#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICES="$REPO_ROOT/shell/services"
REGISTRY="$SERVICES/TrayRegistry.qml"
MIGRATIONS="$SERVICES/ConfigMigrations.qml"
ICONS="$REPO_ROOT/shell/utils/Icons.qml"
BAR="$REPO_ROOT/shell/modules/bar/Bar.qml"
CONTENT="$REPO_ROOT/shell/modules/bar/popouts/Content.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarTray.qml"
LIST_EDITOR="$REPO_ROOT/shell/modules/nexus/common/ListEditor.qml"
PAGE_BASE="$REPO_ROOT/shell/modules/nexus/common/PageBase.qml"
SELECT_ROW="$REPO_ROOT/shell/modules/nexus/common/SelectRow.qml"

# The tray rules that do not need Qt live in a .pragma library file
# (shell/services/trayicons.js), which each script below runs against with node's assert.
check_tray_icons() { check_js "$1" "$SERVICES/trayicons.js" Icons "$2"; }

test_pid_comes_out_of_the_notifier_id() {
    check_tray_icons "notifier ids start with the pid" '
assert.strictEqual(Icons.pidOf("2652-9"), "2652");
assert.strictEqual(Icons.pidOf("firefox"), "");
assert.strictEqual(Icons.pidOf(""), "");
'
}

test_aliases_name_the_app_rather_than_the_notifier() {
    check_tray_icons "aliases must survive a new notifier id" '
assert.strictEqual(Icons.keyOf("2407-1", "", "firefox"), "proc:firefox", "a known process names the app");
assert.strictEqual(Icons.keyOf("2407-1", "image://icon/firefox", ""), "icon:firefox", "no process name falls back to the theme icon");
assert.strictEqual(Icons.keyOf("2407-1", "image://qspixmap/abc", ""), "2407-1", "a pixmap names nothing, so the id stays");
assert.strictEqual(Icons.keyOf("2407-1", "", ""), "2407-1", "an icon with no name keeps its id");
assert.strictEqual(Icons.keyOf("2407-1", "image://icon/a/absolute/path", "kitty"), "proc:kitty", "a process name wins over a path-like icon");
'
}

test_labels_are_readable() {
    check_tray_icons "row labels come from the alias" '
assert.strictEqual(Icons.labelOf("proc:kitty-terminal"), "kitty terminal");
assert.strictEqual(Icons.labelOf("icon:org_kde_plasma"), "org kde plasma");
assert.strictEqual(Icons.labelOf("2407-1"), "2407-1", "a raw id is not prettified");
assert.strictEqual(Icons.iconNameOf("proc:kitty-terminal"), "kitty-terminal");
'
}

test_hidden_wins_over_pinned() {
    check_tray_icons "state precedence is hidden > visible > collapsed" '
assert.strictEqual(Icons.stateOf("a", ["a"], ["a"]), "hidden");
assert.strictEqual(Icons.stateOf("a", [], ["a"]), "visible");
assert.strictEqual(Icons.stateOf("a", ["b"], ["c"]), "collapsed");
'
}

test_listed_keys_come_first_in_listed_order() {
    check_tray_icons "the saved order leads and the rest keeps registration order" '
const rows = [{ key: "a" }, { key: "b" }, { key: "c" }];
assert.deepStrictEqual(Icons.ordered(rows, ["c", "a"]).map(row => row.key), ["c", "a", "b"]);
assert.deepStrictEqual(Icons.ordered(rows, []).map(row => row.key), ["a", "b", "c"], "an empty order keeps registration order");
assert.deepStrictEqual(Icons.ordered(rows, ["gone", "b"]).map(row => row.key), ["b", "a", "c"], "keys the order does not know are skipped");
assert.deepStrictEqual(Icons.ordered([], ["a"]), [], "no rows need no order");
'
}

test_the_bar_and_the_popout_read_one_list() {
    assert_file_contains "$REGISTRY" "readonly property var trayItems" "the registry publishes the bar's icons"
    assert_file_contains "$CONTENT" "TrayRegistry.trayItems" "the tray popout reads the bar's icons"
    assert_file_not_contains "$CONTENT" "SystemTray.items.values.filter" "the popout must not re-derive which icons exist"
    assert_file_not_contains "$BAR" "tray.layout.childAt" "the bar must not reach into the tray's layout"
    assert_file_contains "$BAR" "tray.itemAt(pos)" "the tray owns its own hit test"
}

test_popout_names_have_one_definition() {
    assert_file_contains "$REGISTRY" "function popoutName(key: string): string" "the popout name prefix lives in the registry"
    assert_file_not_contains "$BAR" "traymenu" "the bar must not rebuild the popout name"
    assert_file_contains "$BAR" "trayItem.popoutName" "the bar asks the icon for its popout name"
    assert_file_contains "$CONTENT" "TrayRegistry.popoutNameOf" "the popout names itself through the registry"
}

test_the_reorder_list_is_the_shared_one() {
    assert_file_missing "$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/TrayOrderList.qml" "the tray must reuse the shared reorder list"
    assert_file_contains "$PAGE" "ListEditor {" "the tray page reorders with the shared list editor"
    assert_file_contains "$LIST_EDITOR" "property Component trailingComponent" "the shared list editor carries the extra control"
    assert_file_not_contains "$PAGE_BASE" "scrollLocked" "pages must not grow drag-specific scroll modes"
    assert_file_not_contains "$SELECT_ROW" "highlight" "the shared select row must not grow drag-specific modes"
}

test_a_single_identity_reads_icon_substitutions() {
    assert_file_contains "$ICONS" "function getTrayIcon(key: string, icon: string): string" "icon substitutions are keyed by the alias alone"
    assert_file_contains "$MIGRATIONS" "function migrateTrayIcons(aliases: var): void" "the config rewrite maps ids to aliases"
    assert_file_contains "$MIGRATIONS" "sub.id = aliases[sub.id]" "icon substitutions are rewritten with the lists"
    assert_file_contains "$REGISTRY" "ConfigMigrations.migrateTrayIcons(aliases)" "the registry hands its aliases over"
}

test_config_is_the_only_store() {
    assert_file_not_contains "$REGISTRY" "FileView" "tray settings live in config, not in a second file"
    assert_file_not_contains "$REGISTRY" "unseenTtl" "there is nothing to expire"
    assert_file_contains "$REGISTRY" "GlobalConfig.bar.tray.order" "the bar order is the saved order"
}

run_tests
