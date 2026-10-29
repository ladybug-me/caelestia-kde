#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$REPO_ROOT/shell/modules/background"
ICONS="$DESKTOP/DesktopIcons.qml"
BIG="$DESKTOP/desktopicons/BigItem.qml"
CATALOG="$DESKTOP/desktopicons/WidgetCatalog.qml"
FORM="$DESKTOP/desktopicons/WidgetSettingsForm.qml"
PANEL="$DESKTOP/desktopicons/WidgetSettings.qml"
GALLERY="$DESKTOP/desktopicons/WidgetGallery.qml"
MENU="$DESKTOP/DesktopIconContextMenu.qml"
LAYOUT="$REPO_ROOT/shell/services/DesktopLayout.qml"
WINDOW="$REPO_ROOT/shell/modules/drawers/ContentWindow.qml"
WIDGETS="$DESKTOP/desktopicons/widgets"

# The body of a top-level QML function: from its signature to the closing brace at
# the same indent, so a test can talk about one function rather than a whole file.
function_body() {
    awk -v name="$2" '
        index($0, "function " name "(") { capture = 1 }
        capture { print }
        capture && /^    \}$/ { exit }
    ' "$1"
}

test_every_new_type_ships_its_widget() {
    for pair in "weather:WeatherWidget" "volume:VolumeWidget" "button:ButtonWidget" "sticker:StickerWidget"; do
        local type="${pair%%:*}" file="${pair##*:}"
        assert_file_exists "$WIDGETS/$file.qml"
        assert_file_contains "$CATALOG" "source: \"widgets/$file.qml\"" "the catalogue must offer the $type widget"
        assert_file_matches "$CATALOG" "type: \"$type\"," "the $type widget needs its own catalogue entry"
    done
}

test_a_type_gains_a_control_by_describing_it() {
    # The form is generic, so a control exists because the catalogue describes it.
    assert_contains "$(function_body "$CATALOG" settingsFor)" 'root.appearance' "the card's controls must come from one list"
    assert_contains "$(function_body "$CATALOG" settingsFor)" 'info(type).settings' "a type's controls must come from its own entry"
    assert_contains "$(function_body "$CATALOG" defaultsFor)" 'settingsFor(type)' "a widget must reset to what its entry describes"
    assert_file_contains "$CATALOG" 'key: "albumArtBackground", type: "toggle"' "toggles must be data"
    assert_file_contains "$CATALOG" 'key: "forecastDays", type: "slider"' "sliders must be data"
    assert_file_contains "$CATALOG" 'key: "device", type: "select"' "choices must be data"
    assert_file_contains "$CATALOG" 'key: "path", type: "path"' "file pickers must be data"
    assert_file_contains "$CATALOG" 'key: "command", type: "text"' "text fields must be data"
}

test_the_form_renders_every_row_kind() {
    for kind in toggle slider select path text; do
        assert_file_contains "$FORM" "case \"$kind\":" "the form must build a $kind row"
        assert_file_contains "$FORM" "id: ${kind}Field" "the $kind row needs its own component"
    done
    assert_file_contains "$FORM" 'onLoaded: item.field = modelData' "a row must be handed its schema entry"
}

test_the_inspector_writes_through_the_layout_store() {
    assert_file_contains "$FORM" 'DesktopLayout.setWidgetConfig(root.widgetId, patch)' "a field must write through the store that owns the layout"
    assert_file_contains "$FORM" 'DesktopLayout.resetWidgetConfig(root.widgetId)' "a reset must go the same way"
    assert_file_not_contains "$FORM" 'DesktopLayout.widgets[root.widgetId].config' "the form must not edit the config it is reading"
}

test_a_reset_replaces_the_config_instead_of_merging_it() {
    local body
    body="$(function_body "$LAYOUT" resetWidgetConfig)"
    assert_contains "$body" 'config: {}' "a reset must drop every key that was ever written"
    assert_not_contains "$body" 'w.config' "a merge would keep exactly the keys a reset is meant to remove"
    assert_contains "$body" 'setWidgets(next)' "the reset must still be saved like any other change"
    # A widget whose config a reset empties must fall back to what its type ships with,
    # or resetting Folder View would leave it pointing at no folder at all.
    assert_file_contains "$WIDGETS/FolderWidget.qml" 'frame?.info?.config?.path' "the folder must fall back to its type's default, not to nothing"
    assert_file_contains "$CATALOG" 'config: { path: Paths.home + "/Downloads" }' "that default must be the one the catalogue names"
}

test_the_form_starts_afresh_for_each_opening() {
    assert_contains "$(function_body "$PANEL" openAt)" 'root.refresh()' "opening must go through the one rebuild path"
    assert_contains "$(function_body "$PANEL" close)" 'root.refresh()' "closing must drop the form so the next opening starts clean"
    local body
    body="$(function_body "$PANEL" refresh)"
    assert_contains "$body" 'form.active = false' "the previous form must not be reused"
    assert_contains "$body" 'Qt.callLater' "the rebuild must wait for the new widget id"
    assert_file_contains "$PANEL" 'onTypeChanged: root.refresh()' "a type that arrives after the panel opened must still build the form"
}

test_the_card_edge_is_drawn_above_what_plugins_paint() {
    # The wallpaper depth plugin redraws the wallpaper's foreground above the widgets,
    # so an edge drawn inside a card vanishes under it. The edges live in their own
    # layer, above every background widget.
    local edges="$DESKTOP/WidgetEdges.qml"
    assert_file_exists "$edges"
    assert_file_contains "$BIG" 'readonly property rect edgeRect' "a card must report where its edge goes"
    assert_file_contains "$BIG" 'readonly property bool frameShown' "the editor's frame is drawn the same way"
    assert_file_not_contains "$BIG" 'id: cardEdge' "the edge must not be buried inside the card"
    assert_file_not_contains "$BIG" 'id: outline' "the frame must not be buried inside the card either"
    assert_file_contains "$edges" 'model: root.cards' "one edge per card"
    assert_file_contains "$edges" 'border.color: slot.modelData.edgeColor' "the edge takes the card's own colour"
    assert_file_contains "$DESKTOP/Background.qml" 'icons: desktopIcons' "the edge layer needs the cards it draws"
    assert_file_contains "$DESKTOP/Background.qml" 'z: 4096' "the edges must sit above the plugin background widgets"
}

test_the_panel_never_swallows_a_click_meant_for_something_else() {
    # A full-surface click-catcher sits above the desktop's menus and eats their clicks.
    assert_file_not_contains "$PANEL" 'enabled: root.open' "the panel must not cover the desktop with a backdrop"
    assert_file_not_contains "$PANEL" 'onPressed: root.close()' "clicks outside the panel belong to the desktop"
    assert_file_contains "$PANEL" 'onClicked: root.close()' "the panel needs its own way out"
    assert_file_contains "$PANEL" 'x: root.place.x' "the panel must place itself away from the widget"
    assert_contains "$(function_body "$PANEL" refresh)" 'form.active = false' "the panel is still rebuilt per opening"
}

test_the_panel_opens_away_from_the_widget_it_edits() {
    local place
    place="$(awk '/readonly property point place: \{/{f=1} f{print} f&&/^    \}$/{exit}' "$PANEL")"
    assert_contains "$place" 'a.x + a.width + gap' "it must be able to open to the right of the card"
    assert_contains "$place" 'a.x - w - gap' "it must be able to open to the left of the card"
    assert_contains "$place" 'a.y + a.height + gap' "it must be able to open under the card"
    assert_contains "$place" 'Math.min(root.width - w - edge, x)' "it must stay on screen"
    assert_contains "$(function_body "$ICONS" openWidgetSettings)" 'width: tile.width' "the screen must hand over the card's rectangle, not a point"
    assert_file_contains "$LAYOUT" 'signal widgetSettingsRequested(string screenName, var rect, string id)' "the request carries that rectangle across"
}

test_the_panel_is_in_the_window_s_input_mask() {
    # A layer window only accepts clicks inside its input region. Every popup the
    # window draws has to say it is open, or its clicks fall through to the desktop.
    local overlay
    overlay="$(grep -o 'readonly property bool transientOverlayOpen:.*' "$WINDOW" | head -1)"
    assert_contains "$overlay" 'widgetGallery.open' "the gallery is the model every popup follows"
    assert_contains "$overlay" 'widgetSettings.open' "the settings panel must make the window take input where it is drawn"
}

test_the_panel_is_only_as_tall_as_its_fields() {
    assert_file_contains "$PANEL" 'header.implicitHeight + Tokens.spacing.medium + Math.min(root.formHeight, root.maxFormHeight)' "the height must come from what the panel holds, not from a layout that lags"
    assert_file_contains "$PANEL" 'Layout.preferredHeight: Math.min(root.formHeight, root.maxFormHeight)' "a long form must be capped and scroll instead"
    assert_file_contains "$PANEL" 'root.height - Tokens.padding.large * 2' "it must never be taller than the screen"
}

test_the_card_takes_its_look_from_the_config() {
    assert_file_contains "$BIG" 'config.background === false' "a card can be switched off per widget"
    assert_file_contains "$BIG" 'config.backgroundOpacity' "the fill must follow the widget's opacity"
    assert_file_contains "$BIG" 'config.backgroundRadius' "the corners must follow the widget's radius"
    assert_file_contains "$BIG" 'Qt.alpha(GlobalConfig.appearance.pitchBlack ? "#000000" : Colours.palette.m3surfaceContainer, root.backgroundOpacity)' "the card's one colour must carry the opacity"
    assert_file_contains "$BIG" 'controller.widgetCatalog?.defaultBackgroundOpacity' "an unset widget must use the theme's value, not a second copy of it"
}

test_a_widget_may_hide_itself_and_the_editor_brings_it_back() {
    assert_file_contains "$BIG" 'content?.wantsHidden === true' "the card must follow a content's wish to step aside"
    assert_file_contains "$BIG" '!widgetEditMode && content?.wantsHidden === true' "hiding must not hide a widget from the editor"
    assert_file_contains "$WIDGETS/MediaWidget.qml" 'wantsHidden: cfg.hideWhenNoMedia === true && !root.player' "the player is what asks for it"
}

test_the_media_widget_can_be_laid_out_either_way() {
    assert_file_contains "$WIDGETS/MediaWidget.qml" 'columns: root.vertical ? 1 : 2' "the artwork must be able to sit above the text"
    assert_file_contains "$WIDGETS/MediaWidget.qml" 'cfg.layout === "vertical"' "the choice must come from the widget's settings"
    assert_file_contains "$WIDGETS/MediaWidget.qml" 'layer.effect: MultiEffect' "the artwork behind the player must be blurred"
    assert_file_contains "$WIDGETS/MediaWidget.qml" 'cfg.albumArtBackground === true' "the backdrop must be optional"
}

test_the_calendar_shares_the_month_and_lists_the_day() {
    assert_file_contains "$WIDGETS/CalendarWidget.qml" 'CalendarMonth {' "the month must be the one the bar shows, not a second grid"
    assert_file_contains "$WIDGETS/CalendarWidget.qml" 'selectable: true' "a day must be pickable for the agenda"
    assert_file_contains "$WIDGETS/CalendarWidget.qml" 'CalendarEvents.eventsOn(root.selectedDate)' "the agenda must be the shared calendar service"
    assert_file_contains "$WIDGETS/CalendarWidget.qml" 'Time.clockTime(event.start)' "an event's time must follow the clock's 12/24-hour choice"
    assert_file_contains "$WIDGETS/CalendarWidget.qml" 'cfg.showEvents !== false' "the agenda must be switchable"
}

test_the_weather_widget_only_shows_the_days_that_fit() {
    assert_file_contains "$WIDGETS/WeatherWidget.qml" 'Math.floor((root.height - 96) / 24)' "the forecast must fit the card it is in"
    assert_file_contains "$WIDGETS/WeatherWidget.qml" 'cfg.showForecast !== false' "the forecast must be switchable"
    assert_file_contains "$WIDGETS/WeatherWidget.qml" 'Weather.formatTemp' "temperatures must follow the configured unit"
}

test_the_button_runs_its_command_through_a_shell() {
    assert_file_contains "$WIDGETS/ButtonWidget.qml" 'Launch.exec(["sh", "-c", line])' "a command is a shell line, not an argv"
    assert_file_contains "$WIDGETS/ButtonWidget.qml" 'if (line !== "")' "an empty command must not start a shell"
}

test_the_volume_widget_fills_and_steers_the_default_device() {
    assert_file_contains "$WIDGETS/VolumeWidget.qml" 'cfg.device === "input"' "the microphone must be selectable"
    assert_file_contains "$WIDGETS/VolumeWidget.qml" 'height: track.height * root.filled' "the glyph must fill from the bottom"
    assert_file_contains "$WIDGETS/VolumeWidget.qml" 'node.audio.muted = !node.audio.muted' "the glyph must mute its own device"
    assert_file_contains "$WIDGETS/VolumeWidget.qml" 'WheelHandler {' "scrolling must change the level"
}

test_the_sticker_plays_an_animated_image() {
    assert_file_contains "$WIDGETS/StickerWidget.qml" 'CachingAnimatedImage {' "a GIF must play"
    assert_file_contains "$WIDGETS/StickerWidget.qml" 'CachingImage {' "a still image must be drawn as one"
    assert_file_contains "$WIDGETS/StickerWidget.qml" 'FileDialog {' "the image must be pickable on the desktop"
}

test_settings_are_reachable_from_the_card_and_the_menu() {
    assert_file_contains "$BIG" 'onClicked: root.settingsRequested()' "the editor's gear must open the settings"
    assert_file_contains "$BIG" 'visible: root.widgetEditMode && !root.isGroup' "the gear belongs to the editor"
    assert_file_contains "$ICONS" 'onSettingsRequested: root.openWidgetSettings(key)' "the card must hand its key to the screen"
    assert_contains "$(function_body "$ICONS" openWidgetSettings)" 'DesktopLayout.widgetSettingsRequested(' "the screen must not open the panel itself"
    assert_contains "$(function_body "$ICONS" editModeKey)" 'openWidgetSettings(picked[0])' "a picked widget must open its settings from the keyboard too"
    assert_file_contains "$MENU" 'onClicked: root.controller?.openWidgetSettings(root.firstKey)' "the widget's menu must offer the same panel"
    assert_file_contains "$WINDOW" 'widgetSettings.openAt(rect, id)' "one panel per screen must follow the request"
}

test_the_panel_goes_when_what_it_edits_goes() {
    assert_file_contains "$PANEL" 'if (open && widget === null)' "a removed widget must not leave its settings behind"
    assert_file_contains "$PANEL" 'target: WidgetEditor' "leaving the editor must close the panel"
}

test_the_gallery_scrolls_as_the_catalogue_grows() {
    assert_file_contains "$GALLERY" 'ScrollBar.vertical: StyledScrollBar {' "the gallery must not run off a short screen"
    assert_file_contains "$GALLERY" 'model: root.controller?.widgetCatalog?.types' "the gallery must list the catalogue, not a copy of it"
}

test_the_gallery_hint_points_at_the_settings() {
    assert_contains "$(cat "$GALLERY")" "gear in edit mode" "the gallery must say where the settings are"
}

test_a_card_edge_is_always_visible() {
    # A frameless card has no fill to read against, so its edge is the only thing
    # that says where the widget ends. It must be drawn, and drawn stronger.
    assert_file_contains "$BIG" 'readonly property int edgeWidth: root.selected || root.mergeTarget || root.focusVisible ? (root.widgetEditMode ? 3 : 2) : 1' "every card must keep an edge, frameless or not"
    assert_file_contains "$BIG" 'Qt.alpha(Colours.palette.m3onSurface, root.frameless ? 0.42 : 0.22)' "a card with no fill needs a stronger edge"
    # Selection brightens the edge: the card being edited must not be the faintest.
    assert_file_not_contains "$BIG" 'Qt.darker(Colours.palette.m3primary, 1.45)' "selection must not dim the edge"
    assert_file_contains "$BIG" '? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface' "a selected card's edge must stay at full strength"
}

run_tests
