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

    implicitWidth: 260
    implicitHeight: 84
    width: implicitWidth
    height: implicitHeight

    StyledRect {
        id: bgRect

        anchors.fill: parent
        radius: Surface.panelRounding
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 1)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: root.icon
                    fontStyle: Tokens.font.icon.small
                    color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledRect {
                    Layout.preferredHeight: 22
                    Layout.preferredWidth: badgeText.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.full
                    color: root.isMuted ? Colours.palette.m3errorContainer : (root.isOverAmplified ? Colours.palette.m3tertiaryContainer : Colours.palette.m3primaryContainer)

                    StyledText {
                        id: badgeText

                        anchors.centerIn: parent
                        text: root.isMuted ? qsTr("Muted") : `${Math.round(root.value * 100)}%`
                        font: Tokens.font.label.small
                        color: root.isMuted ? Colours.palette.m3onErrorContainer : (root.isOverAmplified ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onPrimaryContainer)
                    }
                }
            }

            Item {
                id: sliderContainer

                Layout.fillWidth: true
                Layout.preferredHeight: 12

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHighest
                }

                Rectangle {
                    visible: root.maxValue > 1.0
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.round(sliderContainer.width * (1.0 / root.maxValue)) - 1
                    width: 2
                    height: 8
                    radius: 1
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.9
                }

                StyledRect {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: sliderContainer.width * root.progress
                    radius: Tokens.rounding.full
                    color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)

                    Behavior on width {
                        Anim {
                            type: Anim.Emphasized
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: sliderContainer.width * 0.25
                    anchors.rightMargin: sliderContainer.width * 0.25

                    Item {
                        width: parent.width * 0.5
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 2
                            height: 6
                            radius: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.6
                        }
                    }

                    Item {
                        width: parent.width * 0.5
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 2
                            height: 6
                            radius: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.6
                        }
                    }
                }
            }
        }
    }
}
