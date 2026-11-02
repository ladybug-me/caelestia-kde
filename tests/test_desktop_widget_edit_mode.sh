#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$REPO_ROOT/shell/modules/background"
ICONS="$DESKTOP/DesktopIcons.qml"
BIG="$DESKTOP/desktopicons/BigItem.qml"
ENGINE="$DESKTOP/desktopicons/LayoutEngine.js"
MENU="$DESKTOP/DesktopContextMenu.qml"
OVERLAY="$DESKTOP/EditModeOverlay.qml"
EDITOR="$REPO_ROOT/shell/services/WidgetEditor.qml"
LAYOUT="$REPO_ROOT/shell/services/DesktopLayout.qml"
SHELL_ROOT="$REPO_ROOT/shell/shell.qml"

# The body of a top-level QML function: from its signature to the closing brace at
# the same indent, so a test can talk about one function rather than a whole file.
function_body() {
    awk -v name="$2" '
        index($0, "function " name "(") { capture = 1 }
        capture { print }
        capture && /^    \}$/ { exit }
    ' "$1"
}

have_node() {
    command -v node >/dev/null 2>&1
}

test_the_mode_has_one_owner() {
    assert_file_contains "$EDITOR" 'property bool active: false' "the mode must belong to the editor"
    assert_file_contains "$EDITOR" 'property var clipboard: []' "a copy must survive a paste on another screen"
    assert_file_contains "$EDITOR" 'target: "desktop"' "the mode must be reachable without the mouse"
    assert_file_missing "$DESKTOP/WidgetEditOverlay.qml"
    assert_file_not_contains "$LAYOUT" 'widgetEditMode' "the layout store must not own the mode"
    assert_file_not_contains "$LAYOUT" 'widgetClipboard' "the layout store must not own the clipboard"
}

test_the_two_modes_stay_exclusive() {
    assert_file_contains "$EDITOR" 'ContextMenuStore.editMode = false;' "entering the widget mode must leave the Plasma one"
    assert_file_contains "$MENU" 'WidgetEditor.close();' "entering the Plasma mode must leave the widget one"
}

test_the_card_has_one_drag_surface() {
    assert_file_not_contains "$BIG" 'id: editArea' "a second MouseArea over the content is what the mode replaces"
    assert_file_contains "$BIG" 'z: root.widgetEditMode ? 1 : 0' "the card's own area must be raised over the content, not copied"
    assert_file_contains "$BIG" 'enabled: !root.widgetEditMode' "the content must stop taking hover, focus and clicks"
    assert_file_contains "$BIG" 'cursorShape: root.widgetEditMode && !root.locked ? Qt.OpenHandCursor' "the raised area must show it can be grabbed"
}

test_the_key_handler_dispatches_the_mode_once() {
    local handle
    handle="$(function_body "$ICONS" handleKey)"
    assert_not_contains "$handle" "widgetEditMode" "the key handler must not grow a mode check per shortcut"
    assert_contains "$handle" "editModeKey(event, ctrl)" "the mode's keys must be dispatched in one place"
    assert_contains "$(function_body "$ICONS" editModeKey)" "WidgetEditor.close();" "Escape must leave the mode"
}

test_adding_and_pasting_share_one_placement() {
    assert_contains "$(function_body "$ICONS" addWidget)" "placeWidgets(" "adding must use the shared placement"
    assert_contains "$(function_body "$ICONS" pasteWidgets)" "placeWidgets(" "pasting must use the shared placement"
    assert_contains "$(function_body "$ICONS" placeWidgets)" "Engine.placeSpecs(" "placement must be the engine's, so it is testable"
    assert_contains "$(function_body "$ICONS" placeWidgets)" "DesktopLayout.autoArrange" "adding and pasting must both honour auto-arrange"
    assert_contains "$(function_body "$ICONS" copyWidgets)" "WidgetEditor.clipboard" "a copy belongs to the editor"
}

test_placement_is_pure_and_never_overlaps() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "a run of specs must not overlap itself, and must not move what is placed" "$ENGINE" Engine '
const cells = Engine.placeSpecs({}, { col: 0, row: 0 }, [{ w: 2, h: 2 }, { w: 2, h: 2 }, { w: 1, h: 1 }], 10, 6, {});
assert.strictEqual(cells.length, 3);
const seen = new Set();
for (const c of cells) {
    assert.ok(c.col >= 0 && c.col + c.w <= 10, "inside the columns");
    assert.ok(c.row >= 0 && c.row + c.h <= 6, "inside the rows");
    for (let x = c.col; x < c.col + c.w; x++)
        for (let y = c.row; y < c.row + c.h; y++) {
            const id = x + "," + y;
            assert.ok(!seen.has(id), "cell " + id + " used twice");
            seen.add(id);
        }
}
const positions = { "w/a": { col: 0, row: 0 } };
const spans = { "w/a": { w: 2, h: 2 } };
const placed = Engine.placeSpecs(positions, { col: 0, row: 0 }, [{ w: 1, h: 1 }], 10, 6, spans);
assert.ok(!(placed[0].col < 2 && placed[0].row < 2), "must clear the card already there");
assert.deepStrictEqual(positions, { "w/a": { col: 0, row: 0 } }, "the caller owns the write");
const clamped = Engine.placeSpecs({}, null, [{ w: 99, h: 99 }], 4, 3, {});
assert.deepStrictEqual(clamped[0], { col: 0, row: 0, w: 4, h: 3 }, "a spec larger than the grid is clamped");'
}

test_the_pill_carries_both_modes() {
    assert_file_contains "$OVERLAY" 'qsTr("Exit Plasma edit mode")' "the Plasma mode keeps its own way out"
    assert_file_contains "$OVERLAY" 'qsTr("Editing widgets")' "the widget mode says which mode it is"
    assert_file_contains "$OVERLAY" 'WidgetEditor.close()' "the toolbar must be a way out"
    assert_file_contains "$OVERLAY" 'enabled: win.plasma' "the pill is a button itself only in the Plasma mode"
    assert_file_contains "$OVERLAY" 'win.controller.requestWidgetGallery()' "the toolbar must not invent gallery coordinates"
    assert_eq "1" "$(grep -c 'EditModeOverlay {}' "$SHELL_ROOT")" "one overlay must serve both modes"
}

test_editing_never_launches_anything() {
    assert_contains "$(function_body "$ICONS" openKeys)" "if (widgetEditMode)" "opening files while editing must be impossible"
}

test_the_grid_and_identity_show_while_editing() {
    assert_file_contains "$ICONS" 'active: root.widgetEditMode' "the cell guides must be built only while editing"
    assert_file_contains "$BIG" 'visible: root.widgetEditMode && !root.isGroup' "the badge must only appear while editing"
    assert_file_contains "$BIG" 'root.hovered || root.selected || root.widgetEditMode || pressed' "the borders must show without hovering"
    assert_file_contains "$BIG" 'DesktopLayout.widgetOutlines || widgetEditMode' "an empty widget must still be locatable"
}

run_tests
