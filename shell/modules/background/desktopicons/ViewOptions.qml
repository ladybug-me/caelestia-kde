pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// "Arrange Icons" panel opened from the desktop menu: one-off sorting, the
// auto-arrange switch and the icon size.
Item {
    id: root

    required property var controller
    property bool open: false
    property point at

    function openAt(x: real, y: real): void {
        at = Qt.point(x, y);
        open = true;
    }

    anchors.fill: parent
    visible: panel.opacity > 0

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.open = false
    }

    Elevation {
        id: panel

        x: Math.max(Tokens.padding.large, Math.min(root.width - width - Tokens.padding.large, root.at.x))
        y: Math.max(Tokens.padding.large, Math.min(root.height - height - Tokens.padding.large, root.at.y))
        width: content.implicitWidth + Tokens.padding.large * 2
        height: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        level: 2
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.9
        transformOrigin: Item.TopLeft

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: GlobalConfig.appearance.pitchBlack ? "#000000" : Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: qsTr("Sort by")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { key: "name", label: qsTr("Name") },
                            { key: "type", label: qsTr("Type") },
                            { key: "modified", label: qsTr("Date modified") },
                            { key: "size", label: qsTr("Size") }
                        ]

                        TextButton {
                            required property var modelData

                            type: TextButton.Tonal
                            // Shown as chosen only while it keeps applying, under auto-arrange.
                            internalChecked: DesktopLayout.autoArrange && DesktopLayout.sortKey === modelData.key
                            text: modelData.label
                            onClicked: root.controller.sortBy(modelData.key)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: qsTr("Arrange automatically")
                            font: Tokens.font.body.medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Keep icons packed; dragging reorders them")
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledSwitch {
                        checked: DesktopLayout.autoArrange
                        onToggled: root.controller.setAutoArrange(checked)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Rounded icon corners")
                        font: Tokens.font.body.medium
                    }

                    StyledSwitch {
                        checked: DesktopLayout.roundIcons
                        onToggled: DesktopLayout.setRoundIcons(checked)
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacing.small
                    text: qsTr("Icon size")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { size: 48, label: qsTr("Small") },
                            { size: 64, label: qsTr("Medium") },
                            { size: 80, label: qsTr("Large") },
                            { size: 96, label: qsTr("Huge") }
                        ]

                        TextButton {
                            required property var modelData

                            type: TextButton.Tonal
                            internalChecked: DesktopLayout.iconSize === modelData.size
                            text: modelData.label
                            onClicked: DesktopLayout.setIconSize(modelData.size)
                        }
                    }
                }

                StyledText {
                    text: qsTr("Tip: Ctrl+scroll on the desktop also resizes icons")
                    color: Colours.palette.m3outline
                }
            }
        }
    }
}
