#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "$0")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
shortcuts_function="$(sed -n '/QString stolenShortcutsPath()/,/^}/p' "$REPO_ROOT/shell/plugin/src/Caelestia/Services/globalshortcut.cpp")"
edges_function="$(sed -n '/QString stolenEdgesPath()/,/^}/p' "$REPO_ROOT/shell/plugin/src/Caelestia/Services/screenedges.cpp")"
keybinds_function="$(sed -n '/QString KeybindsModel::keybindsPath() const/,/^}/p' "$REPO_ROOT/shell/plugin/src/Caelestia/Services/keybindsmodel.cpp")"

test_all_saved_paths_use_qstandardpaths_config_location() {
    local function
    for function in "$shortcuts_function" "$edges_function" "$keybinds_function"; do
        assert_contains "$function" 'QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)' \
            "each persisted Caelestia config path must honor XDG_CONFIG_HOME"
        assert_not_contains "$function" 'QDir::homePath()' \
            "persisted Caelestia config paths must not hard-code the home directory"
    done
}

test_each_path_keeps_its_existing_relative_location() {
    assert_contains "$shortcuts_function" '"/caelestia/stolen-shortcuts.json"' "shortcut backup filename must stay unchanged"
    assert_contains "$edges_function" '"/caelestia/stolen-screen-edges.json"' "edge backup filename must stay unchanged"
    assert_contains "$keybinds_function" '"/caelestia/keybinds.json"' "keybind filename must stay unchanged"
}

run_tests
