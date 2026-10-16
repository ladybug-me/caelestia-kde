#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$REPO_ROOT/installer/src/steps/build_shell.rs"
RESTART_SCRIPT="$REPO_ROOT/shell/scripts/restart_shell.sh"
UNINSTALL_STEP="$REPO_ROOT/installer/src/uninstall.rs"
IPC="$REPO_ROOT/src/bin/caelestia-shell-ipc"
PKGBUILD="$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD"
PACKAGED_UNIT="$REPO_ROOT/packaging/aur/caelestia-kde/caelestia-shell.service"

test_the_packaged_unit_keeps_the_apps_behind_the_shell() {
    assert_contains "$(cat "$PACKAGED_UNIT")" 'Before=xdg-desktop-autostart.target' "the package's unit should keep the apps behind it"
}

test_the_environment_writer_uses_the_same_layout() {
    # The environment the session reads and the wrapper the unit runs have to agree on where
    # the install put things; they agree by both asking install-kind. The writer is the
    # native build step now, so the source of truth is its Rust.
    local script
    script="$(cat "$BUILD_SCRIPT")"

    assert_contains "$script" 'install_kind::qml_import_path()' "the session environment should ask for the layout"
    assert_contains "$script" 'install_kind::lib_dir()' "as should the library directory"
    assert_contains "$script" 'install_kind::bin_dir()' "and the command directory"
    assert_contains "$script" 'export PATH=\"' "which the session should also put on PATH"
    assert_contains "$script" 'install_kind::shell_config()' "and the entrypoint"
    assert_contains "$script" 'plasma-workspace' "the Plasma session environment should be written"
    assert_contains "$(cat "$UNINSTALL_STEP")" 'plasma-workspace/env/caelestia.sh' "uninstall should clean up the Plasma environment script"
    assert_not_contains "$script" '/usr/lib/qt6/qml' "and must not carry its own copy of the values"
}

test_restarting_goes_through_that_unit() {
    local script
    script="$(cat "$RESTART_SCRIPT")"

    assert_contains "$script" 'systemctl --user restart caelestia-shell.service' "the shell's restart action should restart the login unit"
    assert_not_contains "$script" 'restart app-caelestiashell@autostart.service' "and not the unit the retired entry generated"
}

test_uninstall_removes_and_disables_the_unit() {
    local script
    script="$(cat "$UNINSTALL_STEP")"

    assert_contains "$script" '"--now", "caelestia-shell.service"' "the unit should be stopped and disabled"
    assert_contains "$script" 'remove_file(&shell_unit)' "and its file removed"
    assert_contains "$script" '"app-caelestiashell@autostart.service"' "the retired generated unit should be disabled too"

    # Disabled by name, before the check for a user-owned copy: a package's unit belongs
    # to pacman, so there is no copy to test for, while the enable link exists either way.
    local disable_line file_line
    disable_line="$(grep -n '"--now", "caelestia-shell.service"' "$UNINSTALL_STEP" | cut -d: -f1)"
    file_line="$(grep -n 'remove_file(&shell_unit)' "$UNINSTALL_STEP" | cut -d: -f1)"
    assert_ne "" "$disable_line" "the disable should not be conditional on that copy"
    assert_ne "" "$file_line" "and the copy is still removed when there is one"
    assert_eq "1" "$(( ${disable_line:-0} < ${file_line:-0} ))" "the disable has to come before that check, not inside it"

    # And the link, for the case where the unit's file is already gone and `disable`
    # cannot resolve it: a link with the unit's name is what systemd counts.
    assert_contains "$script" 'caelestia-shell.service"' "uninstall should clear the enable link pacman does not own"
    assert_contains "$script" 'ends_with(".wants")' "and look in the wants directories it finds"
    assert_contains "$script" '!link.exists()' "and only the ones whose file is gone"
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
