#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/IdleInhibitor.qml"
WIDGET="$REPO_ROOT/shell/modules/bar/components/KeepAwakeWidget.qml"
CARD="$REPO_ROOT/shell/modules/utilities/cards/IdleInhibit.qml"

test_the_reload_scoped_store_is_not_used_for_it() {
    assert_file_not_contains "$SERVICE" 'reloadableId' \
        "the reload-scoped property store does not survive a restart of the service"
}

test_the_state_is_per_boot_rather_than_permanent() {
    assert_file_contains "$SERVICE" 'Paths.runtimeTemp("keepawake.json")' \
        "the file belongs in the runtime directory: a restart keeps it, a reboot and a new login do not"
}

test_the_only_way_in_writes_the_file() {
    assert_file_contains "$SERVICE" 'function setEnabled(value: bool): void' \
        "toggling has to go through one entry point, so it cannot skip the file"
    assert_file_contains "$SERVICE" 'readonly property bool enabled: root.state.enabled' \
        "and the flag has to be read-only, so nothing can bypass it"

    # One write path is the invariant: a second `setText` would mean something learned
    # to write the file behind the setter's back.
    assert_eq "$(grep -c 'setText' "$SERVICE")" "1" "the file is written in exactly one place"
}

test_every_caller_uses_the_setter() {
    assert_file_not_contains "$WIDGET" 'IdleInhibitor.enabled = ' "the bar widget must not write the flag"
    assert_file_contains "$WIDGET" 'IdleInhibitor.setEnabled(' "the bar widget goes through the setter"
    assert_file_not_contains "$CARD" 'IdleInhibitor.enabled = ' "the utilities card must not write the flag"
    assert_file_contains "$CARD" 'IdleInhibitor.setEnabled(' "the utilities card goes through the setter"
}

test_restoring_cannot_masquerade_as_a_toggle() {
    assert_file_contains "$SERVICE" 'root.state = {' \
        "reading the file replaces the whole value instead of assigning a flag"
    assert_file_contains "$SERVICE" 'onLoaded: root.restore(stateFile.text())' \
        "the file has to be read back on start"
}

test_a_broken_file_does_not_take_the_shell_with_it() {
    assert_file_contains "$SERVICE" 'Logger.log("[IdleInhibitor]' \
        "an unreadable file is reported (under debug logs) rather than swallowed"
    assert_file_contains "$SERVICE" 'isNaN(since.getTime())' \
        "an unparsable timestamp falls back to now instead of throwing"
}

test_the_inhibitor_and_the_ipc_surface_are_unchanged() {
    assert_file_contains "$SERVICE" 'enabled: root.enabled' \
        "the compositor inhibitor stays bound to the restored value"
    assert_file_contains "$SERVICE" 'target: "idleInhibitor"' "the IPC target is unchanged"
    assert_file_contains "$SERVICE" 'function isEnabled(): bool' "and still answers the same question"
}

run_tests