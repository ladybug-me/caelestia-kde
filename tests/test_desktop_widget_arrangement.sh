#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$REPO_ROOT/shell/modules/background"
ICONS="$DESKTOP/DesktopIcons.qml"
ENGINE="$DESKTOP/desktopicons/LayoutEngine.js"
ICONS_SRC="$(cat "$ICONS")"
ENGINE_SRC="$(cat "$ENGINE")"

check_engine_js() { check_js "$1" "$ENGINE" Engine "$2"; }

have_node() {
    command -v node >/dev/null 2>&1
}

function_body() {
    awk -v name="$2" '
        index($0, "function " name "(") { capture = 1 }
        capture { print }
        capture && /^    \}$/ { exit }
    ' "$1"
}

# --- LayoutEngine.js Tests (Node.js runtime) ---------------------------------

test_plan_move_never_displaces_immovable_keys() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "planMove must not displace immovable keys when target collides" '
const positions = {
    "w/locked": { col: 2, row: 1 },
    "f/item": { col: 0, row: 0 }
};
const spans = { "w/locked": { w: 2, h: 2 }, "f/item": { w: 1, h: 1 } };
const next = Engine.planMove(positions, ["f/item"], "f/item", { col: 2, row: 1 }, 10, 6, spans, ["w/locked"]);
assert.strictEqual(next["w/locked"].col, 2, "locked widget col must not change");
assert.strictEqual(next["w/locked"].row, 1, "locked widget row must not change");'
}

test_plan_move_immovable_blocks_displaced_items_from_landing_on_it() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "planMove displaced items must not be placed onto immovable items" '
const positions = {
    "w/locked": { col: 1, row: 0 },
    "f/other": { col: 3, row: 0 },
    "f/mover": { col: 0, row: 0 }
};
const spans = { "w/locked": { w: 2, h: 2 }, "f/other": { w: 1, h: 1 }, "f/mover": { w: 1, h: 1 } };
const next = Engine.planMove(positions, ["f/mover"], "f/mover", { col: 3, row: 0 }, 10, 6, spans, ["w/locked"]);
assert.strictEqual(next["w/locked"].col, 1);
assert.strictEqual(next["w/locked"].row, 0);
assert.strictEqual(next["f/mover"].col, 3);
assert.strictEqual(next["f/mover"].row, 0);
const other = next["f/other"];
assert.ok(!(other.col >= 1 && other.col <= 2 && other.row >= 0 && other.row <= 1), "displaced item must not overlap locked widget");
assert.ok(Engine.inGrid(other, 10, 6, { w: 1, h: 1 }), "displaced item must stay in grid");'
}

test_compact_packs_icons_around_obstacles() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "compact must respect obstacles and pack around them" '
const obstacles = {
    "w/clock": { col: 1, row: 0 },
    "w/media": { col: 3, row: 2 }
};
const spans = {
    "w/clock": { w: 2, h: 2 },
    "w/media": { w: 2, h: 2 },
    "i/1": { w: 1, h: 1 }, "i/2": { w: 1, h: 1 }, "i/3": { w: 1, h: 1 },
    "i/4": { w: 1, h: 1 }, "i/5": { w: 1, h: 1 }
};
const keys = ["i/1", "i/2", "i/3", "i/4", "i/5"];
const packed = Engine.compact(keys, 4, spans, obstacles);
assert.strictEqual(Object.keys(packed).length, 5, "compact only returns the packed keys");
for (const k of keys) {
    const p = packed[k];
    assert.ok(!(p.col >= 1 && p.col <= 2 && p.row >= 0 && p.row <= 1), k + " overlaps clock obstacle");
    assert.ok(!(p.col >= 3 && p.col <= 4 && p.row >= 2 && p.row <= 3), k + " overlaps media obstacle");
}'
}

test_plan_insert_with_obstacles_excludes_obstacles_and_preserves_positions() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "planInsert must exclude obstacles from re-packing order" '
const positions = {
    "w/clock": { col: 1, row: 0 },
    "i/1": { col: 0, row: 0 },
    "i/2": { col: 0, row: 1 }
};
const obstacles = { "w/clock": { col: 1, row: 0 } };
const spans = { "w/clock": { w: 2, h: 2 }, "i/1": { w: 1, h: 1 }, "i/2": { w: 1, h: 1 } };
const next = Engine.planInsert(positions, ["i/2"], { col: 1, row: 0 }, 4, spans, obstacles);
assert.ok(!("w/clock" in next), "obstacles must not be returned in planInsert compact result");
assert.ok("i/1" in next && "i/2" in next, "moving and rest items are packed");
for (const k of ["i/1", "i/2"]) {
    const p = next[k];
    assert.ok(!(p.col >= 1 && p.col <= 2 && p.row >= 0 && p.row <= 1), k + " overlaps clock obstacle");
}'
}

test_mark_rect_tolerates_null_or_falsy_pos() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "markRect must not throw when pos is null or undefined" '
const occ = {};
Engine.markRect(occ, null, { w: 1, h: 1 }, "null_pos");
Engine.markRect(occ, undefined, { w: 1, h: 1 }, "undef_pos");
assert.strictEqual(Object.keys(occ).length, 0, "markRect must do nothing on falsy pos");'
}

test_snap_out_of_avoids_occupied_cells_and_handles_spans() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_engine_js "snapOutOf must snap to nearest free cell outside occupied footprints" '
function snapOutOf(place, movingSpan, occupiedKeys, positionMap, spans, cols, rows) {
    if (!occupiedKeys || occupiedKeys.length === 0)
        return place;
    const occ = {};
    for (const key of occupiedKeys) {
        const p = positionMap[key];
        if (p)
            Engine.markRect(occ, p, spans[key] || { w: 1, h: 1 }, key);
    }
    const s = movingSpan || { w: 1, h: 1 };
    if (Engine.rectFree(occ, place, s))
        return place;
    return Engine.nearestFree(occ, place.col, place.row, cols, rows, s);
}

const pos = { "w/locked": { col: 2, row: 2 } };
const spans = { "w/locked": { w: 2, h: 2 } };
const snapped = snapOutOf({ col: 2, row: 2 }, { w: 1, h: 1 }, ["w/locked"], pos, spans, 10, 6);
assert.ok(!(snapped.col >= 2 && snapped.col <= 3 && snapped.row >= 2 && snapped.row <= 3), "snapped cell must be outside locked widget");
assert.ok(Engine.inGrid(snapped, 10, 6, { w: 1, h: 1 }), "snapped cell must be inside grid");

const free = snapOutOf({ col: 0, row: 0 }, { w: 1, h: 1 }, ["w/locked"], pos, spans, 10, 6);
assert.deepStrictEqual(free, { col: 0, row: 0 }, "unoccupied target must remain unchanged");

const empty = snapOutOf({ col: 2, row: 2 }, { w: 1, h: 1 }, [], pos, spans, 10, 6);
assert.deepStrictEqual(empty, { col: 2, row: 2 }, "empty occupiedKeys must return place unchanged");'
}

# --- Static Invariant & Integration Tests (DesktopIcons.qml & LayoutEngine.js)

test_layout_engine_safely_iterates_own_properties() {
    assert_not_contains "$ENGINE_SRC" 'for (const key in positions)' "for..in on positions risks prototype pollution"
    assert_contains "$ENGINE_SRC" 'for (const key of Object.keys(positions))' "safe Object.keys iteration on positions must be used"
}

test_locked_keys_helper_only_gathers_locked_widgets() {
    assert_contains "$ICONS_SRC" 'function lockedKeys(): var' "lockedKeys helper must be defined"
    local locked_body
    locked_body="$(function_body "$ICONS" lockedKeys)"
    assert_contains "$locked_body" 'isKeyLocked(key)' "lockedKeys must filter with isKeyLocked"
    local is_locked_body
    is_locked_body="$(function_body "$ICONS" isKeyLocked)"
    assert_contains "$is_locked_body" 'isWidgetKey(key) && DesktopLayout.isWidgetLocked(nameOf(key))' \
        "isKeyLocked must only consider widgets and check DesktopLayout"
}

test_snap_out_of_and_snap_out_of_locked_helpers_present() {
    assert_contains "$ICONS_SRC" 'function snapOutOf(place: var, movingSpan: var, occupiedKeys: var, positionMap: var): var' \
        "snapOutOf helper must be defined with required parameters"
    assert_contains "$ICONS_SRC" 'function snapOutOfLocked(place: var, movingSpan: var): var' \
        "snapOutOfLocked convenience helper must be defined"
    local snap_locked_body
    snap_locked_body="$(function_body "$ICONS" snapOutOfLocked)"
    assert_contains "$snap_locked_body" 'snapOutOf(place, movingSpan, lockedKeys(), contextPositionsTopLevel())' \
        "snapOutOfLocked must wire lockedKeys and contextPositionsTopLevel"
}

test_update_drop_preview_handles_safe_place_and_immovable() {
    local preview_body
    preview_body="$(function_body "$ICONS" updateDropPreview)"
    assert_contains "$preview_body" 'const widgetMove = moving.some(k => isWidgetKey(k));' \
        "preview must detect widget moves"
    assert_contains "$preview_body" 'if (widgetMove && DesktopLayout.autoArrange)' \
        "preview must branch on widget drag under autoArrange"
    assert_contains "$preview_body" 'avoidKeys = locked.filter(k => !moving.includes(k)).concat(iconKeys);' \
        "preview must avoid locked widgets and icons, excluding moving widgets"
    assert_contains "$preview_body" 'immovable = locked.concat(iconKeys);' \
        "preview must mark both locked widgets and icons as immovable"
    assert_contains "$preview_body" 'safePlace = snapOutOfLocked(plan.place, spanOf(dragAnchor));' \
        "preview must snap drop target away from locked widgets"
    assert_contains "$preview_body" 'Engine.planInsert(base, moving, safePlace, rows, spans, iconObstacles)' \
        "preview under autoArrange for icons must pass iconObstacles to planInsert"
    assert_contains "$preview_body" 'Engine.planMove(base, moving, anchor, safePlace, cols, rows, spans, immovable)' \
        "preview for manual moves must pass immovable to planMove"
}

test_commit_drop_handles_safe_place_and_immovable() {
    local commit_body
    commit_body="$(function_body "$ICONS" commitDrop)"
    assert_contains "$commit_body" 'const widgetMove = keys.some(k => isWidgetKey(k));' \
        "commit must detect widget moves"
    assert_contains "$commit_body" 'if (widgetMove && DesktopLayout.autoArrange)' \
        "commit must branch on widget drag under autoArrange"
    assert_contains "$commit_body" 'avoidKeys = locked.filter(k => !keys.includes(k)).concat(iconKeys);' \
        "commit must avoid locked widgets and icons, excluding moving widgets"
    assert_contains "$commit_body" 'immovable = locked.concat(iconKeys);' \
        "commit must mark both locked widgets and icons as immovable"
    assert_contains "$commit_body" 'safePlace = snapOutOfLocked(plan.place, spanOf(dragAnchor || keys[0]));' \
        "commit must snap drop target away from locked widgets"
    assert_contains "$commit_body" 'landed = Engine.planInsert(current, keys, safePlace, rows, spans, iconObstacles);' \
        "commit under autoArrange for icons must pass iconObstacles to planInsert"
    assert_contains "$commit_body" 'landed = Engine.planMove(contextPositionsTopLevel(), keys, dragAnchor || keys[0], safePlace, cols, rows, spans, immovable);' \
        "commit for manual moves must pass immovable to planMove"
}

test_arranged_preserves_widget_obstacles_in_return_value() {
    local arranged_body
    arranged_body="$(function_body "$ICONS" arranged)"
    assert_contains "$arranged_body" 'const movable = key => describe(key).kind !== "widget";' \
        "arranged must identify widgets as immovable obstacles"
    assert_contains "$arranged_body" 'if (!movable(key))' \
        "arranged must extract non-movable keys into obstacles"
    assert_contains "$arranged_body" 'obstacles[key] = positions[key];' \
        "arranged must map obstacle keys to positions"
    assert_contains "$arranged_body" 'return Object.assign({}, obstacles, packed);' \
        "arranged must return both obstacles and packed icons to prevent spurious layout updates"
}

test_resize_plan_passes_locked_keys_as_immovable() {
    local resize_body
    resize_body="$(function_body "$ICONS" resizePlan)"
    assert_contains "$resize_body" 'Engine.planMove(current, [key], key, origin ?? current[key], cols, rows, s, lockedKeys());' \
        "resizePlan must pass lockedKeys() as immovable to planMove"
}

test_desktop_grid_is_aligned_to_margin_and_margin_is_halved() {
    assert_contains "$ICONS_SRC" 'readonly property int baseMargin: Math.round(Tokens.padding.large * 0.5 * root.effectiveScale)' \
        "baseMargin must be halved (0.5 * large token)"
    assert_contains "$ICONS_SRC" 'x: marginLeft' \
        "grid must align directly to marginLeft without centering offset"
    assert_contains "$ICONS_SRC" 'y: marginTop' \
        "grid must align directly to marginTop without centering offset"
    assert_not_contains "$ICONS_SRC" 'x: marginLeft + Math.floor((areaWidth - width) / 2)' \
        "grid must no longer center horizontally"
    assert_not_contains "$ICONS_SRC" 'y: marginTop + Math.floor((areaHeight - height) / 2)' \
        "grid must no longer center vertically"
}

run_tests
