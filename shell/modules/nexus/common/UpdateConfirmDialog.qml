pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    property string fromVersion: ""
    property string toVersion: ""

    signal confirmed

    function open(): void {
        dialog.open();
    }

    Popup {
        id: dialog

        width: 340
        padding: Tokens.padding.large
        height: contentColumn.implicitHeight + Tokens.padding.large * 2
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        parent: Overlay.overlay

        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0

        enter: DialogTransition {}
        exit: DialogTransition {
            exiting: true
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
                radius: Tokens.rounding.large
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
            }
        }

        contentItem: ColumnLayout {
            id: contentColumn

            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Restore %1?").arg(root.toVersion)
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.small
                text: root.fromVersion === ""
                    ? qsTr("This reinstalls an older version over the one installed now. Your settings are backed up first, and the shell restarts when it finishes.")
                    : qsTr("This replaces %1 with %2. Your settings are backed up first, and the shell restarts when it finishes.").arg(root.fromVersion).arg(root.toVersion)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.small

                Item { Layout.fillWidth: true }

                TextButton {
                    text: qsTr("Cancel")
                    onClicked: dialog.close()
                }

                TextButton {
                    type: TextButton.Filled
                    text: qsTr("Restore")
                    activeColour: Colours.palette.m3error
                    inactiveColour: Colours.palette.m3error
                    activeOnColour: Colours.palette.m3onError
                    inactiveOnColour: Colours.palette.m3onError
                    onClicked: {
                        root.confirmed();
                        dialog.close();
                    }
                }
            }
        }
    }
}
