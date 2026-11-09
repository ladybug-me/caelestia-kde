#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANE="$REPO_ROOT/shell/modules/nexus/SubcategoryPane.qml"
CHECK="$REPO_ROOT/tools/check_nexus_page_titles.py"

test_every_card_names_the_page_it_opens() {
    if ! command -v python3 >/dev/null 2>&1; then
        skip_test "python3 is not installed"
        return 0
    fi

    local output
    if ! output="$(cd "$REPO_ROOT" && python3 "$CHECK" 2>&1)"; then
        fail "a subcategory card and its page title disagree: $output"
    fi
}

test_the_middle_pane_does_not_repeat_the_page_name() {
    assert_file_contains "$PANE" 'qsTr("Sections")' \
        "the middle pane header should name the column, not repeat the selected category"
    assert_file_contains "$PANE" 'root.nState.compact ?' \
        "compact mode still shows the page name because it has no left navigation"
}

test_a_long_page_can_scroll_clear_of_the_window_edge() {
    local page_base="$REPO_ROOT/shell/modules/nexus/common/PageBase.qml"
    assert_file_contains "$page_base" '+ Tokens.padding.large : height' \
        "the page needs trailing space so its last row is not cut in half"
    assert_file_contains "$page_base" 'y: flickable.visibleArea.yPosition * flickable.height' \
        "and a scrollbar so the page says it can scroll"
}

test_a_reset_is_hidden_until_it_has_something_to_do() {
    local reset="$REPO_ROOT/shell/components/controls/SettingResetButton.qml"
    assert_file_contains "$reset" 'opacity: root.dirty || root.latched ? 1 : 0' \
        "a default row should not show a permanent reset icon"
    assert_file_contains "$reset" 'icon: "restore"' \
        "the reset icon should not look like reload"
    assert_file_contains "$reset" 'Accessible.name: qsTr("Reset to default")' \
        "and it needs a name for a screen reader"
}

test_long_row_descriptions_wrap_instead_of_eliding() {
    local toggle="$REPO_ROOT/shell/modules/nexus/common/ToggleRow.qml"
    local select="$REPO_ROOT/shell/modules/nexus/common/SelectRow.qml"
    local stepper="$REPO_ROOT/shell/modules/nexus/common/StepperRow.qml"
    assert_file_contains "$toggle" 'wrapMode: Text.Wrap' "toggle descriptions wrap"
    assert_file_contains "$select" 'wrapMode: Text.Wrap' "select descriptions wrap"
    assert_file_contains "$stepper" 'wrapMode: Text.Wrap' "stepper descriptions wrap"
}

test_the_notification_page_uses_the_same_words_as_its_card() {
    local prefs="$REPO_ROOT/shell/modules/nexus/pages/services/NotificationPreferencesPage.qml"
    assert_file_contains "$prefs" 'title: qsTr("Notification Behaviour")' \
        "the content header matches the subcategory card"
    assert_file_contains "$prefs" 'text: qsTr("Open notifications expanded")' \
        "the toggle says what it expands"
    assert_file_contains "$prefs" 'text: qsTr("Behaviour")' \
        "the behaviour settings sit under their own section"
}

test_the_session_icon_fields_show_what_they_change() {
    local session="$REPO_ROOT/shell/modules/nexus/pages/SessionPage.qml"
    assert_file_contains "$session" 'property bool iconField' \
        "icon fields are distinguishable from command fields"
    assert_file_contains "$session" 'text: input.text.length > 0 ? input.text : "help"' \
        "the icon name is previewed live"
    assert_file_contains "$session" 'Material icon names used by the session menu' \
        "the field says what kind of name it wants"
}

test_game_mode_uses_the_hyprland_fact_and_explains_kde() {
    local game="$REPO_ROOT/shell/modules/nexus/pages/services/GameModePage.qml"
    assert_file_contains "$game" 'visible: GameMode.onHyprland' \
        "the page uses the service's own compositor fact"
    assert_file_contains "$game" 'KDE desktop effects' \
        "KDE users get an explanation instead of an empty page"
}

test_the_picker_trigger_is_named_and_points_up() {
    local popup="$REPO_ROOT/shell/modules/nexus/common/BlobPopup.qml"
    assert_file_contains "$popup" 'Accessible.name: qsTr("Open picker")' \
        "the picker trigger is not an unnamed glyph"
    assert_file_contains "$popup" 'text: "expand_less"' \
        "the trigger points the way the popup opens"
}

run_tests
