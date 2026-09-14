#!/usr/bin/env bash
# test_autostart_unit.sh - Tests for the one mechanism that starts the shell.
#
# parity-6: the shell starts from a single systemd user unit enabled by `caelestia
# install`, not from a desktop entry that KDE's xdg-autostart generator turns into a
# second unit. These tests read the files that must agree on that: the unit name, who
# writes, restarts and removes it, and the package that ships the other copy.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOSTART_SCRIPT="$REPO_ROOT/scripts/10-autostart.sh"
BUILD_SCRIPT="$REPO_ROOT/scripts/08-build-shell.sh"
RESTART_SCRIPT="$REPO_ROOT/shell/scripts/restart_shell.sh"
UNINSTALL_SCRIPT="$REPO_ROOT/uninstall.sh"
IPC="$REPO_ROOT/src/bin/caelestia-shell-ipc"
PKGBUILD="$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD"
PACKAGED_UNIT="$REPO_ROOT/packaging/aur/caelestia-kde/caelestia-shell.service"

test_the_checkout_writes_the_unit_instead_of_an_entry() {
    local script
    script="$(cat "$AUTOSTART_SCRIPT")"

    assert_contains "$script" 'config/systemd/user/caelestia-shell.service' "the checkout's install should write the shell's unit"
    assert_contains "$script" 'ExecStart=%h/.local/bin/caelestia-autostart.sh' "and the unit should run the wrapper that sets the environment"
    assert_contains "$script" 'systemctl --user enable caelestia-shell.service' "and enable it, so it starts on the next login"

    # The entry's writer is gone, but the KWin interface entry further down is a
    # different file that must stay: it decides whether KWin offers screencasting.
    assert_not_contains "$script" 'AUTOSTART_DIR/caelestiashell.desktop" << EOF' "it must not write the retired autostart entry"
    assert_contains "$script" 'applications/quickshell.desktop' "while the KWin interface entry it writes stays"
}

test_an_older_entry_and_its_generated_unit_are_retired() {
    local script
    script="$(cat "$AUTOSTART_SCRIPT")"

    assert_contains "$script" 'AUTOSTART_DIR/caelestiashell.desktop' "an install that still has the old entry should have it removed"
    assert_contains "$script" 'disable app-caelestiashell@autostart.service' "and the unit the generator made from it disabled"
}

test_the_ordering_the_entry_phase_provided_is_kept() {
    # The shell registers org.freedesktop.Notifications, and apps decide once at
    # startup whether a server exists. The entry bought that with
    # X-KDE-AutostartPhase=1; the unit with an ordering against the target the
    # generator puts app units in.
    assert_contains "$(cat "$AUTOSTART_SCRIPT")" 'Before=xdg-desktop-autostart.target' "the checkout's unit should keep the apps behind it"
    assert_contains "$(cat "$PACKAGED_UNIT")" 'Before=xdg-desktop-autostart.target' "and so should the package's"
}

test_the_wrapper_takes_its_paths_from_the_install_layout() {
    # These paths used to be written out in three places, which is how the command
    # came to name a checkout's directories on a packaged machine. They come from
    # install-kind.sh now; test_install_paths.sh covers the values themselves.
    local script
    script="$(cat "$AUTOSTART_SCRIPT")"

    assert_contains "$script" 'SHELL_CONFIG="$(install_shell_config)"' "the autostart step should ask where the shell's entrypoint is"
    assert_contains "$script" 'QML_IMPORT_PATH="$(install_qml_import_path)"' "and where its QML modules are"
    assert_contains "$script" 'BIN_DIR="$(install_bin_dir)"' "and where the command is"
    assert_not_contains "$script" '/etc/xdg/quickshell/caelestia' "the step must not name a path itself"
    assert_not_contains "$script" '/usr/lib/qt6/qml' "not even the package's"

    # The wrapper is generated, so what it exports is text this script writes.
    assert_contains "$script" 'export QML2_IMPORT_PATH="$QML_IMPORT_PATH"' "the wrapper should carry the environment into everything the shell spawns"
    assert_contains "$script" 'exec "$QUICKSHELL_PATH" -n -p "$SHELL_CONFIG"' "and start the entrypoint the install named"
    assert_not_contains "$script" 'exec "$QUICKSHELL_PATH" -n -p "$HOME/.config/quickshell/caelestia/shell.qml"' "rather than a checkout's path on every machine"
}

test_the_environment_writer_uses_the_same_layout() {
    # The environment the session reads and the wrapper the unit runs have to agree on
    # where the install put things; they agree by both asking install-kind.sh.
    local script
    script="$(cat "$BUILD_SCRIPT")"

    assert_contains "$script" 'QML2_IMPORT_PATH=$(install_qml_import_path)' "the session environment should ask for the layout"
    assert_contains "$script" 'CAELESTIA_LIB_DIR=$(install_lib_dir)' "as should the library directory"
    assert_contains "$script" 'CAELESTIA_BIN_DIR=$(install_bin_dir)' "and the command directory"
    assert_contains "$script" 'CAELESTIA_SHELL_CONFIG=$(install_shell_config)' "and the entrypoint"
    assert_not_contains "$script" 'QML2_IMPORT_PATH=/usr/lib/qt6/qml' "and must not carry its own copy of the values"
}

test_an_install_clears_a_failed_unit_before_using_it() {
    # Removing the package leaves this unit enabled pointing at a gone tree: five failed
    # starts, then `start-limit-hit`, after which systemd refuses to start it until it is
    # reset. An install repairing the machine is what finds it that way, so it must clear
    # it - otherwise the run reports success and the shell cannot start.
    local script
    script="$(cat "$AUTOSTART_SCRIPT")"
    assert_contains "$script" 'systemctl --user reset-failed caelestia-shell.service' "the autostart step should clear a failed unit"
}

test_restarting_goes_through_that_unit() {
    local script
    script="$(cat "$RESTART_SCRIPT")"

    assert_contains "$script" 'systemctl --user restart caelestia-shell.service' "the shell's restart action should restart the login unit"
    assert_not_contains "$script" 'restart app-caelestiashell@autostart.service' "and not the unit the retired entry generated"
}

test_a_dead_enable_link_does_not_survive_an_install() {
    # Removing the user's copy leaves the enable link behind, and systemd counts a unit
    # as enabled whenever a link of that name exists, however dead - so `enable` leaves it
    # alone instead of repairing it. That link starts the unit at login, so it must be
    # dropped and rewritten against the unit that survived.
    local script
    script="$(cat "$AUTOSTART_SCRIPT")"

    assert_contains "$script" '"$HOME"/.config/systemd/user/*.wants/caelestia-shell.service' "the install should look at the links that enable the unit"
    assert_contains "$script" '[[ -e "$link" ]] && continue' "and drop the ones whose file is gone"
}

test_uninstall_removes_and_disables_the_unit() {
    local script
    script="$(cat "$UNINSTALL_SCRIPT")"

    assert_contains "$script" 'disable --now caelestia-shell.service' "the unit should be stopped and disabled before its file goes"
    assert_contains "$script" 'rm -f "$USER_SYSTEMD/caelestia-shell.service"' "and removed"
    assert_contains "$script" 'disable app-caelestiashell@autostart.service' "the retired generated unit should be disabled too"

    # Disabled by name, before the check for a user-owned copy: a package's unit belongs
    # to pacman, so there is no copy to test for, while the enable link exists either way.
    local disable_line file_line
    disable_line="$(grep -n 'systemctl --user disable --now caelestia-shell.service' "$UNINSTALL_SCRIPT" | cut -d: -f1)"
    file_line="$(grep -n 'if \[\[ -f "\$USER_SYSTEMD/caelestia-shell.service" \]\]' "$UNINSTALL_SCRIPT" | cut -d: -f1)"
    assert_ne "" "$disable_line" "the disable should not be conditional on that copy"
    assert_ne "" "$file_line" "and the copy is still removed when there is one"
    assert_eq "1" "$(( ${disable_line:-0} < ${file_line:-0} ))" "the disable has to come before that check, not inside it"

    # And the link, for the case where the unit's file is already gone and `disable`
    # cannot resolve it: a link with the unit's name is what systemd counts.
    assert_contains "$script" '"$HOME"/.config/systemd/user/*.wants/caelestia-shell.service' "uninstall should clear the enable link pacman does not own"
    assert_contains "$script" '[[ -e "$link" ]] && continue' "and only the ones whose file is gone"
}

test_the_package_ships_the_unit_and_not_an_entry() {
    local pkgbuild
    pkgbuild="$(cat "$PKGBUILD")"

    assert_contains "$pkgbuild" 'usr/lib/systemd/user/caelestia-shell.service' "the package should install the unit"
    assert_not_contains "$pkgbuild" '$pkgdir/etc/xdg/autostart' "and must not install an autostart entry beside it"
    assert_contains "$(cat "$PACKAGED_UNIT")" 'ExecStart=/usr/bin/caelestia-autostart' "the package's unit should run the package's wrapper"
}

test_the_ipc_start_helper_does_not_take_the_login_units_name() {
    # A transient unit cannot take a name a loaded unit already has, so `caelestia shell`
    # must not use caelestia-shell while caelestia-shell.service exists.
    local ipc
    ipc="$(cat "$IPC")"

    assert_contains "$ipc" '--unit="caelestia-shell-start"' "the transient start helper should use a name of its own"
    assert_not_contains "$ipc" '--unit="caelestia-shell"' "and not the login unit's"
}

run_tests
