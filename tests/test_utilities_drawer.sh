#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WINDOW="$REPO_ROOT/shell/modules/drawers/ContentWindow.qml"
PANELS="$REPO_ROOT/shell/modules/drawers/Panels.qml"
NOTIFS="$REPO_ROOT/shell/modules/notifications/Content.qml"

test_the_window_takes_the_keyboard_from_the_panels_it_holds() {
    local panels window
    panels="$(cat "$PANELS")"
    window="$(cat "$WINDOW")"

    assert_contains "$panels" 'readonly property bool wantsKeyboard:' \
        "the panels are the ones that know whether any of them owns a text field"
    assert_contains "$panels" 'utilities.offsetScale < 1' \
        "the timers are text fields, so the drawer has to be in that answer"
    assert_contains "$panels" 'The OSD is deliberately absent' \
        "and the exception has to be written down, or the next panel guesses"
    assert_contains "$window" 'readonly property bool wantsKeyboard: panels.wantsKeyboard' \
        "the window asks them instead of keeping its own list"
}

test_the_stack_takes_one_room_measurement() {
    local panels notifs
    panels="$(cat "$PANELS")"
    notifs="$(cat "$NOTIFS")"

    assert_contains "$panels" 'readonly property real notifRoom:' \
        "the panels are the only place that holds every panel in one coordinate space"
    assert_contains "$notifs" 'readonly property bool empty: list.count === 0' \
        "an empty stack is a state the stack itself names"
    assert_contains "$notifs" 'implicitHeight: root.empty ? 0 :' \
        "and while it is empty the stack collapses to nothing, rather than to its padding"
    assert_contains "$notifs" 'Math.min(root.contentHeight + root.padding + root.clampedPadding, root.room)' \
        "the stack clamps what it wants to the room it is given, and says both plainly"
    assert_not_contains "$notifs" 'osdPanel' \
        "it must not measure the panels itself"
    assert_not_contains "$notifs" 'utilitiesPanel' \
        "for any of them"
}

test_the_two_panels_are_kept_out_of_one_blob_once() {
    local window
    window="$(cat "$WINDOW")"

    assert_contains "$window" 'exclude: [utilsBg]' \
        "a notification background must not bridge into the drawer's behind it"
    assert_not_contains "$window" 'notifsBg]' \
        "exclusion is symmetric, so one side saying it is enough"
}

run_tests