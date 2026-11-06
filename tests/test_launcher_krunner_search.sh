#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_HPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/krunnerbridge.hpp"
BRIDGE_CPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/krunnerbridge.cpp"
SERVICES_CMAKE="$REPO_ROOT/shell/plugin/src/Caelestia/Services/CMakeLists.txt"
SEARCH="$REPO_ROOT/shell/services/Search.qml"
APP_LIST="$REPO_ROOT/shell/modules/launcher/AppList.qml"
CONTENT="$REPO_ROOT/shell/modules/launcher/Content.qml"
KRUNNER_ITEM="$REPO_ROOT/shell/modules/launcher/items/KRunnerItem.qml"
LAUNCHER_CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/launcherconfig.hpp"

test_bridge_is_optional_at_build_time() {
    local cmake
    cmake="$(cat "$SERVICES_CMAKE")"

    assert_contains "$cmake" 'find_package(KF6Runner QUIET)' \
        "KF6Runner must be optional so a build without it still works"
    assert_contains "$cmake" 'target_compile_definitions(caelestia-services PRIVATE CAELESTIA_HAVE_KRUNNER)' \
        "the bridge must be compiled in only when KF6Runner is found"
    assert_contains "$cmake" 'krunnerbridge.cpp' \
        "the bridge source must always be part of the module"
    # Optionality that says nothing is how Fedora and Debian shipped without search.
    assert_contains "$cmake" 'message(STATUS "KF6Runner not found' \
        "a build without KF6Runner has to say so instead of silently losing the mode"
}

test_bridge_identifies_results_by_match_id() {
    local hpp cpp
    hpp="$(cat "$BRIDGE_HPP")"
    cpp="$(cat "$BRIDGE_CPP")"

    assert_contains "$hpp" 'QML_ELEMENT' "the bridge must be exposed to QML"
    assert_contains "$hpp" 'Q_PROPERTY(bool available READ available CONSTANT)' \
        "QML needs to know whether KRunner is usable"
    # Runners keep answering while the list is on screen, so a row cannot be
    # identified by its position.
    assert_contains "$hpp" 'Q_INVOKABLE void run(const QString& id, const QString& actionId)' \
        "activation must address a match by id, not by index"
    assert_contains "$cpp" 'QStringLiteral("id"), match.id()' "results must carry their match id"
    assert_contains "$cpp" 'if (match.id() != id)' "activation must resolve the match by id"
    assert_contains "$cpp" 'return false;' \
        "without KF6Runner the bridge must report itself unavailable"
}

test_busy_state_is_not_advertised() {
    # There is no consumer for it, and the previous implementation passed its own
    # cached value back into setBusy, so it could never turn true.
    assert_not_contains "$(cat "$BRIDGE_HPP")" 'busy' "the bridge must not advertise a busy state"
    assert_not_contains "$(cat "$SEARCH")" 'busy' "the service must not re-export a busy state"
}

test_launcher_has_a_live_search_mode() {
    local list search
    list="$(cat "$APP_LIST")"
    search="$(cat "$SEARCH")"

    assert_contains "$list" '"clipboard", "windows", "search"' \
        "the launcher must recognise the search mode"
    assert_contains "$list" 'return Search.results;' \
        "the search mode must render KRunner results"
    assert_contains "$list" 'id: krunnerItem' "the search mode needs its own delegate"
    assert_contains "$list" 'onSearchQueryChanged: Search.search(root.searchQuery)' \
        "typing must drive the asynchronous query"

    assert_contains "$search" 'readonly property var results: KRunnerBridge.results' \
        "the service must expose the results"
    assert_contains "$search" 'KRunnerBridge.run(id, actionId ?? "")' \
        "the service must forward activation by id"
}

test_every_launcher_row_activates_the_same_way() {
    # Enter used to re-derive dispatch by parsing the mode prefix, so every new mode
    # had to be threaded into that chain. Rows now own their activation.
    local content
    content="$(cat "$CONTENT")"
    assert_contains "$content" 'currentItem.activate()' "Enter must delegate activation to the row"
    assert_not_contains "$content" 'currentItem.clicked()' "Enter must not call a row-specific method"
    assert_not_contains "$content" 'currentItem.modelData.onClicked' "Enter must not reach into row data"

    local item
    for item in AppItem ActionItem CalcItem SchemeItem VariantItem EmojiItem ClipItem WindowSwitcherItem KRunnerItem KeybindItem; do
        assert_contains "$(cat "$REPO_ROOT/shell/modules/launcher/items/$item.qml")" 'function activate()' \
            "$item must expose activate()"
    done
    assert_contains "$(cat "$REPO_ROOT/shell/modules/launcher/AnimationsList.qml")" 'function activate()' \
        "the animations list owns its rows too, so it must match"
}

test_search_results_activate_by_id() {
    local item
    item="$(cat "$KRUNNER_ITEM")"
    assert_contains "$item" 'function activate(): void' "a result must expose activate() for the launcher"
    assert_contains "$item" 'Search.run(root.modelData.id, "")' "activation must address the match by id"
}

test_search_mode_is_discoverable_from_the_action_list() {
    local config
    config="$(cat "$LAUNCHER_CONFIG")"

    assert_contains "$config" 'u"Search Everything"_s' "the action list must advertise the mode"
    assert_contains "$config" 'QStringList{ u"autocomplete"_s, u"search"_s }' \
        "the action must autocomplete the search prefix"
}

test_krunner_icons_never_reach_the_provider_unresolved() {
    local item
    item="$(cat "$KRUNNER_ITEM")"

    # KRunner sends an empty icon for executables with no themed icon (most scripts
    # and local binaries) and can send a bare filesystem path. Both used to reach the
    # icon provider unresolved, which draws its placeholder.
    assert_not_contains "$item" 'Quickshell.iconPath(root.modelData?.icon ?? "")' \
        "the provider must never be called without a fallback"
    assert_contains "$item" 'Quickshell.iconPath(root.fallbackIcon, "image-missing")' \
        "an empty icon must resolve to a fallback"
    assert_contains "$item" 'return `file://${raw}`;' "a bare path must become a file URL"
    assert_contains "$item" 'Quickshell.iconPath(raw, root.fallbackIcon)' \
        "an unknown icon name must degrade to the fallback"
    assert_contains "$item" 'if (id.startsWith("exec://"))' \
        "executables need an executable glyph rather than a missing-image one"
}

run_tests
