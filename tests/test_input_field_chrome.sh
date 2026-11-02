#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIELD="$REPO_ROOT/shell/components/controls/StyledTextField.qml"
LAYER="$REPO_ROOT/shell/components/StateLayer.qml"

test_there_is_one_input_field_component() {
    assert_file_missing "$REPO_ROOT/shell/components/controls/StyledInputField.qml" \
        "a wrapper that re-declared the field's own API is what drew two boxes"

    local leftover
    leftover="$(grep -rl 'StyledInputField' "$REPO_ROOT/shell" || true)"
    assert_eq "" "$leftover" "and no call site may still ask for it"
}

test_the_boxed_style_draws_the_box_itself() {
    assert_file_contains "$FIELD" 'Boxed' \
        "the compact field is a style of the field, not a second component around it"
    assert_file_contains "$FIELD" 'id: boxedComp' \
        "and the style has its own chrome to draw"
    assert_file_contains "$FIELD" "root.type === StyledTextField.Boxed ? boxedComp" \
        "which is what the background resolves to for that style"
}

test_hover_feedback_belongs_to_whoever_draws_the_box() {
    assert_file_contains "$LAYER" 'root.showHoverBackground && (containsMouse' \
        "the setting has to be honoured, not just declared"
    assert_file_contains "$FIELD" 'showHoverBackground: root.type !== StyledTextField.Boxed' \
        "a boxed field tints its own box instead of painting a second rectangle inside it"
}

run_tests