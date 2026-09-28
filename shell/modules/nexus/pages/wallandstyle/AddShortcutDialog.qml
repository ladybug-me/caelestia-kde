pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components.controls as Controls
import qs.components.effects
import qs.services

Popup {
    id: root

    property var targetItem: null

    signal saved(string label, string cmd, string icon)

    width: 300
    padding: 24
    height: contentColumn.implicitHeight + 48
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    parent: Overlay.overlay

    x: targetItem && parent ? Math.min(parent.width - width - 16, Math.max(16, targetItem.mapToItem(parent, targetItem.width - width, targetItem.height + 8).x)) : (parent ? Math.round((parent.width - width) / 2) : 0)
    y: targetItem && parent ? Math.min(parent.height - height - 16, Math.max(16, targetItem.mapToItem(parent, 0, targetItem.height + 8).y)) : (parent ? Math.round((parent.height - height) / 2) : 0)

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Tokens.anim.durations.small }
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: Tokens.anim.durations.small; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Tokens.anim.durations.small }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: Tokens.anim.durations.small; easing.type: Easing.InCubic }
    }

    background: Item {
        Elevation {
            anchors.fill: bgRect
            level: 3
            radius: bgRect.radius
        }
        Rectangle {
            id: bgRect

            anchors.fill: parent
            color: Colours.palette.m3surfaceContainerHigh
            radius: 16
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }
    }

    contentItem: ColumnLayout {
        id: contentColumn

        spacing: 8

        Text {
            text: qsTr("Add Custom Shortcut")
            font: Tokens.font.body.large
            color: Colours.palette.m3onSurface
            Layout.fillWidth: true
            Layout.bottomMargin: 8
        }

        Controls.StyledTextField {
            id: labelField
            Layout.fillWidth: true

            placeholderText: qsTr("Label (e.g. Firefox)")
        }

        Controls.StyledTextField {
            id: commandField
            Layout.fillWidth: true

            placeholderText: qsTr("Command (e.g. firefox)")
        }

        Controls.StyledTextField {
            id: iconField
            Layout.fillWidth: true

            placeholderText: qsTr("Icon (e.g. firefox)")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            
            Controls.TextButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            Item { Layout.fillWidth: true }

            Controls.TextButton {
                text: qsTr("Save")
                enabled: labelField.text.length > 0 && commandField.text.length > 0
                onClicked: {
                    root.saved(labelField.text, commandField.text, iconField.text);
                    labelField.text = ""
                    commandField.text = ""
                    iconField.text = ""
                    root.close()
                }
            }
        }
    }
}
