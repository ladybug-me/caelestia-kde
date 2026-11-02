#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIS="$REPO_ROOT/shell/services/Visibilities.qml"
GRID="$REPO_ROOT/shell/modules/overview/WindowGrid.qml"
DOCK="$REPO_ROOT/shell/modules/bar/popouts/DockContext.qml"
DOCK_MODEL="$REPO_ROOT/shell/modules/bar/components/Dock.qml"
KWIN="$REPO_ROOT/shell/services/Kwin.qml"

test_overview_can_be_limited_to_one_application() {
    local vis
    vis="$(cat "$VIS")"

    assert_contains "$vis" 'property var overviewAppFilter: []' \
        "Visibilities should hold the overview's application filter"
    assert_contains "$vis" 'function showAppWindows(names: var): void' \
        "Visibilities should be able to open the overview for one application"
    assert_contains "$vis" 'overviewAppFilter = [];' \
        "closing the overview must clear the filter, or the next open is still filtered"
}

test_one_query_feeds_both_the_grid_and_the_selection() {
    local grid
    grid="$(cat "$GRID")"

    assert_contains "$grid" 'function gridWindows(wsId: int): var' \
        "one function describes what a page lays out"
    assert_contains "$grid" 'Kwin.windowMatchesApp(w, filter)' \
        "the grid must filter through the shared matcher"
    assert_contains "$grid" 'const filter = Visibilities.overviewAppFilter' \
        "the filter must be read inside the binding, or the grid never re-evaluates"
    assert_contains "$grid" 'return root.gridWindows(Kwin.workspaces[listView.currentIndex].index)' \
        "the selection must read the same query as the page, not its own copy"
    assert_contains "$grid" 'const arr = root.gridWindows(wsId)' \
        "the rendered cards must come from that query too"
    assert_contains "$grid" 'on_AppFilterChanged: _updateWsWindows()' \
        "the rendered window cards must re-run when the filter changes"
}

test_the_matcher_lives_on_the_window_service() {
    local kwin
    kwin="$(cat "$KWIN")"

    assert_contains "$kwin" 'function classNamesApp(cls: string, names: var): bool' \
        "one rule says what counts as the same application"
    assert_contains "$kwin" 'function windowMatchesApp(w: var, names: var): bool' \
        "and it is reachable from a window, which is what callers have"
    assert_contains "$kwin" 'replace(/\.desktop$/, "")' \
        "matching must normalise desktop entry ids against window classes"
    assert_contains "$kwin" 'startsWith("steam_app_")' \
        "steam's per-game classes must only ever match themselves"
}

test_the_dock_groups_through_the_same_rule() {
    local dock
    dock="$(cat "$DOCK_MODEL")"

    assert_contains "$dock" 'Kwin.classNamesApp(appClass, [app.id, app.appClass])' \
        "the dock must not keep a second opinion about what counts as the same app"
    assert_not_contains "$dock" 'includes(appClass.toLowerCase())' \
        "the hand-rolled class matching must be gone"
}

test_the_dock_offers_show_all_windows() {
    local dock
    dock="$(cat "$DOCK")"

    assert_contains "$dock" 'Visibilities.showAppWindows(root.appNames)' \
        "the dock context menu should open the overview for that application"
    assert_contains "$dock" 'Kwin.windowMatchesApp(w, root.appNames)' \
        "the entry should only appear when the application has windows"
    assert_contains "$dock" 'Kwin.activeWsId' \
        "the overview opens on the active workspace, so windows elsewhere do not count"
    assert_contains "$dock" 'qsTr("Show all windows")' \
        "the action needs a label"
}

run_tests