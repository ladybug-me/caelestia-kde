pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    property string state: "probing"
    property string manualCommand: ""

    readonly property bool canRun: root.state === "script"

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
                text: qsTr("Uninstall Caelestia?")
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.small
                text: {
                    if (root.state === "probing")
                        return qsTr("Still looking for the uninstaller. Try again in a moment.");
                    if (root.state === "script")
                        return qsTr("This opens the uninstaller in a terminal, where it asks for confirmation of its own. It removes the shell, its config files and its services, and can restore your pre-install configuration from a backup.");
                    if (root.state === "package")
                        return qsTr("This install belongs to a package, so the package manager owns its files. Remove it with:\n\n%1").arg(root.manualCommand);
                    return qsTr("No uninstaller script was found and no known package manager owns this install. Remove it the same way you installed it.");
                }
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
                    text: qsTr("Uninstall")
                    visible: root.canRun
                    activeColour: Colours.palette.m3error
                    inactiveColour: Colours.palette.m3error
                    activeOnColour: Colours.palette.m3onError
                    inactiveOnColour: Colours.palette.m3onError
                    enabled: root.state !== "probing"
                    onClicked: {
                        root.confirmed();
                        dialog.close();
                    }
                }
            }
        }
        }
}
