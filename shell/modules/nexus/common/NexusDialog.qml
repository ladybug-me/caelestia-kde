pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// The frame every Nexus confirmation uses: centred modal, elevated surface, a
// title, a paragraph that explains the consequence, and two buttons. A caller
// that cannot confirm (because it is still deciding) leaves confirmText empty and
// gets the cancel-only variant.
Item {
    id: root

    property string title: ""
    property string message: ""
    property string confirmText: ""
    property string cancelText: qsTr("Cancel")
    property bool destructive: false

    signal confirmed

    function open(): void {
        dialog.open();
    }

    function close(): void {
        dialog.close();
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
                anchors.fill: surface
                level: 3
                radius: surface.radius
            }

            Rectangle {
                id: surface

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
                text: root.title
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.small
                text: root.message
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    text: root.cancelText
                    onClicked: dialog.close()
                }

                TextButton {
                    type: TextButton.Filled
                    visible: root.confirmText !== ""
                    text: root.confirmText
                    activeColour: root.destructive ? Colours.palette.m3error : Colours.palette.m3primary
                    inactiveColour: root.destructive ? Colours.palette.m3error : Colours.palette.m3primary
                    activeOnColour: root.destructive ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                    inactiveOnColour: root.destructive ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                    onClicked: {
                        root.confirmed();
                        dialog.close();
                    }
                }
            }
        }
    }
}
