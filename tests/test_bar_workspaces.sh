#!/usr/bin/env bash
# test_bar_workspaces.sh - What the bar draws for a workspace: a square when occupied,
# a circle when empty, something larger for the focused one.
#
# This port deliberately omits upstream's organic shapes (Cookie4Sided..Cookie12Sided,
# Clover4Leaf, Clover8Leaf, SoftBurst, Ghostish) from the random pool - upstream's reads
# as a Pac-Man sitting in the bar. The rest of the bar syncs from upstream, so this file
# is the record of that divergence: both the pool and the two places drawing from it are
# asserted, because two copies of the list is how a divergence survives in only one.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_QML="$REPO_ROOT/shell/modules/bar/components/workspaces/Workspace.qml"

test_the_bite_shaped_material_shapes_are_not_drawn() {
    local qml
    qml="$(cat "$WORKSPACE_QML")"

    local shape
    for shape in Cookie4Sided Cookie6Sided Cookie7Sided Cookie9Sided Cookie12Sided Clover4Leaf Clover8Leaf SoftBurst Ghostish; do
        assert_not_contains "$qml" "MaterialShape.$shape" "a $shape indicator reads as a Pac-Man rather than a workspace"
    done
}

test_the_focused_shape_comes_from_one_pool() {
    local qml
    qml="$(cat "$WORKSPACE_QML")"

    assert_eq "1" "$(printf '%s\n' "$qml" | grep -c 'readonly property list<int> focusShapes: \[')" "the pool of shapes should be defined once"
    assert_eq "2" "$(printf '%s\n' "$qml" | grep -c 'randShape = focusShapes\[Math.floor(Math.random() \* focusShapes.length)\]')" "and drawn from by both the activation and the swipe path"
    assert_contains "$qml" 'wsShape.shape = root.isOccupied ? MaterialShape.Square : MaterialShape.Circle' "while an unfocused workspace keeps the square it occupies and the circle it does not"
}

run_tests
