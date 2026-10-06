#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/panels.sh"

PANEL_SCRIPT="$(stock_panel_script)"

test_the_script_only_touches_a_desktop_that_has_no_panel() {
    assert_contains "$PANEL_SCRIPT" 'panels().length === 0' "the script should guard on the panel count"
}

test_the_script_builds_a_bottom_panel_with_the_stock_widgets() {
    assert_contains "$PANEL_SCRIPT" "panel.location = 'bottom'" "the panel should sit at the bottom"
    assert_contains "$PANEL_SCRIPT" "panel.alignment = 'center'" "and be centered"
    assert_contains "$PANEL_SCRIPT" "panel.hiding = 'dodgewindows'" "and hide when a window needs the room"
    assert_contains "$PANEL_SCRIPT" "new Panel" "the script should create a panel"

    local widget
    for widget in org.kde.plasma.kickoff org.kde.plasma.icontasks org.kde.plasma.systemtray org.kde.plasma.digitalclock; do
        assert_contains "$PANEL_SCRIPT" "panel.addWidget('$widget')" "the panel should carry $widget"
    done
}

test_the_script_is_plain_javascript_the_bus_can_take() {
    assert_not_contains "$PANEL_SCRIPT" '\"' "the script should use single quotes, not escaped ones"
    assert_not_contains "$PANEL_SCRIPT" '$' "no shell expansion should survive into the script"
}

test_the_script_carries_no_shell_syntax() {
    assert_not_contains "$PANEL_SCRIPT" ';;' "no C-style case terminator should be in a JS program"
    assert_not_contains "$PANEL_SCRIPT" '$((' "no arithmetic expansion should be in a JS program"
}

run_tests
