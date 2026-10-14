#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLOURS="$REPO_ROOT/shell/services/Colours.qml"
PREVIEW_COLOURS="$REPO_ROOT/shell/services/PreviewColours.qml"
WALLPAPERS="$REPO_ROOT/shell/services/Wallpapers.qml"
LAYER="$REPO_ROOT/shell/modules/background/Wallpaper.qml"
LAUNCHER="$REPO_ROOT/shell/modules/launcher/Content.qml"
APPLIST="$REPO_ROOT/shell/modules/launcher/AppList.qml"
M3VARIANTS="$REPO_ROOT/shell/modules/launcher/services/M3Variants.qml"

COLOURS_SRC="$(cat "$COLOURS")"
PC_SRC="$(cat "$PREVIEW_COLOURS")"
WALL_SRC="$(cat "$WALLPAPERS")"
LAYER_SRC="$(cat "$LAYER")"
LAUNCHER_SRC="$(cat "$LAUNCHER")"

# How many times a file writes the preview palette on or off, so that "one owner" is measurable.
writes_to_the_preview_scheme() {
    local on off
    on="$(grep -c 'Colours\.showPreview = true' "$1" || true)"
    off="$(grep -c 'Colours\.showPreview = false' "$1" || true)"
    printf '%s' "$((on + off))"
}

test_the_preview_state_lives_in_one_component() {
    assert_contains "$PC_SRC" 'function show(source: string): void' "show must be part of the interface"
    assert_contains "$PC_SRC" 'function hold(): void' "hold must be part of the interface"
    assert_contains "$PC_SRC" 'function release(): void' "release must be part of the interface"
    assert_contains "$PC_SRC" 'function stop(): void' "stop must be part of the interface"
    assert_not_contains "$WALL_SRC" 'previewColourLock' "a latch on the preview must stay inside the component"
    assert_not_contains "$WALL_SRC" 'pendingPreviewClear' "a deferred clear must stay inside the component"
    assert_not_contains "$WALL_SRC" 'getPreviewColoursProc' "the matugen process must be owned by the component"
}

test_only_colours_shows_the_preview_scheme() {
    assert_eq "1" "$(grep -c 'root.showPreview = true' "$COLOURS" || true)" \
        "exactly one place may turn the preview scheme on"
    assert_contains "$COLOURS_SRC" 'function loadPreview(data: string): void' \
        "a process result must go through it"
    assert_eq "0" "$(writes_to_the_preview_scheme "$PREVIEW_COLOURS")" \
        "the component must not write the preview scheme"
    assert_eq "0" "$(writes_to_the_preview_scheme "$M3VARIANTS")" \
        "the variant picker must not write the preview scheme"
    assert_eq "0" "$(writes_to_the_preview_scheme "$APPLIST")" \
        "the scheme picker must not write the preview scheme"
    assert_eq "0" "$(writes_to_the_preview_scheme "$WALLPAPERS")" \
        "Wallpapers must not write the preview scheme"
}

test_the_picker_carries_no_second_preview_flag() {
    assert_not_contains "$WALL_SRC" 'property bool showPreview' \
        "the picker's preview state must be derived, not a flag beside Colours.showPreview"
    assert_contains "$WALL_SRC" 'readonly property bool previewing' \
        "and it is derived from the path being previewed"
}

test_a_preview_never_puts_its_wallpaper_on_screen() {
    assert_contains "$WALL_SRC" 'readonly property string current: actualCurrent' \
        "the wallpaper on screen is the applied one"
    assert_not_contains "$WALL_SRC" 'previewPath : actualCurrent' \
        "a preview must not swap the wallpaper on screen, which costs a transition per highlight"
    assert_contains "$LAYER_SRC" 'source: Wallpapers.current' \
        "the wallpaper layer shows what Wallpapers calls current"
    assert_not_contains "$LAYER_SRC" 'previewing' \
        "and takes no preview of its own"
}

test_a_result_is_shown_only_when_it_loaded_and_is_still_wanted() {
    assert_contains "$PC_SRC" 'if (!root.active && !root.held)' "a result nobody waits for must be dropped"
    assert_contains "$PC_SRC" 'root.wanted !== root.running' "a result for an earlier highlight must not be shown"
    assert_contains "$PC_SRC" 'Colours.loadPreview(text)' "the result must go through the scheme parse gate"
}

test_the_preview_ends_only_while_nothing_wants_it() {
    assert_contains "$PC_SRC" 'if (!active && !held)' "the preview is cleared only while nothing wants it"
}

test_the_applied_scheme_ends_the_hold() {
    assert_contains "$COLOURS_SRC" 'signal schemeApplied' "Colours must announce the scheme in effect"
    assert_contains "$COLOURS_SRC" 'root.schemeApplied()' "and announce it when one is applied"
    assert_contains "$PC_SRC" 'function onSchemeApplied(): void' "the applied scheme landing is what ends the hold"
    assert_contains "$WALL_SRC" 'previewColoursState.hold()' "setting a wallpaper holds the preview"
    assert_contains "$PC_SRC" 'held = Colours.showPreview' "a hold with no preview palette to cover is not armed"
    assert_not_contains "$WALL_SRC" 'previewColoursState.release()' "the hold must not end on the wallpaper path file, which lands before the scheme does"
    assert_not_contains "$LAUNCHER_SRC" 'previewColours' "the launcher must not drive the preview state"
    assert_not_contains "$LAUNCHER_SRC" 'hold()' "the launcher must not hold the preview state"
}

run_tests
