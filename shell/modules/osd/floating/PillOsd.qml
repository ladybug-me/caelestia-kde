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

    implicitWidth: 280
    implicitHeight: 48

    StyledRect {
        id: bgRect

        anchors.fill: parent
        radius: Surface.panelRounding
        color: Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 1)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: Tokens.rounding.full
                color: root.isMuted ? Colours.palette.m3errorContainer : (root.isOverAmplified ? Colours.palette.m3tertiaryContainer : Colours.palette.m3primaryContainer)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.icon
                    fontStyle: Tokens.font.icon.small
                    color: root.isMuted ? Colours.palette.m3onErrorContainer : (root.isOverAmplified ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onPrimaryContainer)
                }
            }

            Item {
                id: trackContainer

                Layout.fillWidth: true
                Layout.preferredHeight: 8

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHighest
                }

                Rectangle {
                    visible: root.maxValue > 1.0
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.round(trackContainer.width * (1.0 / root.maxValue)) - 1
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
                    width: trackContainer.width * root.progress
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
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: root.isMuted ? qsTr("Muted") : `${Math.round(root.value * 100)}%`
                font: Tokens.font.label.large
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3onSurface)
            }
        }
    }
}
