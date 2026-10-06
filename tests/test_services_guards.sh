#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="$REPO_ROOT/shell/services"

test_the_periodic_update_check_survives_its_first_run() {
    assert_contains "$SERVICES/UpdateChecker.qml" 'repeat: true' \
        "autoCheckTimer must keep firing every interval"
    assert_not_contains "$SERVICES/UpdateChecker.qml" 'autoCheckTimer.restart()' \
        "gitProcess.onExited must not gate the next check on a timer that already fired"
}

test_discord_presence_survives_a_null_active_window() {
    assert_contains "$SERVICES/DiscordRPC.qml" 'Kwin.activeWindow?.class' \
        "presence updates run exactly when the active window disappears"
}

test_a_corrupt_notification_file_does_not_kill_persistence() {
    assert_contains "$SERVICES/Notifs.qml" 'JSON.parse(text())' "the parse still happens"
    assert_contains "$SERVICES/Notifs.qml" 'saved notifications are corrupt, starting fresh' \
        "but a corrupt store degrades to a fresh list instead of a dead FileView"
    assert_contains "$SERVICES/Notifs.qml" 'if (!Array.isArray(data))' \
        "valid but non-array JSON must also degrade to a fresh list"
}

test_monitor_names_skip_the_injected_values_bucket() {
    assert_contains "$SERVICES/Kwin.qml" 'if (key !== "values")' \
        "the monitors cache carries a synthetic values key that is not a monitor"
}

test_vpn_registration_runs_once_per_auth_wall() {
    assert_contains "$SERVICES/VPN.qml" 'property bool registerSent: false' \
        "needs-auth must be a transition, not a per-poll event"
    assert_contains "$SERVICES/VPN.qml" 'property int statusGen: 0' \
        "and a provider switch must invalidate in-flight status output"
}
