#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
SWITCH="$SHELL_DIR/services/QuickShare.qml"
SETUP="$SHELL_DIR/services/QuickShareSetup.qml"
PAGE="$SHELL_DIR/modules/nexus/pages/services/QuickSharePage.qml"
CARD="$SHELL_DIR/modules/utilities/cards/Toggles.qml"

test_the_switch_state_has_one_home() {
    local file
    for file in "$CARD" "$PAGE"; do
        assert_contains "$(cat "$file")" "QuickShare.enabled" \
            "$(basename "$file") should read the switch state from the service"
    done

    local derived
    derived="$(grep -rn 'QuickShareService.isEnabled ||' "$SHELL_DIR/modules" --include='*.qml' || true)"
    assert_eq "" "$derived" "no view should re-derive whether Quick Share is on"
}

test_the_switch_is_asked_for_in_one_way() {
    local callers
    callers="$(grep -rn 'QuickShare\.\(toggle\|setEnabled\)' "$SHELL_DIR/modules" --include='*.qml' || true)"

    assert_not_contains "$callers" "QuickShare.toggle" \
        "the switch should have one way in, rather than a second entry point that reads the service"
    assert_contains "$callers" "QuickShare.setEnabled" \
        "and it should be the one the gate lives behind"
}

test_the_setup_flow_has_one_owner() {
    assert_file_exists "$SETUP"

    local borrowed
    borrowed="$(grep -n 'shellPath\|--status\|SETUP=\|pkexec' "$SWITCH" || true)"
    assert_eq "" "$borrowed" "the prompt service should not own the system check"

    assert_contains "$(cat "$SETUP")" 'PrivilegedHelpers.path("quickshare_setup.sh")' \
        "the setup service should be the one that runs the helper"
    assert_contains "$(cat "$PAGE")" "QuickShareSetup.status" \
        "and the row should report what that service found"
    assert_contains "$(cat "$PAGE")" "QuickShareSetup.run()" \
        "with the row itself as the way to ask for it by hand"
}

test_the_elevated_helper_is_only_ever_one_root_owns() {
    local helpers="$SHELL_DIR/utils/PrivilegedHelpers.qml"

    assert_file_exists "$helpers"
    assert_contains "$(cat "$helpers")" '"/usr/lib/caelestia/scripts"' \
        "the installer's copy lives outside every tree this user can write"
    assert_contains "$(cat "$helpers")" '[ ! -L "$path" ]' \
        "a symlink is refused rather than read through"
    assert_contains "$(cat "$helpers")" '[[ "$owner" == 0 && "$mode" =~ ^[0-7]+$ ]]' \
        "and only root's copy is ever accepted"
    assert_contains "$(cat "$helpers")" '(( 8#$mode & 8#022 )) -eq 0' \
        "which nobody else may be able to write"

    local elevated
    elevated="$(grep -rn 'pkexec' "$SHELL_DIR" --include='*.qml' || true)"
    assert_not_contains "$elevated" 'Quickshell.shellPath' \
        "nothing elevates the copy that sits next to the shell"
}

# polkit runs whatever path it is handed as root, and the shell inherits PATH from a session
# where a source install puts this user's own bin directory first. A `pkexec`, `bash` or
# `stat` they could write there would be the thing deciding what runs as root, so none of
# them may be looked up.
test_nothing_deciding_what_runs_as_root_comes_from_path() {
    local helpers="$SHELL_DIR/utils/PrivilegedHelpers.qml" body
    body="$(cat "$helpers")"

    assert_contains "$body" "'PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH'" \
        "the ownership check replaces the inherited PATH before it runs anything"
    assert_contains "$body" '/usr/bin/stat -c %u' \
        "and asks stat by absolute path"
    assert_contains "$body" 'command: ["/bin/bash", "-c"' \
        "and runs the check with a bash named by absolute path"
}

test_every_elevation_names_the_program_it_runs() {
    local sites rellooked
    sites="$(grep -rn 'command:.*pkexec' "$SHELL_DIR" --include='*.qml' || true)"

    rellooked="$(printf '%s\n' "$sites" | grep -v '"/usr/bin/pkexec"' || true)"
    assert_eq "" "$rellooked" "every elevation names pkexec by absolute path"

    rellooked="$(printf '%s\n' "$sites" | grep -v '"/bin/bash"' || true)"
    assert_eq "" "$rellooked" "and hands the helper to a bash named by absolute path"

    assert_contains "$sites" 'QuickShareSetup.qml' "the Quick Share helper is one of them"
    assert_contains "$sites" 'AiSettingsPage.qml' "so is the Ollama helper"
}

run_tests
