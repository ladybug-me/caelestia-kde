#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAYERS="$REPO_ROOT/shell/services/Players.qml"
LOCK_UI="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml"

test_shell_exposes_media_status_over_ipc() {
    local content
    content="$(cat "$PLAYERS")"

    assert_contains "$content" 'function status(): string' \
        "Players should expose an IPC snapshot for out-of-process views"
    assert_contains "$content" 'target: "mpris"' \
        "the snapshot must live on the mpris IPC target"
}

test_lockscreen_polls_the_media_snapshot() {
    local content
    content="$(cat "$LOCK_UI")"

    assert_contains "$content" 'send("mpris status")' \
        "the lock screen must poll the shell for the live media state"
    assert_not_contains "$content" 'call mpris getActive' \
        "the lock screen must not fetch media fields one call at a time"
}

run_tests
