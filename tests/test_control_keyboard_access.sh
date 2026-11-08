#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLS="$REPO_ROOT/shell/components/controls"

test_buttons_are_named_and_reachable_by_keyboard() {
    local base
    base="$(cat "$CONTROLS/ButtonBase.qml")"

    assert_contains "$base" 'property string accessibleLabel' \
        "the base needs a name a leaf can fill in"
    assert_contains "$base" 'Accessible.role: Accessible.Button' "a button has to announce its role"
    assert_contains "$base" 'Accessible.name: accessibleLabel' "and the name the leaf supplied"
    assert_contains "$base" 'Accessible.checkable: isToggle' "a toggle button says it can be checked"
    assert_contains "$base" 'Accessible.checked: internalChecked' "and whether it is"
    assert_contains "$base" 'Accessible.onPressAction: activate()' \
        "an assistive tool pressing the button must do what a click does"
    assert_contains "$base" 'activeFocusOnTab:' "the button has to be reachable with Tab"
    assert_contains "$base" 'Keys.onSpacePressed: activate()' "Space activates it"
    assert_contains "$base" 'Keys.onReturnPressed: activate()' "Return activates it"
    assert_contains "$base" 'Keys.onEnterPressed: activate()' "and so does keypad Enter"
    # One path: the pointer, the keys and the accessibility press all end in activate().
    assert_contains "$base" 'onClicked: root.activate()' "a click must go through the same path"
    assert_contains "$base" 'visible: root.activeFocus' "keyboard focus needs something on screen"
}

test_button_leaves_supply_a_name() {
    assert_contains "$(cat "$CONTROLS/TextButton.qml")" 'accessibleLabel: root.text' \
        "a text button is named by its text"
    assert_contains "$(cat "$CONTROLS/IconButton.qml")" 'accessibleLabel: (root.icon || "").replace(/_/g, " ")' \
        "an icon button is named by its icon, with the separators knocked out"
    assert_contains "$(cat "$CONTROLS/IconTextButton.qml")" 'accessibleLabel: root.text' \
        "an icon-with-text button prefers the words"
}

test_switches_report_checked_state() {
    local switch
    switch="$(cat "$CONTROLS/StyledSwitch.qml")"

    assert_contains "$switch" 'Accessible.role: Accessible.CheckBox' "a switch is a check box to a screen reader"
    assert_contains "$switch" 'Accessible.name: root.text' "it is named by its text"
    assert_contains "$switch" 'Accessible.checkable: true' "it is checkable"
    assert_contains "$switch" 'Accessible.checked: root.checked' "and reports its state"
    assert_contains "$switch" 'Accessible.onToggleAction: root.toggle()' "an assistive tool can flip it"
    assert_contains "$switch" 'activeFocusOnTab:' "the switch has to be reachable with Tab"
    assert_contains "$switch" 'visible: root.activeFocus' "and show where focus is"

    # The plain row draws its own label, so the switch has to be given it.
    assert_contains "$(cat "$CONTROLS/ToggleRow.qml")" 'text: root.label' \
        "the row's label is the switch's name"
    # Nexus rows carry the label as text already; the subtext explains the row.
    assert_contains "$(cat "$REPO_ROOT/shell/modules/nexus/common/ToggleRow.qml")" \
        'Accessible.description: root.subtext' "the subtext belongs in the description"
}

test_text_fields_are_named_by_their_label() {
    local field
    field="$(cat "$CONTROLS/TextFieldBase.qml")"

    assert_contains "$field" 'property string accessibleLabel: root.placeholderText' \
        "the placeholder is the fallback name"
    assert_contains "$field" 'Accessible.name: accessibleLabel' \
        "a field must not be announced by the text it happens to hold"
}

test_checkboxes_toggle_from_the_keyboard() {
    local box
    box="$(cat "$CONTROLS/CheckBox.qml")"

    assert_contains "$box" 'Accessible.role: Accessible.CheckBox' "a check box announces its role"
    assert_contains "$box" 'Accessible.name: accessibleLabel' "and takes its name from the row"
    assert_contains "$box" 'Accessible.checked: checked' "and reports its state"
    assert_contains "$box" 'Accessible.onToggleAction: toggle()' "an assistive tool can flip it"
    assert_contains "$box" 'Keys.onSpacePressed: toggle()' "so can the keyboard"
    assert_contains "$box" 'onClicked: root.toggle()' "and a click takes the same path"
}

test_toggle_chips_are_named_and_reachable() {
    local chip
    chip="$(cat "$CONTROLS/ToggleButton.qml")"

    assert_contains "$chip" 'Accessible.role: Accessible.CheckBox' "a chip toggles, so it says so"
    assert_contains "$chip" 'Accessible.name: root.label || root.tooltip' \
        "the label names it, the tooltip is the fallback"
    assert_contains "$chip" 'Accessible.checked: root.toggled' "and it reports its state"
    assert_contains "$chip" 'activeFocusOnTab:' "the chip has to be reachable with Tab"
    assert_contains "$chip" 'Keys.onSpacePressed: root.clicked()' "Space activates it"
}

run_tests
