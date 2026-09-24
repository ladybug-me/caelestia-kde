#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Issue #636: apps and user-configured commands must launch through the
# Launch service (shell/utils/Launch.qml). Spawned raw they inherit the
# shell's stdio, which is /dev/null for a detached shell, and Vesktop
# deadlocks in exactly that state (issue #402).
GUARDED_QML=(
    "$REPO_ROOT/shell/modules/session/Content.qml"
    "$REPO_ROOT/shell/modules/launcher/services/Actions.qml"
    "$REPO_ROOT/shell/modules/launcher/Content.qml"
)

test_user_command_launches_go_through_the_launch_service() {
    local file qml
    for file in "${GUARDED_QML[@]}"; do
        qml="$(cat "$file")" || {
            fail "could not read $file"
            continue
        }
        assert_not_contains "$qml" "Quickshell.execDetached" "$file must not spawn via Quickshell.execDetached (see shell/utils/Launch.qml)"
        assert_not_contains "$qml" "Process {" "$file must not spawn via an inline Quickshell Process (see shell/utils/Launch.qml)"
        assert_contains "$qml" "Launch.exec(" "$file should route app and user-command launches through Launch.exec"
    done
}

test_the_launch_service_keeps_its_wrapping_contract() {
    local launch
    launch="$(cat "$REPO_ROOT/shell/utils/Launch.qml")"

    assert_contains "$launch" "function wrap(command: list<string>): list<string>" "wrap() is what keeps launched apps off the shell's stdio"
    assert_contains "$launch" "function exec(command: list<string>): void" "exec() is the entry point the guarded files call"
}

run_tests
