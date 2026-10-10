#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTRL="$REPO_ROOT/shell/components/controls"
LOADING_SRC="$(cat "$CTRL/LoadingIndicator.qml")"
CIRCULAR_SRC="$(cat "$CTRL/CircularProgress.qml")"
BAR_SRC="$(cat "$CTRL/StyledProgressBar.qml")"
COVER_SRC="$(cat "$REPO_ROOT/shell/components/widgets/CoverArt.qml")"

test_loading_indicator_runs_only_while_visible() {
    assert_contains "$LOADING_SRC" 'readonly property bool running: animated && visible' "running must depend on visibility"
    assert_contains "$LOADING_SRC" 'running: root.running && !root.springSettled' "the frame animation must follow running"
    assert_not_contains "$LOADING_SRC" 'running: root.animated' "no animation may follow animated alone"
}

test_looping_animations_pause_while_hidden() {
    assert_contains "$CIRCULAR_SRC" '|| !root.visible' "CircularProgress wave must pause while hidden"
    assert_contains "$BAR_SRC" 'root.wavePaused || !root.visible' "StyledProgressBar wave must pause while hidden"
    assert_contains "$COVER_SRC" '|| !root.visible' "CoverArt rotation must pause while hidden"
}

test_progress_bar_size_transitions_are_skipped_while_hidden() {
    local count
    count=$(grep -c 'enabled: root.visible' "$CTRL/StyledProgressBar.qml")
    assert_eq 2 "$count" "both size behaviours must be disabled while hidden"
}

run_tests
