#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$REPO_ROOT/shell/modules/Shortcuts.qml"
DEFAULTS="$REPO_ROOT/shell/plugin/src/Caelestia/Config/keybindsdefaults.hpp"

# Repeater cannot be used here: Scope is not an Item, so the delegate objects
# (Loaders registering Caelestia.GlobalShortcut) must be parented by an
# Instantiator to stay alive. The two ids whose casing looks like a typo stay
# exactly as the krohnkite kwinscript registers them — krohnkite 0.9.9.2's
# contents/ui/shortcuts.qml registers "KrohnkitegrowWidth" and "KrohnkitetoggleDock"
# verbatim, so re-casing them to the repo catalogue's style would silently no-op.

model_entries() {
    grep '^[[:space:]]*{ name: "krohnkite' "$QML"
}

model_ids() {
    model_entries | grep -oP 'action: "\K[^"]+'
}

model_names() {
    model_entries | grep -oP 'name: "\Kkrohnkite[A-Za-z]+'
}

test_the_table_drives_one_instantiator_delegate() {
    local qml
    qml="$(cat "$QML")"

    assert_contains "$qml" 'readonly property var krohnkiteShortcuts: [' "the shortcut table should exist"
    assert_contains "$qml" 'Instantiator {' "the table should be instantiated"
    assert_contains "$qml" 'model: root.krohnkiteShortcuts' "the instantiator should read the table"
    assert_contains "$qml" 'required property var modelData' "the delegate should take its entry as modelData"

    assert_eq "1" "$(printf '%s\n' "$qml" | grep -c 'delegate: CustomShortcut {')" \
        "exactly one CustomShortcut delegate should exist for the whole table"
    assert_eq "1" "$(printf '%s\n' "$qml" | grep -c 'invokeShortcut')" \
        "the qdbus invokeShortcut call should be built in exactly one place"
    assert_eq "36" "$(printf '%s\n' "$qml" | grep -c 'name: "krohnkite')" \
        "krohnkite shortcut names should exist only as the 36 table entries"

    assert_eq "36" "$(model_entries | wc -l)" "the table should hold all 36 krohnkite shortcuts"
}

test_no_krohnkite_action_id_appears_twice() {
    local dup
    dup="$(model_ids | sort | uniq -d)"
    assert_eq "" "$dup" "every action id should appear exactly once in the table"

    local id total outside_comments
    while IFS= read -r id; do
        total="$(grep -oF "$id" "$QML" | wc -l)"
        outside_comments="$(grep -v '^[[:space:]]*//' "$QML" | grep -oP "\b${id}\b" | wc -l)"
        assert_eq "1" "$outside_comments" "$id should appear once outside comments (found $total with comments)"
    done < <(model_ids)
}

test_the_suspicious_ids_are_intentionally_preserved() {
    local qml
    qml="$(cat "$QML")"

    # Not our typos: these are the ids the krohnkite kwinscript itself registers.
    assert_eq "1" "$(printf '%s\n' "$qml" | grep -cF 'action: "KrohnkitegrowWidth"')" \
        "the growWidth id must keep the kwinscript's lowercase casing"
    assert_eq "1" "$(printf '%s\n' "$qml" | grep -cF 'action: "KrohnkitetoggleDock"')" \
        "the toggleDock id must keep the kwinscript's lowercase casing"
    assert_not_contains "$qml" 'action: "KrohnkiteGrowWidth"' "the catalogue-cased growWidth variant must not be invented"
    assert_not_contains "$qml" 'action: "KrohnkiteToggleDock"' "the catalogue-cased toggleDock variant must not be invented"
    assert_contains "$qml" "contents/ui/shortcuts.qml" "the file should document where the ids were verified"
}

test_the_table_matches_the_plugin_default_keybinds() {
    # One name differs upstream: the shell
    # names the shortcut krohnkiteTreeColumnLayout while the catalogue has
    # krohnkiteThreeColumnLayout (both default to "", and the KWin-side id is
    # KrohnkiteThreeColumnLayout either way) — normalise it so the comparison
    # covers names, coverage and default keys without blessing a rename.
    local catalogue model
    catalogue="$(paste -d'|' \
        <(grep -oP 'QStringLiteral\("\Kkrohnkite[A-Za-z]+(?="\), QStringLiteral)' "$DEFAULTS") \
        <(grep -oP 'QStringLiteral\("krohnkite[A-Za-z]+"\), QStringLiteral\("\K[^"]*(?="\))' "$DEFAULTS") \
        | sed 's/^krohnkiteThreeColumnLayout|/krohnkiteTreeColumnLayout|/' | sort)"
    model="$(paste -d'|' \
        <(model_names) \
        <(model_entries | grep -oP 'key: "\K[^"]*(?=" \})') | sort)"

    assert_eq "$catalogue" "$model" "model name|default-key pairs should mirror keybindsdefaults.hpp"
}

test_the_fullscreen_ipc_guards_read_a_live_source() {
    local qml
    qml="$(cat "$QML")"

    assert_contains "$qml" 'readonly property bool hasFullscreen: Kwin.hasFullscreen()' \
        "hasFullscreen should read the Kwin service like NotifData does"
    assert_not_contains "$qml" 'hasFullscreen: false' "hasFullscreen must not be hardcoded off"
}

run_tests
