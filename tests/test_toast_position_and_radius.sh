#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOASTS="$REPO_ROOT/shell/modules/utilities/toasts/Toasts.qml"
CORNER="$REPO_ROOT/shell/modules/utilities/toasts/corner.js"
PANELS="$REPO_ROOT/shell/modules/drawers/Panels.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/services/ToastPreferencesPage.qml"
SCHEMA="$REPO_ROOT/shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp"
WINDOW="$REPO_ROOT/shell/modules/drawers/ContentWindow.qml"

# The corner vocabulary is pure, so it is executed rather than grepped: each script
# below runs against corner.js with node's assert.
check_corner() { check_js "$1" "$CORNER" Corner "$2"; }

test_the_corner_is_a_setting_with_a_corner_for_every_taste() {
    assert_file_contains "$SCHEMA" "CONFIG_GLOBAL_PROPERTY(QString, position, u\"auto\"_s)" \
        "the corner is config, so it survives a restart"
    assert_file_contains "$PAGE" "readonly property list<string> cornerValues: Corner.VALUES" \
        "the row offers the same five names the layout resolves"
    assert_file_contains "$PAGE" 'GlobalConfig.utilities.toasts.position = root.cornerValues' \
        "and the row writes it"
    assert_file_contains "$CORNER" 'var VALUES = ["auto", "top-left", "top-right", "bottom-left", "bottom-right"];' \
        "which are written down once"
}

# `auto` must keep the spot the shell has always used, and a value nobody recognises has
# to land where the row that shows it says it will.
test_automatic_keeps_the_corner_the_shell_always_used() {
    check_corner "automatic has to follow the bar, the way the shell always has" '
assert.strictEqual(Corner.resolve("auto", "bottom"), "bottom-left", "a bottom bar leaves the toasts on the left");
assert.strictEqual(Corner.resolve("auto", "right"), "bottom-left", "a right bar puts the sidebar on the left, so the toasts stay left of it");
assert.strictEqual(Corner.resolve("auto", "top"), "bottom-right", "a top bar leaves them on the right");
assert.strictEqual(Corner.resolve("auto", "left"), "bottom-right", "and so does a left one");
assert.strictEqual(Corner.resolve("top-right", "bottom"), "top-right", "a chosen corner is left alone");
'
}

test_a_corner_nobody_recognises_is_automatic_everywhere() {
    check_corner "an unknown value must not place the stack somewhere no row can show" '
assert.strictEqual(Corner.resolve("sideways", "bottom"), "bottom-left", "the layout falls back to automatic");
assert.strictEqual(Corner.index("sideways"), 0, "and the row shows automatic, which is the same answer");
assert.strictEqual(Corner.index("auto"), 0, "automatic is the first row");
assert.strictEqual(Corner.index("bottom-right"), 4, "and the last corner is the last row");
'
}

# The stack has always grown upwards from the bottom; a top corner has to grow the other
# way, which is why both margins and both edges exist.
test_the_stack_grows_from_the_corner_it_was_given() {
    assert_file_contains "$TOASTS" 'required property bool fromTop' "the stack is told which way to grow"
    assert_file_contains "$TOASTS" 'required property bool fromLeft' "and which side to hang from"
    assert_file_not_contains "$TOASTS" 'position' "it does not parse a corner name of its own"
    assert_file_contains "$TOASTS" 'anchors.top: root.fromTop ? parent.top : undefined' "a top corner hangs from the top"
    assert_file_contains "$TOASTS" 'anchors.bottom: root.fromTop ? undefined : parent.bottom' "and a bottom corner from the bottom"
    assert_file_contains "$TOASTS" 'anchors.topMargin: root.fromTop ? root.offsetFor(index) : 0' "each toast clears the ones in front of it"
    assert_file_contains "$TOASTS" 'anchors.bottomMargin: root.fromTop ? 0 : root.offsetFor(index)' "in the direction the stack grows"
    assert_file_contains "$TOASTS" 'anchors.left: parent.left' "each toast spans the stack's width, so a right-hand corner cannot push it off the screen"
    assert_file_contains "$TOASTS" 'anchors.right: parent.right' "on both sides, not one"
    assert_file_contains "$TOASTS" 'Behavior on anchors.topMargin' "and the movement is animated either way"
}

# A chosen corner is the only owner of the stack's edges, so the bar-position states
# cannot quietly move it back, and a panel that is open is the only thing that pushes it.
test_a_chosen_corner_owns_the_edge_and_no_state_moves_it() {
    assert_file_contains "$PANELS" 'readonly property string corner: Corner.resolve(GlobalConfig.utilities.toasts.position, bar.position)' \
        "the corner is resolved once, from the setting"
    assert_file_contains "$PANELS" 'fromTop: Corner.isTop(toasts.corner)' "and handed to the stack as two sides"
    assert_file_contains "$PANELS" 'fromLeft: Corner.isLeft(toasts.corner)'
    assert_file_contains "$PANELS" 'anchors.right: Corner.isLeft(toasts.corner) ? undefined : parent.right' \
        "a right-hand corner reaches the edge of the screen"
    assert_file_contains "$PANELS" 'readonly property real sidebarInset: sidebar.visible && Corner.isLeft(toasts.corner) !== toasts.sidebarOnRight ? sidebar.width : 0' \
        "the only thing that moves it is a sidebar open on that side"
    assert_file_contains "$PANELS" 'readonly property real drawerInset: utilities.visible && utilities.vAnchor === "bottom" ? utilities.implicitHeight : 0' \
        "and the utilities drawer when it is open along the bottom"
    assert_file_not_contains "$PANELS" 'target: toasts' \
        "the bar-position states leave the stack where the corner put it"
    assert_file_not_contains "$PANELS" 'property string vAnchor: toasts' \
        "and the stack carries no side anchors nobody reads"
}

# The drawer's frame and the surface drawn inside it are one number, not two: a frame
# rounding that disagrees with the panel leaves a sliver of wallpaper at every corner.
test_the_drawer_frame_and_its_surface_share_one_radius() {
    assert_file_contains "$WINDOW" 'readonly property real borderRounding: Config.border.rounding' \
        "the radius has a single owner"
    assert_eq "1" "$(find "$WINDOW" -type f -exec grep -c 'readonly property real borderRounding' {} \;)" \
        "and it is defined once"
    assert_eq "yes" "$([[ "$(find "$WINDOW" -type f -exec grep -c 'radius: root.borderRounding' {} \;)" -ge 2 ]] && echo yes || echo no)" \
        "the frame and the surface both read it, so they cannot disagree"
    # What is left on a token is the bar island: a surface of its own, with no frame
    # around it to line up with.
    assert_file_contains "$WINDOW" 'radius: Tokens.rounding.extraLarge' \
        "the island keeps the corner of an island"
}

run_tests
