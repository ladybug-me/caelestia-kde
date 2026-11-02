#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXUS="$REPO_ROOT/shell/modules/nexus"
SHELL="$REPO_ROOT/shell"

test_back_shortcut_is_a_configurable_keybind() {
    assert_file_contains "$SHELL/plugin/src/Caelestia/Config/keybindsdefaults.hpp" \
        'QStringLiteral("nexusBack"), QStringLiteral("Alt+Left")' \
        "the back binding should have a default in the keybind model"
    assert_file_contains "$SHELL/modules/Shortcuts.qml" 'name: "nexusBack"' \
        "the back binding should be registered as a shell shortcut"
    assert_file_contains "$SHELL/modules/Shortcuts.qml" 'enabled: WindowFactory.openWindowActive' \
        "the binding should only be grabbed while the settings window is focused"
    assert_file_contains "$SHELL/modules/Shortcuts.qml" 'WindowFactory.goBack()' \
        "the binding should ask the settings window to go back"
}

test_the_shortcut_only_closes_a_sub_page() {
    assert_file_contains "$NEXUS/Nexus.qml" 'Window.window.active' \
        "the settings window should report whether it is focused"
    assert_file_contains "$NEXUS/WindowFactory.qml" 'function goBack(): void' \
        "the settings window should expose a back action"
    assert_file_contains "$NEXUS/WindowFactory.qml" 'subPageIdxStack.length > 0' \
        "the back action should do nothing at the page root"
    assert_file_contains "$NEXUS/WindowFactory.qml" 'state.closeSubPage()' \
        "the back action should pop one sub-page"
}

test_mouse_back_button_triggers_go_back() {
    assert_file_contains "$NEXUS/Nexus.qml" 'acceptedButtons: Qt.BackButton' \
        "the nexus window should listen for the mouse back button"
    assert_file_contains "$NEXUS/Nexus.qml" 'WindowFactory.goBack()' \
        "the mouse back button should invoke WindowFactory.goBack"
}

test_the_shortcuts_page_lists_the_back_binding() {
    assert_file_contains "$NEXUS/pages/ShortcutManagerPage.qml" 'nexus.*' \
        "the shortcuts page should classify nexusBack as a shell shortcut"
}

test_clicking_a_location_returns_to_its_root_page() {
    assert_file_contains "$NEXUS/navpane/NavLocations.qml" 'root.nState.goToPage(item.pageIdx)' \
        "a location click should go through goToPage, so the current page can reset too"
    assert_file_contains "$NEXUS/NexusState.qml" 'subPagesCleared()' \
        "resetting the current page should tell the stack view"
    assert_file_contains "$NEXUS/common/StackPage.qml" 'root.popToIndex(0, StackView.Immediate)' \
        "the stack view should drop every sub-page in one operation"
}

test_go_to_page_still_switches_pages() {
    assert_file_contains "$NEXUS/NexusState.qml" 'currentPageIdx = pageIdx' \
        "selecting another page should still change currentPageIdx"
}

test_a_search_result_for_the_main_page_returns_to_its_root() {
    assert_file_contains "$NEXUS/NexusState.qml" 'goToPage(pageIdx)' \
        "goToSubPage should route main-page hits through goToPage"
}

test_a_shortcut_without_a_key_keeps_its_default() {
    assert_file_contains "$SHELL/components/misc/CustomShortcut.qml" 'property var key' \
        "an unset key should stay undefined instead of defaulting to an empty string"
    assert_file_contains "$SHELL/components/misc/CustomShortcut.qml" 'when: root.key !== undefined' \
        "the key should only be assigned when a caller supplies one"
}

run_tests
