#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/install-kind.sh"
CLI="$REPO_ROOT/src/bin/caelestia"
IPC_HELPER="$REPO_ROOT/src/bin/caelestia-shell-ipc"

layout() {
    CAELESTIA_INSTALL_KIND="$1" BUNDLE_DIR="$REPO_ROOT" LAYOUT_LIB="$LIB" LAYOUT_FN="$2" \
        bash -c '
            set -u
            source "$LAYOUT_LIB"
            "$LAYOUT_FN"
        '
}

cli_env() {
    env -u QML2_IMPORT_PATH -u CAELESTIA_LIB_DIR -u CAELESTIA_INSTALL_KIND \
        HOME="$2" XDG_CONFIG_HOME="$2/.config" CAELESTIA_BIN_DIR="$1" \
        bash -c 'source "$0" >/dev/null 2>&1; printf "%s|%s" "$QML2_IMPORT_PATH" "$CAELESTIA_LIB_DIR"' \
        "$CLI"
}

ipc_defaults() {
    # $1 = stub dir, $2 = home, $3 = the config path to resolve the defaults for
    env -u QML2_IMPORT_PATH -u CAELESTIA_LIB_DIR -u CAELESTIA_INSTALL_KIND \
        PATH="$1:$PATH" HOME="$2" XDG_CONFIG_HOME="$2/.config" \
        CAELESTIA_SHELL_CONFIG="$2/.config/quickshell/caelestia/shell.qml" \
        bash -c 'source "$0" >/dev/null 2>&1
                 SHELL_CONFIG="$1"
                 _export_shell_env
                 printf "%s|%s" "$QML2_IMPORT_PATH" "$CAELESTIA_LIB_DIR"' \
        "$IPC_HELPER" "$3"
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
    local fn
    for fn in install_shell_config install_qml_import_path install_lib_dir install_bin_dir; do
        assert_ne "$(layout source "$fn")" "$(layout package "$fn")" "$fn should differ between the two installs"
    done
}

test_the_kind_can_be_stated_rather_than_inferred() {
    assert_eq "package" "$(layout package install_kind)" "the environment's answer wins"
    assert_eq "source" "$(layout source install_kind)" "in both directions"
}

test_the_kind_survives_walking_into_another_directory() {
    local dir out
    dir="$(new_tmpdir)"
    mkdir -p "$dir/elsewhere"

    out="$(cd "$REPO_ROOT" && bash -c '
        set -u
        source scripts/lib/install-kind.sh
        cd "$1" || exit 1
        printf "%s|%s" "$(install_shell_config)" "$(install_lib_dir)"
    ' _ "$dir/elsewhere" 2>&1)"

    assert_not_contains "$out" "[ERR]" "answering from another directory should not complain"
    assert_eq "$HOME/.config/quickshell/caelestia/shell.qml|$HOME/.local/lib/caelestia" "$out" \
        "and a checkout's directories should still be the answer"
}

test_the_command_names_the_installs_own_directories() {
    assert_eq "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia|/usr/lib/caelestia" \
        "$(cli_env /usr/bin "$HOME")" "a command in /usr/bin belongs to a package"

    local home out
    home="$(new_tmpdir)/home"
    out="$(cli_env "$home/.local/bin" "$home")"
    assert_eq "$home/.local/lib/qt6/qml:$home/.config/quickshell/caelestia|$home/.local/lib/caelestia" \
        "$out" "and one anywhere else belongs to a checkout, from that user's home"
}

test_the_command_prefers_what_the_session_told_it() {
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
    local cli
    cli="$(cat "$CLI")"
    assert_contains "$cli" '"$CAELESTIA_LIB_DIR/version" -s' "the version should come from the installed helper"
    assert_not_contains "$cli" 'quickshell/caelestia/version.env' "not from a copy beside the config"
    assert_not_contains "$cli" '$BIN_DIR/../../.github/version.env' "and not from walking up from itself"
    assert_not_contains "$cli" '$BIN_DIR/../../../.github/version.env' "at two depths either"
}

test_a_package_with_no_version_helper_reports_unknown() {
    local dir home status out
    dir="$(new_tmpdir)"
    home="$dir/home"
    mkdir -p "$dir/empty" "$home"

    out="$(env CAELESTIA_INSTALL_KIND=package HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        CAELESTIA_BIN_DIR=/usr/bin CAELESTIA_LIB_DIR="$dir/empty" "$CLI" version 2>&1)"
    status=$?

    assert_status 0 "$status" "a package with no version helper should still answer"
    assert_eq "caelestia unknown" "$out" "and report unknown rather than fail"
}

test_a_package_does_not_run_a_checkout_it_was_not_pointed_at() {
    local dir home out
    dir="$(new_tmpdir)"
    home="$dir/home"
    mkdir -p "$home/caelestia-kde"
    printf '#!/bin/sh\necho RAN-THE-CHECKOUT-INSTALLER\n' > "$home/caelestia-kde/install.sh"
    chmod +x "$home/caelestia-kde/install.sh"

    out="$(env CAELESTIA_INSTALL_KIND=package HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        CAELESTIA_DATA_DIR="$dir/no-scripts" "$CLI" install 2>&1 || true)"
    assert_not_contains "$out" "RAN-THE-CHECKOUT-INSTALLER" "a package must not run ~/caelestia-kde/install.sh"

    out="$(env CAELESTIA_INSTALL_KIND=source CAELESTIA_DIR="$home/caelestia-kde" HOME="$home" \
        XDG_CONFIG_HOME="$home/.config" "$CLI" install 2>&1 || true)"
    assert_contains "$out" "RAN-THE-CHECKOUT-INSTALLER" "a checkout named explicitly still runs its installer"
}

test_the_ipc_helper_defaults_to_the_installs_own_directories() {
    local dir home
    dir="$(new_tmpdir)"
    home="$dir/home"
    mkdir -p "$home/.local/bin" "$home/.config/quickshell/caelestia"
    stub_bin "$dir/stubs" quickshell "exit 0"
    : > "$home/.config/quickshell/caelestia/shell.qml"

    assert_eq "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia|/usr/lib/caelestia" \
        "$(ipc_defaults "$dir/stubs" "$home" /etc/xdg/quickshell/caelestia/shell.qml)" \
        "a packaged shell config should get the package's directories"

    assert_eq "$home/.local/lib/qt6/qml:$home/.config/quickshell/caelestia|$home/.local/lib/caelestia" \
        "$(ipc_defaults "$dir/stubs" "$home" "$home/.config/quickshell/caelestia/shell.qml")" \
        "a checkout's shell config should get the user's directories"
}

run_tests
