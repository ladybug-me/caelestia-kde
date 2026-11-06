#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$REPO_ROOT/shell/modules/background"
ENGINE="$DESKTOP/desktopicons/LayoutEngine.js"
BIG="$DESKTOP/desktopicons/BigItem.qml"
BIG_SRC="$(cat "$BIG")"
ICONS_SRC="$(cat "$DESKTOP/DesktopIcons.qml")"
GALLERY_SRC="$(cat "$DESKTOP/desktopicons/WidgetGallery.qml")"

# LayoutEngine.js is a .pragma library with no Qt dependencies, so node can run it
# directly: each script below runs against it with node's assert.
check_engine_js() { check_js "$1" "$ENGINE" Engine "$2"; }

have_node() {
    command -v node >/dev/null 2>&1
}

count_in() {
    local count
    count="$(grep -cF -- "$2" "$1" || true)"
    printf '%s' "${count:-0}"
}

test_dragging_the_left_edge_keeps_the_right_one_in_place() {
    have_node || { skip_test "node is not installed"; return 0; }
    # A 2x2 widget at column 4 grows one cell to the left without moving the
    # right edge, which stays at column 6.
    check_engine_js "a left edge resize must move the item and keep its right edge" '
const positions = { "w/a": { col: 4, row: 1 } };
const next = Engine.planMove(positions, ["w/a"], "w/a", { col: 3, row: 1 }, 10, 6, { "w/a": { w: 3, h: 2 } });
assert.strictEqual(next["w/a"].col, 3);
assert.strictEqual(next["w/a"].row, 1);
assert.strictEqual(next["w/a"].col + 3, 6);'
}

test_dragging_the_top_edge_keeps_the_bottom_one_in_place() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "a top edge resize must move the item and keep its bottom edge" '
const positions = { "w/a": { col: 4, row: 2 } };
const next = Engine.planMove(positions, ["w/a"], "w/a", { col: 4, row: 0 }, 10, 6, { "w/a": { w: 2, h: 4 } });
assert.strictEqual(next["w/a"].row, 0);
assert.strictEqual(next["w/a"].row + 4, 4);
assert.strictEqual(next["w/a"].col, 4);'
}

test_items_under_a_growing_edge_step_aside() {
    have_node || { skip_test "node is not installed"; return 0; }
    # Growing two cells to the left covers an icon that was sitting there, so it
    # has to land somewhere else.
    check_engine_js "a left edge resize must not leave an item under the widget" '
const positions = { "w/a": { col: 4, row: 0 }, "f/note": { col: 3, row: 0 } };
const next = Engine.planMove(positions, ["w/a"], "w/a", { col: 2, row: 0 }, 10, 6, { "w/a": { w: 4, h: 2 } });
assert.strictEqual(next["w/a"].col, 2);
const note = next["f/note"];
assert.ok(!(note.col >= 2 && note.col < 6 && note.row < 2), "the icon must not stay under the widget");
assert.ok(Engine.inGrid(note, 10, 6, { w: 1, h: 1 }));'
}

test_every_border_of_a_card_resizes() {
    assert_eq "8" "$(count_in "$BIG" 'Grip {')" "the four edges and the four corners must all be draggable"
    assert_contains "$BIG_SRC" 'horizontal: -1' "the left border must resize"
    assert_contains "$BIG_SRC" 'horizontal: 1' "the right border must resize"
    assert_contains "$BIG_SRC" 'vertical: -1' "the top border must resize"
    assert_contains "$BIG_SRC" 'vertical: 1' "the bottom border must resize"
    assert_contains "$BIG_SRC" 'anchors.left: card.left' "the left border must follow the card"
    assert_contains "$BIG_SRC" 'anchors.right: card.right' "the right border must follow the card"
    assert_contains "$BIG_SRC" 'anchors.top: card.top' "the top border must follow the card"
    assert_contains "$BIG_SRC" 'anchors.bottom: card.bottom' "the bottom border must follow the card"
}

test_the_border_cursor_matches_the_edge() {
    assert_contains "$BIG_SRC" 'return Qt.SizeVerCursor;' "a horizontal border must offer a vertical cursor"
    assert_contains "$BIG_SRC" 'return Qt.SizeHorCursor;' "a vertical border must offer a horizontal cursor"
    assert_contains "$BIG_SRC" 'Qt.SizeFDiagCursor : Qt.SizeBDiagCursor' "corners must offer the diagonal cursors"
}

test_the_drag_hands_its_origin_cell_to_the_controller() {
    assert_contains "$BIG_SRC" 'root.controller.previewResize(root.key, s.w, s.h, {' "the preview must carry the cell the opposite edge is held to"
    assert_contains "$BIG_SRC" 'root.controller.resizeItem(root.key, s.w, s.h, {' "the commit must carry the same cell"
    assert_contains "$ICONS_SRC" 'function previewResize(key: string, w: int, h: int, origin: var): void' "the preview must take an origin"
    assert_contains "$ICONS_SRC" 'function resizeItem(key: string, w: int, h: int, origin: var): void' "the commit must take an origin"
    assert_contains "$ICONS_SRC" 'origin ?? current[key]' "a resize without an origin must keep the item in its cell"
    assert_contains "$ICONS_SRC" 'previewOrigin = null;' "ending a preview must forget the origin"
}

test_the_gallery_hint_mentions_the_borders() {
    assert_contains "$GALLERY_SRC" "border or corner" "the gallery hint must not promise corners only"
}

run_tests