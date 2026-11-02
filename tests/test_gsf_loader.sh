#!/usr/bin/env bash

# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOADER="$REPO_ROOT/shell/modules/GSFLoader.qml"
LOADER_SRC="$(cat "$LOADER")"

# The shell bundles one build of Google Sans Flex. Loading it next to a system install
# of the same family is what issue #1180 reported: the two builds carry different glyph
# orders, Qt matches the family to either file, and a layout cached against one renders
# with the other, so a fresh shell start draws unrelated glyphs until a relayout.

test_the_bundled_family_is_checked_against_the_system() {
    assert_contains "$LOADER_SRC" 'Qt.fontFamilies().includes("Google Sans Flex")' \
        "the loader must ask the font database whether the system already has the family"
}

test_the_bundled_font_is_skipped_when_the_system_has_it() {
    assert_contains "$LOADER_SRC" 'source: systemProvidesFamily ? "" : Quickshell.shellPath(' \
        "the bundled file must only be registered when the family is otherwise missing"
}

test_the_bundled_font_is_still_the_fallback() {
    assert_contains "$LOADER_SRC" 'GoogleSansFlex-VariableFont_GRAD,ROND,opsz,slnt,wdth,wght.ttf' \
        "the bundle stays the source when no system copy exists"
}

run_tests
