pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils

// The fields of one widget, built from the catalogue's schema and written straight
// into that widget's config. Created afresh for every opening, so each control
// starts on the value the widget actually holds rather than on the last drag.
ColumnLayout {
    id: root

    required property string widgetId
    required property string type
    required property var catalog

    readonly property var widget: DesktopLayout.widgets[root.widgetId] ?? null
    readonly property var settings: root.catalog ? root.catalog.settingsFor(root.type) : []
    readonly property var defaults: root.catalog ? root.catalog.defaultsFor(root.type) : ({})

    // Bumped by a reset. A control that was dragged has replaced its own binding
    // with what the drag wrote, so the fields reload from the config instead.
    property int reloadTick: 0

    spacing: Tokens.spacing.medium

    /// An unset key falls back to the type's default, which is what the widget
    /// itself draws with, so the form never shows a value the desktop is not using.
    function read(key: string): var {
        if (!key)
            return undefined;
        const value = root.widget?.config?.[key];
        return value === undefined ? root.defaults[key] : value;
    }

    function write(key: string, value: var): void {
        if (!key)
            return;
        const patch = {};
        patch[key] = value;
        DesktopLayout.setWidgetConfig(root.widgetId, patch);
    }

    function reset(): void {
        DesktopLayout.resetWidgetConfig(root.widgetId);
        root.reloadTick++;
    }

    function percentValue(v: real): string {
        return `${Math.round(v * 100)}%`;
    }

    Repeater {
        model: root.settings

        Loader {
            id: fieldLoader

            required property var modelData

            Layout.fillWidth: true
            sourceComponent: {
                switch (modelData.type) {
                case "toggle":
                    return toggleField;
                case "slider":
                    return sliderField;
                case "select":
                    return selectField;
                case "path":
                    return pathField;
                case "text":
                    return textField;
                default:
                    return textField;
                }
            }
            onLoaded: item.field = modelData
        }
    }

    Component {
        id: toggleField

        RowLayout {
            id: toggleRow

            property var field: null

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: toggleRow.field?.label ?? ""
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !!toggleRow.field?.description
                    text: toggleRow.field?.description ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }
            }

            StyledSwitch {
                id: toggle

                checked: toggleRow.field ? root.read(toggleRow.field.key) !== false : false
                onToggled: root.write(toggleRow.field.key, checked)

                Connections {
                    target: root

                    function onReloadTickChanged(): void {
                        toggle.checked = root.read(toggleRow.field.key) !== false;
                    }
                }
            }
        }
    }

    Component {
        id: sliderField

        ColumnLayout {
            id: sliderRow

            property var field: null

            readonly property real current: root.read(sliderRow.field?.key ?? "") ?? 0
            readonly property bool whole: sliderRow.field?.integer === true

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: sliderRow.field?.label ?? ""
                }

                StyledText {
                    text: sliderRow.whole ? String(Math.round(slider.value)) : root.percentValue(slider.value)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            StyledSlider {
                id: slider

                Layout.fillWidth: true
                from: sliderRow.field?.min ?? 0
                to: sliderRow.field?.max ?? 1
                stepSize: sliderRow.field?.step ?? 0
                value: sliderRow.current
                onInteraction: v => root.write(sliderRow.field.key, sliderRow.whole ? Math.round(v) : v)

                Connections {
                    target: root

                    function onReloadTickChanged(): void {
                        slider.value = sliderRow.current;
                    }
                }
            }
        }
    }

    Component {
        id: selectField

        ColumnLayout {
            id: selectRow

            property var field: null

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: selectRow.field?.label ?? ""
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: selectRow.field?.options ?? []

                    ToggleButton {
                        required property var modelData

                        Layout.fillWidth: true
                        label: modelData.label ?? ""
                        toggled: root.read(selectRow.field.key) === modelData.value
                        onClicked: root.write(selectRow.field.key, modelData.value)
                    }
                }
            }
        }
    }

    Component {
        id: textField

        ColumnLayout {
            id: textRow

            property var field: null

            readonly property string current: String(root.read(textRow.field?.key ?? "") ?? "")

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.fillWidth: true
                text: textRow.field?.label ?? ""
                font: Tokens.font.label.medium
            }

            StyledTextField {
                id: input

                Layout.fillWidth: true
                placeholderText: textRow.field?.placeholder ?? ""
                text: textRow.current
                // Every keystroke is written, not just the end of the edit: the panel can
                // be closed with a click outside, which would otherwise drop the value.
                onTextEdited: root.write(textRow.field.key, text)

                Connections {
                    target: root

                    function onReloadTickChanged(): void {
                        input.text = textRow.current;
                    }
                }
            }
        }
    }

    Component {
        id: pathField

        ColumnLayout {
            id: pathRow

            property var field: null

            readonly property string current: String(root.read(pathRow.field?.key ?? "") ?? "")
            readonly property bool folder: pathRow.field?.mode === "folder"

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.fillWidth: true
                text: pathRow.field?.label ?? ""
                font: Tokens.font.label.medium
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                TextButton {
                    Layout.fillWidth: true
                    text: pathRow.current !== "" ? pathRow.current.substring(pathRow.current.lastIndexOf("/") + 1) : (pathRow.field?.placeholder ?? qsTr("Choose…"))
                    type: TextButton.Filled
                    onClicked: {
                        picker.target = pathRow.field.key;
                        picker.selectFolder = pathRow.folder;
                        picker.filters = pathRow.folder ? ["*"] : ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif"];
                        picker.filterLabel = pathRow.folder ? qsTr("All folders") : qsTr("Images");
                        picker.open();
                    }
                }

                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    visible: pathRow.current !== ""
                    onClicked: root.write(pathRow.field.key, "")
                }
            }

            FileDialog {
                id: picker

                property string target: ""

                title: selectFolder ? qsTr("Choose a folder") : qsTr("Choose an image")
                cwd: pathRow.current.startsWith(Paths.home) ? ["Home", ...pathRow.current.substring(Paths.home.length).split("/").filter(s => s.length > 0)] : ["Home"]
                onAccepted: path => root.write(picker.target, path.replace(/^file:\/\//, "").replace(/\/+$/, ""))
            }
        }
    }
}
