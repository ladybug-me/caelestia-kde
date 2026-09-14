#!/usr/bin/env bash
# test_install_paths.sh - Tests for the one definition of where an install keeps its files.
#
# The layout used to be written in three places, and the command's copy was the
# checkout's unconditionally: on a packaged machine it put ~/.config/quickshell/caelestia
# ahead of the installed tree for everything it spawned. These tests run the library that
# owns the layout now, plus the command, for both kinds.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/install-kind.sh"
CLI="$REPO_ROOT/src/bin/caelestia"

# layout <kind> <function>: what that function answers for that kind of install.
layout() {
    CAELESTIA_INSTALL_KIND="$1" BUNDLE_DIR="$REPO_ROOT" LAYOUT_LIB="$LIB" LAYOUT_FN="$2" \
        bash -c '
            set -u
            source "$LAYOUT_LIB"
            "$LAYOUT_FN"
        '
}

# cli_env <bin dir> <home>: what the command exports for everything it spawns, decided
# from where the command is - which is the whole of the inference it does.
#
# Sourced with its path in $0 and nothing in $@: a sourced script inherits the
# caller's positional parameters, and this one ends by calling main "$@", so an
# argument would run as a subcommand and exit. stdout is silenced so the usage text
# does not become the answer.
cli_env() {
    env -u QML2_IMPORT_PATH -u CAELESTIA_LIB_DIR -u CAELESTIA_INSTALL_KIND \
        HOME="$2" XDG_CONFIG_HOME="$2/.config" CAELESTIA_BIN_DIR="$1" \
        bash -c 'source "$0" >/dev/null 2>&1; printf "%s|%s" "$QML2_IMPORT_PATH" "$CAELESTIA_LIB_DIR"' \
        "$CLI"
}

test_the_packaged_layout_is_the_packages_directories() {
    assert_eq "/etc/xdg/quickshell/caelestia/shell.qml" "$(layout package install_shell_config)" "the shell tree"
    assert_eq "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia" "$(layout package install_qml_import_path)" "the QML import path"
    assert_eq "/usr/lib/caelestia" "$(layout package install_lib_dir)" "the library directory"
    assert_eq "/usr/bin" "$(layout package install_bin_dir)" "the command directory"
}

test_the_checkout_layout_is_the_users_own_directories() {
    assert_eq "$HOME/.config/quickshell/caelestia/shell.qml" "$(layout source install_shell_config)" "the shell tree"
    assert_eq "$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia" "$(layout source install_qml_import_path)" "the QML import path"
    assert_eq "$HOME/.local/lib/caelestia" "$(layout source install_lib_dir)" "the library directory"
    assert_eq "$HOME/.local/bin" "$(layout source install_bin_dir)" "the command directory"
}

test_no_path_is_the_same_in_both_layouts() {
    # A copy-paste that left the checkout's value in the package's branch would silently
    # point a package at a directory it never creates.
    local fn
    for fn in install_shell_config install_qml_import_path install_lib_dir install_bin_dir; do
        assert_ne "$(layout source "$fn")" "$(layout package "$fn")" "$fn should differ between the two installs"
    done
}

test_the_kind_can_be_stated_rather_than_inferred() {
    # The front end that runs the steps says which half they are, and the answer has to
    # win over where the library happens to sit.
    assert_eq "package" "$(layout package install_kind)" "the environment's answer wins"
    assert_eq "source" "$(layout source install_kind)" "in both directions"
}

test_the_command_names_the_installs_own_directories() {
    # The bug this replaced: the command exported the checkout's paths everywhere, so a
    # packaged install spawned its shell with ~/.config/quickshell/caelestia ahead of
    # /etc/xdg, losing /usr/lib/qt6/qml from the import path.
    assert_eq "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia|/usr/lib/caelestia" \
        "$(cli_env /usr/bin "$HOME")" "a command in /usr/bin belongs to a package"

    local home out
    home="$(new_tmpdir)/home"
    out="$(cli_env "$home/.local/bin" "$home")"
    assert_eq "$home/.local/lib/qt6/qml:$home/.config/quickshell/caelestia|$home/.local/lib/caelestia" \
        "$out" "and one anywhere else belongs to a checkout, from that user's home"
}

test_the_command_prefers_what_the_session_told_it() {
    # A session gets these from ~/.config/environment.d, written for the install it
    # belongs to. They are what the command appends to, not what it overrides.
    local dir
    dir="$(new_tmpdir)"
    local out
    out="$(env HOME="$dir/home" XDG_CONFIG_HOME="$dir/home/.config" CAELESTIA_BIN_DIR=/usr/bin \
        QML2_IMPORT_PATH=/from/the/session CAELESTIA_LIB_DIR=/from/the/session \
        bash -c 'source "$0" >/dev/null 2>&1; printf "%s|%s" "$QML2_IMPORT_PATH" "$CAELESTIA_LIB_DIR"' \
        "$CLI")"

    assert_eq "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia:/from/the/session|/from/the/session" \
        "$out" "the session's values should survive"
}

test_the_version_comes_from_the_installed_helper() {
    # Both upstream's CLI and this one read the helper CMake installs into INSTALL_LIBDIR:
    # the number is compiled in, so a package reports what pacman installed. A copy of
    # version.env beside the config went stale between an upgrade and `caelestia install`.
    local dir home out
    dir="$(new_tmpdir)"
    home="$dir/home"
    mkdir -p "$dir/lib" "$home"
    printf '#!/bin/sh\nprintf "caelestia-shell 9.9.9, revision deadbeef\\n"\n' > "$dir/lib/version"
    chmod +x "$dir/lib/version"

    out="$(env -u CAELESTIA_INSTALL_KIND HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        CAELESTIA_BIN_DIR="$home/.local/bin" CAELESTIA_LIB_DIR="$dir/lib" "$CLI" version 2>&1)"
    assert_eq "caelestia v9.9.9" "$out" "the helper's version should be reported, with the tag's v"
}

test_a_checkout_with_no_helper_reports_its_version_file() {
    # A tree that has not been built yet has no helper to ask, and answers from the
    # repository's own version.env - the source of truth, not a copy of it.
    local dir home expected out
    dir="$(new_tmpdir)"
    home="$dir/home"
    mkdir -p "$dir/empty" "$home"
    expected="$(awk -F= '$1 == "VERSION" { print $2; exit }' "$REPO_ROOT/.github/version.env")"
    assert_ne "" "$expected" "the repository should carry a version"

    out="$(env -u CAELESTIA_INSTALL_KIND HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        CAELESTIA_BIN_DIR="$home/.local/bin" CAELESTIA_LIB_DIR="$dir/empty" "$CLI" version 2>&1)"
    assert_eq "caelestia $expected" "$out" "a checkout with no helper should fall back to its version file"
}

test_the_command_asks_the_install_for_its_version() {
    # It used to count directory levels up from wherever it was, guessing at a checkout's
    # shape, then read a version.env copy an upgrade could leave behind.
    local cli
    cli="$(cat "$CLI")"
    assert_contains "$cli" '"$CAELESTIA_LIB_DIR/version" -s' "the version should come from the installed helper"
    assert_not_contains "$cli" 'quickshell/caelestia/version.env' "not from a copy beside the config"
    assert_not_contains "$cli" '$BIN_DIR/../../.github/version.env' "and not from walking up from itself"
    assert_not_contains "$cli" '$BIN_DIR/../../../.github/version.env' "at two depths either"
}

run_tests
