#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFS="$REPO_ROOT/shell/services/Notifs.qml"
LOCK_UI="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml"
NOTIF_SYNC="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen/components/NotifSync.qml"
SHELL_CALL="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen/components/ShellCall.qml"

test_shell_exposes_live_snapshot_over_ipc() {
    local content
    content="$(cat "$NOTIFS")"

    assert_contains "$content" 'function list(): string' \
        "Notifs should expose an IPC snapshot for out-of-process views"
    assert_contains "$content" 'function toPlainList(): var' \
        "the snapshot and the persisted history must share one description of a notification"
    assert_contains "$content" 'quiet: root.quiet' \
        "the snapshot must carry the quiet state alongside the items"
    assert_contains "$content" 'items: root.toPlainList()' \
        "the snapshot's items must come from the shared description"
    assert_contains "$content" 'target: "notifs"' \
        "the snapshot must live on the notifs IPC target"
}

test_quiet_is_one_state_with_named_holders() {
    local content
    content="$(cat "$NOTIFS")"

    assert_contains "$content" 'function setDndHold(reason: string, held: bool): void' \
        "features must claim quiet by name instead of writing the user's switch"
    assert_contains "$content" 'readonly property bool quiet:' \
        "one derived state answers whether popups stay quiet"
    assert_contains "$content" 'property alias dnd: props.dnd' \
        "the user's own switch stays theirs, and stays persisted"

    local holder_file
    for holder_file in "$REPO_ROOT/shell/services/Focus.qml" \
        "$REPO_ROOT/shell/services/StreamMonitor.qml" \
        "$REPO_ROOT/shell/modules/sidebar/DinoGame.qml"; do
        assert_file_contains "$holder_file" 'Notifs.setDndHold(' \
            "every feature that wants quiet holds it by name"
    done
}

test_lockscreen_takes_quiet_from_the_snapshot() {
    local sync ui
    sync="$(cat "$NOTIF_SYNC")"
    ui="$(cat "$LOCK_UI")"

    assert_contains "$sync" 'root.quiet = snapshot.quiet === true' \
        "the lock screen must take the quiet state from the shell's snapshot"
    assert_contains "$sync" 'root.items = snapshot.items' \
        "and the list from the same snapshot"
    assert_contains "$ui" 'liveNotifs: notifSync.items' \
        "the dock must render the snapshot the component holds"
}

test_the_lock_screen_game_holds_quiet_by_name() {
    local sync ui
    sync="$(cat "$NOTIF_SYNC")"
    ui="$(cat "$LOCK_UI")"

    assert_contains "$sync" 'notifs setDndHold lockGame' \
        "the dino game's request must name its own reason, so the user's switch survives"
    assert_contains "$ui" 'onDndRequested: enabled => notifSync.setGameQuiet(enabled)' \
        "the game's request must reach the component, not be dropped"
    assert_not_contains "$ui" '_dndBeforeGame' \
        "the shell remembers who asked; the page must not"
}

test_lockscreen_reads_the_live_snapshot_not_the_persisted_file() {
    local sync ui
    sync="$(cat "$NOTIF_SYNC")"
    ui="$(cat "$LOCK_UI")"

    assert_contains "$sync" 'notifs list' \
        "the lock screen must poll the shell for the live list"
    assert_not_contains "$sync" 'cat ~/.local/state/caelestia/notifs.json' \
        "the lock screen must not read the debounced persistence file"
    assert_not_contains "$ui" 'cat ~/.local/state/caelestia/notifs.json' \
        "nor may the page"
    assert_not_contains "$sync" 'notifsClearedAt' \
        "clear-all must not need a local timestamp filter"
    assert_not_contains "$sync" 'isClearingNotifs' \
        "clear-all must not need a local suppression latch"
}

test_lockscreen_clears_through_the_shell() {
    local sync
    sync="$(cat "$NOTIF_SYNC")"

    assert_contains "$sync" 'notifs clear' \
        "clearing from the lock screen must go through the shell so the desktop page follows"
}

test_the_ipc_call_boilerplate_lives_in_one_component() {
    local call ui
    call="$(cat "$SHELL_CALL")"
    ui="$(cat "$LOCK_UI")"

    assert_contains "$call" 'function send(request: string): void' \
        "one component owns how the greeter calls the shell"
    assert_contains "$call" 'root.replied(data["stdout"] || "")' \
        "and hands back stdout alone, never the engine's stderr"
    assert_not_contains "$ui" 'caelestia-shell-ipc' \
        "the page must not spell out the IPC binary for each call"
    assert_not_contains "$ui" 'ipcBin' \
        "the component owns the IPC path"
}

run_tests