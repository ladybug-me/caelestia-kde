pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property real value
    required property bool isMuted
    required property string icon
    required property string title
    required property string type
    readonly property real maxValue: type === "brightness" ? 1.0 : Math.max(1.0, GlobalConfig.services.maxVolume)
    readonly property real progress: isMuted ? 0 : Math.max(0, Math.min(1, maxValue > 0 ? (value / maxValue) : 0))
    readonly property bool isOverAmplified: !isMuted && value > 1.0
    readonly property Item panelItem: bgRect

    implicitWidth: 300
    implicitHeight: 28

    StyledRect {
        id: bgRect

        anchors.fill: parent
        radius: Surface.panelRounding
        color: Colours.layer(Colours.tPalette.m3surfaceContainerHighest, 1)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: root.icon
                fontStyle: Tokens.font.icon.small
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)
            }

            Item {
                id: barContainer

                Layout.fillWidth: true
                Layout.preferredHeight: 4

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerLow
                }

                Rectangle {
                    visible: root.maxValue > 1.0
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.round(barContainer.width * (1.0 / root.maxValue)) - 1
                    width: 2
                    height: parent.height
                    radius: 1
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.7
                }

                StyledRect {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: barContainer.width * root.progress
                    radius: Tokens.rounding.full
                    color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)

                    Behavior on width {
                        Anim {
                            type: Anim.Emphasized
                        }
                    }
                }
            }

            StyledText {
                text: root.isMuted ? qsTr("Muted") : `${Math.round(root.value * 100)}%`
                font: Tokens.font.label.small
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3outline)
            }
        }
    }
}
