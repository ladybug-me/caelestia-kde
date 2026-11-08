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
    // The widget's settings with its type's defaults filled in -- the same resolution
    // the card uses, so the form never shows a value the desktop is not drawing with.
    readonly property var values: root.catalog ? root.catalog.configFor(root.type, root.widget?.config) : ({})

    function read(key: string): var {
        return key ? root.values[key] : undefined;
    }

    function write(key: string, value: var): void {
        if (!key)
            return;
        const patch = {};
        patch[key] = value;
        DesktopLayout.setWidgetConfig(root.widgetId, patch);
    }

    function percentValue(v: real): string {
        return `${Math.round(v * 100)}%`;
    }

    spacing: Tokens.spacing.medium

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
                    onClicked: picker.open()
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

                // Each row edits exactly one key, so the dialog's answers are constants
                // for the row rather than set just before it opens.
                readonly property string target: pathRow.field?.key ?? ""

                title: pathRow.folder ? qsTr("Choose a folder") : qsTr("Choose an image")
                selectFolder: pathRow.folder
                filters: pathRow.folder ? ["*"] : ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif"]
                filterLabel: pathRow.folder ? qsTr("All folders") : qsTr("Images")
                cwd: Paths.cwdSegments(pathRow.current)
                onAccepted: path => root.write(picker.target, path.replace(/^file:\/\//, "").replace(/\/+$/, ""))
            }
        }
    }
}
