#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$REPO_ROOT/shell/modules/background"
ICONS_SRC="$(cat "$DESKTOP/DesktopIcons.qml")"
BIG_SRC="$(cat "$DESKTOP/desktopicons/BigItem.qml")"
SYSTEM_SRC="$(cat "$DESKTOP/desktopicons/widgets/SystemWidget.qml")"

test_the_system_widget_only_builds_the_layout_it_shows() {
    assert_contains "$SYSTEM_SRC" 'active: root.tier === 0' "the ring layout must be a Loader tied to its tier"
    assert_contains "$SYSTEM_SRC" 'active: root.tier > 0' "the meter layout must be a Loader tied to its tier"
}

test_the_system_widget_has_no_endless_animation() {
    assert_not_contains "$SYSTEM_SRC" 'property: "slideProgress"' "the network graph must not slide on a loop"
    assert_contains "$SYSTEM_SRC" 'slideProgress: 1' "the network graph is drawn without a slide"
}

test_drag_previews_are_rebuilt_only_when_the_plan_changes() {
    assert_contains "$ICONS_SRC" 'property string previewPlanKey' "the last drop plan is remembered"
    assert_contains "$ICONS_SRC" 'if (planKey === previewPlanKey)' "an unchanged drop plan must not rebuild the preview"
    assert_contains "$ICONS_SRC" 'previewPlanKey = "";' "clearing the preview must forget the plan"
    assert_contains "$ICONS_SRC" 'if (span && span.w === w && span.h === h)' "an unchanged resize span must not rebuild the preview"
}

test_the_frosted_cards_share_one_blurred_wallpaper() {
    assert_contains "$ICONS_SRC" 'id: glassLoader' "the controller blurs the wallpaper once"
    assert_contains "$ICONS_SRC" 'readonly property Item glass: glassLoader.item' "the blurred wallpaper is exposed to the cards"
    assert_contains "$BIG_SRC" 'sourceItem: root.controller.glass' "cards sample the shared blur"
    assert_not_contains "$BIG_SRC" 'blurEnabled: true' "cards must not blur the wallpaper themselves"
}

run_tests
