#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOADER="$REPO_ROOT/shell/services/PluginLoader.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/PluginsPage.qml"
POPUP="$REPO_ROOT/shell/modules/nexus/pages/PluginSettingsPopup.qml"
README="$REPO_ROOT/shell/modules/plugins/README.md"

# Prints the lookup out of the loader so the test drives the real implementation
# rather than a copy of it. QML closes its functions with an indented brace, so
# the helper for shell functions does not apply here.
extract_settings_schema_for() {
    python3 - "$LOADER" <<'PYEOF'
import re
import sys

text = open(sys.argv[1]).read()
match = re.search(r"\n    function settingsSchemaFor\(idOrName\) \{\n(.*?)\n    \}\n", text, re.S)
if not match:
    sys.exit(1)
sys.stdout.write("function settingsSchemaFor(idOrName) {\n" + match.group(1) + "\n}\n")
PYEOF
}

test_the_loader_keeps_a_count_the_plugin_list_can_carry() {
    local loader
    loader="$(cat "$LOADER")"

    assert_eq "$(grep -cF 'meta.settingsCount = meta.settings.length;' "$LOADER")" "3" \
        "every place that reads a manifest should record how many settings it declares"
    assert_contains "$loader" 'function settingsSchemaFor(idOrName)' \
        "and the schema, which the model drops, should stay reachable through a lookup"
    assert_file_contains "$LOADER" 'if ((meta.id || meta.name) === idOrName)' \
        "the lookup should match the same id the settings popup is opened with"
}

test_the_plugin_list_shows_the_settings_button_without_the_schema() {
    local page
    page="$(cat "$PAGE")"

    assert_contains "$page" 'visible: bundledDelegate.settingsCount > 0' \
        "a bundled plugin should offer its settings when the manifest declares any"
    assert_contains "$page" 'visible: userDelegate.settingsCount > 0' \
        "and so should one the user installed"
    assert_not_contains "$page" '.settings.count' \
        "a nested array never survives the ListModel, so the button must not be gated on one"
    assert_not_contains "$page" 'settingsPopup.settingsSchema =' \
        "the popup should look the schema up rather than be handed it through the model"
    assert_eq "$(grep -cF 'required property int settingsCount' "$PAGE")" "2" \
        "both rows should carry the count as a plain number"
}

test_the_popup_reads_the_schema_from_the_loader() {
    assert_file_contains "$POPUP" 'property var settingsSchema: PluginLoader.settingsSchemaFor(root.pluginId)' \
        "the popup should resolve the schema of the plugin it was opened for"
}

test_the_schema_lookup_finds_a_plugin_by_id_or_name() {
    local body result
    body="$(extract_settings_schema_for)" || {
        fail "the schema lookup could not be read out of the loader"
        return 0
    }

    result="$({
        printf '%s\n' "$body"
        cat <<'JSEOF'
const discovered = [
    { id: "alpha", name: "Alpha", settings: [{ id: "a" }, { id: "b" }] },
    { name: "Beta", settings: [{ id: "c" }] },
    { id: "gamma", name: "Gamma" },
];

console.log([
    settingsSchemaFor("alpha").length,
    settingsSchemaFor("Beta").length,
    settingsSchemaFor("Gamma").length,
    settingsSchemaFor("missing").length,
].join(" "));
JSEOF
    } | node -)"

    assert_eq "$result" "2 1 0 0" \
        "a plugin should be found by id or by name, and a manifest without settings should come back empty"
}

test_the_popup_renders_every_type_a_manifest_can_declare() {
    local popup
    popup="$(cat "$POPUP")"

    assert_contains "$popup" 'visible: delegateRow.modelData.type === "enum"' \
        "the choices should still be offered"
    assert_contains "$popup" 'visible: delegateRow.modelData.type === "toggle"' \
        "a switch should be drawn for a toggle"
    assert_contains "$popup" 'visible: delegateRow.modelData.type === "text"' \
        "a field for a text setting"
    assert_contains "$popup" 'visible: delegateRow.modelData.type === "number"' \
        "and a spinner for a number"
    assert_contains "$popup" 'pSettings.setValue(delegateRow.modelData.id' \
        "every row should store its value under the setting's own id"
}

test_the_settings_schema_is_documented() {
    assert_file_contains "$README" '`toggle`, `text`, `number` or `enum`' \
        "the types a row can be should be documented"
    assert_file_contains "$README" '`Plugin_<plugin id>`' \
        "along with the category a plugin reads its values back from"
}

test_the_popup_opens_in_the_window_of_the_page() {
    assert_file_contains "$POPUP" 'function openIn(win)' \
        "the popup should take the window it is opened from as its parent"
    assert_file_not_contains "$POPUP" 'parent: Overlay.overlay' \
        "the controls overlay is not part of the window tree of the nexus, so the popup cannot be parented to it"
    assert_file_contains "$PAGE" 'settingsPopup.openIn(QsWindow.window)' \
        "the settings button should open the popup in the window the page lives in"
    assert_file_contains "$PAGE" 'parent: settingsPopupHost.windowContentItem' \
        "and the popup should be declared inside the page content, where that window is reachable"
    assert_file_contains "$PAGE" 'readonly property var windowContentItem' \
        "the window of the page is what the popup ends up attached to"
}

run_tests
