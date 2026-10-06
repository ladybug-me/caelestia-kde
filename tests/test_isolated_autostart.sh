#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOSTART_SCRIPT="$REPO_ROOT/scripts/10-autostart.sh"

run_autostart() {
    local home="$1" stub_dir="$2" log="$3"
    HOME="$home" BUNDLE_DIR="$REPO_ROOT" PATH="$stub_dir:$PATH" \
        bash "$AUTOSTART_SCRIPT" > "$home/run.log" 2>&1
    printf '%s\n' "$?"
}

test_autostart_isolated_and_idempotent() {
    local root home stub_dir log first_hash second_hash status
    root="$(new_tmpdir)"
    home="$root/home"
    stub_dir="$root/bin"
    log="$root/systemctl.log"
    mkdir -p "$home/.config/quickshell/caelestia" "$stub_dir"
    : > "$home/.config/quickshell/caelestia/shell.qml"

    stub_bin "$stub_dir" quickshell 'exit 0'
    stub_bin "$stub_dir" systemctl "printf '%s\n' \"\$*\" >> '$log'; exit 0"

    status="$(run_autostart "$home" "$stub_dir" "$log")"
    assert_status 0 "$status" "the isolated autostart step should succeed"
    assert_file_exists "$home/.local/bin/caelestia-autostart.sh"
    assert_file_exists "$home/.config/systemd/user/caelestia-shell.service"
    assert_file_exists "$home/.local/share/applications/quickshell.desktop"
    assert_contains "$(cat "$home/.config/systemd/user/caelestia-shell.service")" \
        'ExecStart=%h/.local/bin/caelestia-autostart.sh' \
        "the generated unit should use the isolated home layout"
    assert_contains "$(cat "$home/.local/bin/caelestia-autostart.sh")" \
        "export QML2_IMPORT_PATH=\"$home/.local/lib/qt6/qml:$home/.config/quickshell/caelestia\"" \
        "the wrapper should carry the isolated import path"
    assert_contains "$(cat "$log")" '--user enable caelestia-shell.service' \
        "the unit should be enabled through systemctl"

    first_hash="$(sha256sum "$home/.config/systemd/user/caelestia-shell.service" "$home/.local/bin/caelestia-autostart.sh")"
    status="$(run_autostart "$home" "$stub_dir" "$log")"
    assert_status 0 "$status" "repeating the isolated autostart step should succeed"
    second_hash="$(sha256sum "$home/.config/systemd/user/caelestia-shell.service" "$home/.local/bin/caelestia-autostart.sh")"
    assert_eq "$first_hash" "$second_hash" "repeating the step should keep generated file hashes stable"
}

run_tests
