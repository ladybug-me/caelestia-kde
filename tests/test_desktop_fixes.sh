#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$REPO_ROOT/shell/modules/background/desktopicons"
CLOCK_SRC="$(cat "$DESKTOP/widgets/ClockWidget.qml")"
MEDIA_SRC="$(cat "$DESKTOP/widgets/MediaWidget.qml")"

# LayoutEngine.js is a .pragma library with no Qt dependencies, so node can
# load it directly. Prints "ok" when every assertion held.
run_engine_js() {
    ENGINE="$DESKTOP/LayoutEngine.js" node -e '
const fs = require("fs");
const assert = require("assert");
const src = fs.readFileSync(process.env.ENGINE, "utf8").replace(/^\.pragma library$/m, "");
const names = [...src.matchAll(/^function (\w+)/gm)].map(m => m[1]);
const Engine = new Function(src + "\nreturn {" + names.join(",") + "};")();
'"$1"'
console.log("ok");' 2>&1
}

check_engine_js() {
    local message="$1" script="$2" out
    out="$(run_engine_js "$script")"
    [[ "$out" == "ok" ]] || fail_with_output "$message" "$out"
}

have_node() {
    command -v node >/dev/null 2>&1
}

test_a_smaller_grid_keeps_every_item_when_it_has_room_for_all_of_them() {
    have_node || { skip_test "node is not installed"; return 0; }
    # Eight icons and a 2x2 widget scattered over a 6x5 grid, which then
    # shrinks to 4x3: exactly 12 cells for 12 cells of items. Keeping each item
    # where it was and filling the gaps leaves one icon without a cell, packing
    # them all again does not.
    check_engine_js "fitIntoGrid must pack again when that leaves fewer items outside" '
const spans = { w1: { w: 2, h: 2 } };
const positions = {
    w1: { col: 3, row: 2 }, i0: { col: 5, row: 2 }, i1: { col: 0, row: 4 },
    i2: { col: 1, row: 0 }, i3: { col: 2, row: 1 }, i4: { col: 4, row: 4 },
    i5: { col: 0, row: 3 }, i6: { col: 4, row: 0 }, i7: { col: 1, row: 1 },
};
const out = Engine.fitIntoGrid(positions, 4, 3, spans);
assert.strictEqual(Object.keys(out).length, 9);
for (const key in out) {
    const s = spans[key] || { w: 1, h: 1 };
    assert.ok(Engine.inGrid(out[key], 4, 3, s), key + " is outside the grid");
}
const seen = {};
for (const key in out) {
    const s = spans[key] || { w: 1, h: 1 };
    for (let c = 0; c < s.w; c++)
        for (let r = 0; r < s.h; r++) {
            const id = (out[key].col + c) + "," + (out[key].row + r);
            assert.ok(!seen[id], key + " overlaps " + seen[id]);
            seen[id] = key;
        }
}'
}

test_items_that_already_fit_stay_where_they_are() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "fitIntoGrid must not move items that are inside the grid" '
const positions = { a: { col: 0, row: 0 }, b: { col: 2, row: 1 }, c: { col: 3, row: 2 } };
const out = Engine.fitIntoGrid(positions, 4, 3, {});
assert.deepStrictEqual(out, positions);'
}

test_items_that_cannot_all_fit_are_reduced_to_the_fewest_outside() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "fitIntoGrid must never leave more items outside than keeping them in place" '
const positions = {};
for (let i = 0; i < 8; i++)
    positions["i" + i] = { col: i % 4, row: Math.floor(i / 4) * 2 };
const out = Engine.fitIntoGrid(positions, 3, 2, {});
let outside = 0;
for (const key in out)
    if (!Engine.inGrid(out[key], 3, 2, { w: 1, h: 1 }))
        outside++;
assert.strictEqual(outside, 2);'
}

test_clock_content_stays_inside_narrow_sizes() {
    assert_contains "$CLOCK_SRC" 'fontSizeMode: root.wide ? Text.HorizontalFit : Text.Fit' "the time must shrink to fit when stacked above the weather"
    assert_contains "$CLOCK_SRC" 'elide: Text.ElideRight' "the temperature must elide instead of overflowing"
    assert_not_contains "$CLOCK_SRC" 'Layout.maximumWidth: root.width / (root.wide ? 2.4 : 1.2)' "the weather text must follow the layout width"
}

test_media_art_is_kept_while_it_reloads_on_resize() {
    assert_contains "$MEDIA_SRC" 'retainWhileLoading: true' "the cover must stay visible while a new size loads"
}

run_tests
