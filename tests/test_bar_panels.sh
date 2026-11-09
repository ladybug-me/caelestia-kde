#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRAWERS="$REPO_ROOT/shell/modules/drawers"
CONFIG_HPP="$REPO_ROOT/shell/plugin/src/Caelestia/Config/barconfig.hpp"
CONTENT_SRC="$(cat "$DRAWERS/ContentWindow.qml")"
PANEL_SRC="$(cat "$DRAWERS/PanelLayer.qml")"
REGIONS_SRC="$(cat "$DRAWERS/Regions.qml")"
INTERACTIONS_SRC="$(cat "$DRAWERS/Interactions.qml")"
POPOUT_STATE_SRC="$(cat "$REPO_ROOT/shell/modules/bar/popouts/PopoutState.qml")"
CONFIG_SRC="$(cat "$CONFIG_HPP")"

test_panel_schema_exposes_visibility_options() {
    assert_contains "$CONFIG_SRC" 'CONFIG_PROPERTY(bool, persistent, true)' "a panel must be able to leave the screen"
    assert_contains "$CONFIG_SRC" 'CONFIG_PROPERTY(bool, showOnHover, true)' "a panel must be able to follow the pointer"
    assert_contains "$CONFIG_SRC" 'CONFIG_PROPERTY(int, lengthPercent, 100)' "a panel must be able to take part of its edge"
    assert_contains "$CONFIG_SRC" 'CONFIG_PROPERTY(QString, align, u"center"_s)' "a partial panel must be placeable along its edge"
    assert_contains "$CONFIG_SRC" 'CONFIG_PROPERTY(QStringList, screens, QStringList())' "a panel must be able to name its screens"
    assert_eq 1 "$(grep -c 'CONFIG_LIST_TYPE(BarPanel, BarPanelList)' "$CONFIG_HPP")" "the panel list type must be declared once"
    assert_eq 1 "$(grep -c 'CONFIG_GLOBAL_LIST(BarPanelList, panels, {})' "$CONFIG_HPP")" "the global panel list must be declared once"
}

test_panels_default_to_staying_on_screen() {
    assert_eq 1 "$(printf '%s\n' "$PANEL_SRC" | grep -c 'persistent: modelData.panel.persistent !== false')" "an unset persistent must keep the panel on screen"
    assert_eq 1 "$(printf '%s\n' "$PANEL_SRC" | grep -c 'revealOnHover: modelData.panel.showOnHover !== false')" "an unset showOnHover must reveal the panel on hover"
    assert_contains "$PANEL_SRC" 'readonly property bool revealed: band.persistent || band.hovered || band.pulled' "a panel must stay out while it is hovered or pulled"
    assert_contains "$PANEL_SRC" 'readonly property bool takesSpace: band.persistent || band.pulled' "only a panel that stays or was pulled may take its space"
}

test_hidden_panels_reveal_from_the_strip_at_their_edge() {
    assert_contains "$PANEL_SRC" 'function updateReveal(x: real, y: real, pressed: bool, dragStart: point, dragX: real, dragY: real): void' "the reveal must take the pointer and the drag"
    assert_contains "$PANEL_SRC" 'if (band.inStrip(x, y))' "a hover must be tested against the strip the panel keeps"
    assert_contains "$PANEL_SRC" 'function inStrip(x: real, y: real): bool' "the strip must be its own predicate"
    assert_contains "$PANEL_SRC" 'band.pulled = true' "dragging inwards must pull the panel open"
    assert_contains "$PANEL_SRC" 'band.pulled = false' "dragging back out must close it again"
    assert_eq 2 "$(printf '%s\n' "$PANEL_SRC" | grep -c 'Config.bar.dragThreshold')" "the drag must use the bar's threshold on both directions"
}

test_reveal_is_cleared_when_the_pointer_leaves() {
    assert_contains "$PANEL_SRC" 'function clearReveal(): void' "the reveal must be clearable"
    assert_contains "$PANEL_SRC" 'band.hovered = false;' "clearing must hide the hovered panels"
    assert_contains "$INTERACTIONS_SRC" 'required property PanelLayer barPanels' "the interactions must know the panel layer"
    assert_contains "$INTERACTIONS_SRC" 'barPanels.updateReveal(x, y, pressed, dragStart, dragX, dragY)' "moving the pointer must drive the reveal"
    assert_contains "$INTERACTIONS_SRC" 'barPanels.clearReveal()' "leaving the frame must clear the reveal"
}

test_compositor_regions_follow_the_snapped_strip() {
    assert_contains "$PANEL_SRC" 'readonly property var strips: {' "the layer must hand out the strips"
    assert_contains "$PANEL_SRC" 'list.push(band.strip);' "a strip must be the band's own region"
    assert_contains "$PANEL_SRC" 'x: band.revealed ? band.revealedRect.x : band.restingRect.x' "a strip must snap to whether the panel is out"
    assert_contains "$PANEL_SRC" 'readonly property var revealedRect: ({' "the out rect must be a plain rectangle"
    assert_contains "$PANEL_SRC" 'readonly property var restingRect: band.horizontal ? ({' "the resting rect must be a plain rectangle"
    assert_contains "$REGIONS_SRC" 'required property var panelStrips' "the input mask must take the strips"
    assert_contains "$REGIONS_SRC" 'regions: root.panelStrips' "the cutouts must be the strips themselves"
    assert_contains "$CONTENT_SRC" 'panelLayer.strips' "the blur region must take the strips"
    assert_eq 0 "$(printf '%s\n' "$CONTENT_SRC$REGIONS_SRC" | grep -c 'Strips\[[0-9]')" "no fixed number of strips may be baked in"
    assert_contains "$PANEL_SRC" 'model: root.bands' "the islands must be drawn at the bands"
}

test_panel_bands_slide_through_the_frame_edge() {
    assert_contains "$PANEL_SRC" 'clip: true' "the band must be clipped so its content slides in"
    assert_contains "$PANEL_SRC" 'visible: band.horizontal ? band.height > Config.border.thickness : band.width > Config.border.thickness' "a band that is away must leave only the border"
    assert_contains "$PANEL_SRC" 'name: "hidden"' "a band that is away must have a hidden state"
    assert_contains "$PANEL_SRC" 'when: !band.revealed' "the hidden state must follow the reveal"
    assert_contains "$PANEL_SRC" 'from: ""' "the hidden state must be animated out of"
    assert_contains "$PANEL_SRC" 'to: "hidden"' "hiding must be a transition of its own"
    assert_contains "$PANEL_SRC" 'from: "hidden"' "coming back must be a transition of its own"
    assert_eq 3 "$(printf '%s\n' "$PANEL_SRC" | grep -c 'type: Anim.Emphasized')" "hiding must be emphasized"
    assert_eq 3 "$(printf '%s\n' "$PANEL_SRC" | grep -c 'type: Anim.DefaultSpatial')" "coming back must be a spatial default"
    assert_contains "$PANEL_SRC" 'property: "opacity"' "the rows must fade while the band slides"
}

test_only_full_edge_panels_thicken_the_frame() {
    assert_contains "$PANEL_SRC" 'thickness = Math.max(thickness, band.thickness);' "a panel that spans its edge must thicken the frame"
    assert_contains "$PANEL_SRC" 'if (band && band.edge === side && band.takesSpace)' "a panel must only keep its space while it takes it"
    assert_contains "$PANEL_SRC" 'if (band && band.full && band.edge === side)' "a partial panel must not thicken the frame"
    assert_contains "$PANEL_SRC" 'root.borderThickness, root.edges.left' "the frame edge must come from one place"
}

test_a_popout_origin_is_written_in_one_go() {
    assert_contains "$POPOUT_STATE_SRC" 'function setOrigin(newEdge: string, newInset: real, newPanelIndex: int): void {' "the origin must be settable atomically"
    assert_contains "$POPOUT_STATE_SRC" 'property real inset: 0' "the origin must carry the inset"
    assert_eq 0 "$(printf '%s\n' "$INTERACTIONS_SRC" | grep -c 'popouts\.currentInset')" "no call site may write the inset on its own"
    assert_eq 0 "$(printf '%s\n' "$INTERACTIONS_SRC" | grep -c 'popouts\.currentEdge')" "no call site may write the edge on its own"
}

run_tests
