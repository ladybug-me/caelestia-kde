#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXUS="$REPO_ROOT/shell/modules/nexus"
CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/nexusconfig.hpp"
NEXUS_SETTINGS="$NEXUS/pages/wallandstyle/NexusSettingsPage.qml"

test_the_layout_is_a_global_setting_that_defaults_to_two_panels() {
    assert_file_contains "$CONFIG" 'CONFIG_GLOBAL_PROPERTY(bool, sidePane, false)' \
        "the setting should be global and default to the two-panel layout"
}

test_the_toggle_lives_in_the_settings_window_itself() {
    assert_file_contains "$NEXUS_SETTINGS" 'setting: "sidePane"' \
        "the toggle should reset through the setting it edits"
    assert_file_contains "$NEXUS_SETTINGS" 'GlobalConfig.nexus.sidePane = checked' \
        "the toggle should write the setting"
}

test_the_window_reads_the_setting_and_hides_the_pane() {
    assert_file_contains "$NEXUS/Nexus.qml" 'readonly property bool sidePane: GlobalConfig.nexus.sidePane' \
        "the window should follow the setting"
    assert_file_contains "$NEXUS/Nexus.qml" 'visible: root.sidePane' \
        "the subcategory pane should be hidden when the setting is off"
}

test_the_compact_fold_only_applies_to_the_three_pane_layout() {
    assert_file_contains "$NEXUS/Nexus.qml" 'readonly property bool compact: root.width < 1120 && root.sidePane' \
        "there is nothing to fold once the middle pane is gone"
}

test_a_section_opens_on_its_own_list_without_the_pane() {
    assert_file_contains "$NEXUS/NexusState.qml" 'property bool sidePane: false' \
        "the navigation state should know which layout it is driving"
    assert_file_contains "$NEXUS/NexusState.qml" 'if (!sidePane)' \
        "the default slot should depend on the layout"
    assert_file_contains "$NEXUS/NexusState.qml" 'return sidePane ? parentSubCategory(pageIdx, target) : "hub"' \
        "without the pane the section list is the root of the stack"
}

test_keyboard_navigation_skips_the_pane_that_is_not_there() {
    assert_file_contains "$NEXUS/Nexus.qml" 'function enterSubcategories(): void' \
        "stepping into the content should be one decision, not a pane index sprinkled around"
    assert_file_contains "$NEXUS/Nexus.qml" 'function leaveContent(): void' \
        "stepping back out should land on the section list when the pane is gone"
}

run_tests
