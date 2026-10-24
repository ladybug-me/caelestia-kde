#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$REPO_ROOT/shell/modules/bar/BarWidgets.qml"
BAR="$REPO_ROOT/shell/modules/bar/Bar.qml"
CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/barconfig.hpp"
EDITOR="$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarComponents.qml"

registry_entries() {
    sed -nE 's/^ *\{ id: "([A-Za-z0-9_]+)", zone: "([a-z]+)" \},?$/\1 \2/p' "$REGISTRY"
}

registry_ids() {
    registry_entries | awk '{ print $1 }' | sort
}

schema_entries() {
    sed -nE 's/.*u"id"_s, u"([A-Za-z0-9_]+)"_s.*u"zone"_s, u"([a-z]+)"_s.*/\1 \2/p' "$CONFIG"
}

bar_choice_ids() {
    sed -nE 's/^ *roleValue: "([A-Za-z0-9_]+)"$/\1/p' "$BAR" | sort
}

editor_ids() {
    sed -nE 's/^ *"([A-Za-z0-9_]+)": \{.*$/\1/p' "$EDITOR" | sort
}

assert_same_lines() {
    local what="$1" expected="$2" actual="$3"
    local only_expected only_actual
    only_expected="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | paste -sd' ' -)"
    only_actual="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | paste -sd' ' -)"

    if [[ -n "$only_expected" || -n "$only_actual" ]]; then
        fail "$what (missing: ${only_expected:-nothing}; unexpected: ${only_actual:-nothing})"
    fi
}

assert_matched_something() {
    local what="$1" found="$2"
    assert_ne "" "$found" "$what (the pattern matched nothing, so nothing was checked)"
}

test_the_registry_and_the_bar_draw_the_same_widgets() {
    local registry drawn
    registry="$(registry_ids)"
    drawn="$(bar_choice_ids)"

    assert_matched_something "no widgets are declared in BarWidgets.qml" "$registry"
    assert_matched_something "no widgets are drawn by Bar.qml" "$drawn"
    assert_same_lines "the bar's DelegateChooser and the registry disagree" "$registry" "$drawn"
}

test_the_registry_and_the_schema_defaults_agree() {
    local registry schema
    registry="$(registry_entries | sort)"
    schema="$(schema_entries | sort)"

    assert_matched_something "no widgets are declared in BarWidgets.qml" "$registry"
    assert_matched_something "no default entries are declared in barconfig.hpp" "$schema"
    assert_same_lines "bar.entries defaults and the registry disagree, id or zone" "$registry" "$schema"
}

test_the_editor_labels_every_registered_widget() {
    local registry editor
    registry="$(registry_ids)"
    editor="$(editor_ids)"

    assert_matched_something "the taskbar editor labels no widgets" "$editor"
    assert_same_lines "the taskbar editor's label table and the registry disagree" "$registry" "$editor"
}

test_resetting_the_layout_asks_the_schema_for_its_defaults() {
    assert_file_contains "$EDITOR" 'BarWidgets.resetToDefaults(root.targetNode)' \
        "the reset button has to go back to the schema's own defaults"
    assert_file_not_contains "$EDITOR" '{ id: "dock", enabled: true, zone: "middle" }' \
        "and must not grow another copy of the default layout - that copy is how resetting lost media"
    assert_file_contains "$EDITOR" 'BarWidgets.zoneFor(root.targetNode, id)' \
        "a widget dragged out of the bar keeps the zone it had, or it comes back on the left"
}

test_nothing_else_writes_the_entry_list_by_hand() {
    local file
    for file in \
        "$BAR" \
        "$EDITOR" \
        "$REPO_ROOT/shell/modules/bar/popouts/Updates.qml" \
        "$REPO_ROOT/shell/modules/nexus/pages/UpdatesPage.qml" \
        "$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarDock.qml" \
        "$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml" \
        "$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarUpdates.qml"; do
        assert_file_not_contains "$file" 'bar.entries =' \
            "toggling a widget is BarWidgets' job, not a settings page's ($(basename "$file"))"
    done
}

test_the_toggle_helper_keeps_the_widget_list_well_formed() {
    if ! command -v node >/dev/null 2>&1; then
        skip_test "node is not available"
        return 0
    fi

    local harness
    harness="$(mktemp "${TMPDIR:-/tmp}/caelestia-barwidgets.XXXXXX.mjs")"
    cat > "$harness" <<'EOF'
import { readFileSync } from "node:fs";

const src = readFileSync(process.argv[2], "utf8");

function sliceBalanced(from, open, close) {
    let depth = 0;
    for (let i = from; i < src.length; i++) {
        if (src[i] === open) depth++;
        else if (src[i] === close && --depth === 0) return src.slice(from, i + 1);
    }
    throw new Error("unbalanced " + open);
}

function stripTypes(header) {
    return header
        .replace(/\)\s*:\s*[A-Za-z_][\w<>.\[\]|]*\s*$/, ") ")
        .replace(/([(,\s])([A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w<>.\[\]|]*/g, "$1$2");
}

function extractFunction(name) {
    const marker = "function " + name + "(";
    const start = src.indexOf(marker);
    if (start === -1) throw new Error(name + " not found");
    const text = sliceBalanced(start, "{", "}");
    const brace = text.indexOf("{");
    return stripTypes(text.slice(0, brace)) + text.slice(brace);
}

function extractArray(name) {
    const marker = name + ": [";
    const start = src.indexOf(marker);
    if (start === -1) throw new Error(name + " not found");
    return sliceBalanced(src.indexOf("[", start), "[", "]");
}

const widgets = new Function("return " + extractArray("widgets") + ";")();
const root = { widgets };
root.byId = (() => {
    const byId = {};
    root.widgets.forEach((widget, index) => byId[widget.id] = Object.assign({ index: index }, widget));
    return byId;
})();
root.ids = root.widgets.map(widget => widget.id);

const names = ["widget", "isKnown", "entriesOf", "zoneEntries", "isEnabled", "zoneFor", "setEnabled", "replaceAll", "indexFor"];
Object.assign(root, new Function("root", names.map(extractFunction).join("\n") + "\nreturn {" + names.join(", ") + "};")(root));

const eq = (actual, expected, msg) => {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        console.error("FAIL:", msg);
        console.error("  actual:  ", JSON.stringify(actual));
        console.error("  expected:", JSON.stringify(expected));
        process.exit(1);
    }
};

const defaults = [
    { id: "logo", enabled: true, zone: "left" },
    { id: "workspaces", enabled: true, zone: "left" },
    { id: "greeter", enabled: true, zone: "left" },
    { id: "dock", enabled: true, zone: "middle" },
    { id: "tray", enabled: true, zone: "right" },
    { id: "updateIndicator", enabled: true, zone: "right" },
    { id: "github", enabled: false, zone: "right" },
    { id: "media", enabled: false, zone: "right" },
    { id: "clock", enabled: true, zone: "right" },
    { id: "power", enabled: true, zone: "right" }
];
const ids = entries => entries.map(entry => entry.id);

eq(ids(root.zoneEntries(defaults, "left")), ["logo", "workspaces", "greeter"], "left zone");
eq(ids(root.zoneEntries(defaults, "middle")), ["dock"], "middle zone");
eq(ids(root.zoneEntries(defaults, "right")), ["tray", "updateIndicator", "clock", "power"], "the right zone drops the disabled widgets");
eq(ids(root.zoneEntries([{ id: "clock", enabled: true }], "left")), ["clock"], "an entry with no zone is a left one, which is what the bar always assumed");

eq(ids(root.zoneEntries([
    { id: "spacer", enabled: true, zone: "left" },
    { id: "nonsense", enabled: true, zone: "left" },
    { id: "clock", enabled: true, zone: "left" }
], "left")), ["clock"], "spacer and unknown ids never reach the bar");
eq(root.isKnown("media"), true, "media is a widget");
eq(root.isKnown("spacer"), false, "spacer is not");

eq(root.isEnabled({ entries: defaults }, "dock"), true, "dock is on");
eq(root.isEnabled({ entries: defaults }, "github"), false, "github is off");
eq(root.isEnabled({ entries: defaults }, "perfCpu"), false, "a widget with no entry is off");
eq(root.isEnabled({}, "dock"), false, "an empty list reads as off");

eq(root.zoneFor({ entries: defaults }, "dock"), "middle", "an entry's own zone wins");
eq(root.zoneFor({}, "dock"), "middle", "and a widget with no entry keeps the zone it was declared with");
eq(root.zoneFor({}, "nonsense"), "left", "an id the registry does not know still lands somewhere");

const toggled = { entries: defaults.map(entry => Object.assign({}, entry)) };
const handedOver = toggled.entries;
root.setEnabled(toggled, "github", true);
eq(ids(toggled.entries), ["logo", "workspaces", "greeter", "dock", "tray", "updateIndicator", "github", "media", "clock", "power"],
    "an existing widget keeps its place");
eq(root.isEnabled(toggled, "github"), true, "and turns on");
eq(handedOver[6].enabled, false, "without writing through the entry objects the old list handed over");

const restored = { entries: defaults.filter(entry => entry.id !== "updateIndicator") };
root.setEnabled(restored, "updateIndicator", true);
eq(ids(restored.entries).indexOf("updateIndicator"), ids(restored.entries).indexOf("tray") + 1,
    "a widget missing from the list goes back beside the neighbours it was declared with");
eq(restored.entries.find(entry => entry.id === "updateIndicator").zone, "right", "with its declared zone");

const empty = {};
root.setEnabled(empty, "dock", true);
eq(empty.entries, [{ id: "dock", enabled: true, zone: "middle" }], "and into an empty list the registry supplies the zone");

const source = [{ id: "clock", enabled: true, zone: "right" }];
const editor = {};
root.replaceAll(editor, source);
source.push({ id: "dock", enabled: true, zone: "middle" });
eq(ids(editor.entries), ["clock"], "the editor's list is snapshotted, not aliased");

console.log("bar widget registry: all harness cases passed");
EOF

    if ! timeout 15 node "$harness" "$REGISTRY"; then
        rm -f "$harness"
        fail "the bar widget registry harness failed"
        return 0
    fi
    rm -f "$harness"
}

run_tests
