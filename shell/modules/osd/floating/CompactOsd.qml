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
    property bool vertical: false
    readonly property real maxValue: type === "brightness" ? 1.0 : Math.max(1.0, GlobalConfig.services.maxVolume)
    readonly property real progress: isMuted ? 0 : Math.max(0, Math.min(1, maxValue > 0 ? (value / maxValue) : 0))
    readonly property bool isOverAmplified: !isMuted && value > 1.0
    readonly property Item panelItem: bg

    implicitWidth: vertical ? 44 : 240
    implicitHeight: vertical ? 200 : 38
    width: implicitWidth
    height: implicitHeight

    StyledRect {
        id: bg

        anchors.fill: parent
        radius: Surface.panelRounding
        color: Colours.layer(Colours.tPalette.m3surfaceContainerLowest, 2)
        clip: true

        Item {
            id: fillTrack

            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.top: root.vertical ? undefined : parent.top
            anchors.right: root.vertical ? parent.right : undefined
            width: root.vertical ? parent.width : Math.max(0, Math.min(bg.width, bg.width * root.progress))
            height: root.vertical ? Math.max(0, Math.min(bg.height, bg.height * root.progress)) : parent.height
            clip: true
            visible: root.vertical ? (height > 0.5) : (width > 0.5)

            Behavior on width {
                enabled: !root.vertical

                Anim {
                    type: Anim.Emphasized
                }
            }

            Behavior on height {
                enabled: root.vertical

                Anim {
                    type: Anim.Emphasized
                }
            }

            StyledRect {
                id: fillRect

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.top: root.vertical ? undefined : parent.top
                anchors.right: root.vertical ? parent.right : undefined
                width: bg.width
                height: bg.height
                radius: bg.radius
                color: root.isMuted ? Colours.palette.m3errorContainer : (root.isOverAmplified ? Colours.palette.m3tertiaryContainer : Colours.palette.m3secondaryContainer)
            }
        }

        Rectangle {
            visible: !root.vertical && root.maxValue > 1.0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            x: Math.round(bg.width * (1.0 / root.maxValue)) - 1
            width: 2
            color: Colours.palette.m3outlineVariant
            opacity: 0.6
        }

        Rectangle {
            visible: root.vertical && root.maxValue > 1.0
            anchors.left: parent.left
            anchors.right: parent.right
            y: Math.round(bg.height * (1.0 - 1.0 / root.maxValue)) - 1
            height: 2
            color: Colours.palette.m3outlineVariant
            opacity: 0.6
        }

        StyledRect {
            anchors.fill: parent
            radius: bg.radius
            color: "transparent"
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }

        RowLayout {
            visible: !root.vertical
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: root.icon
                fontStyle: Tokens.font.icon.small
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title.toUpperCase()
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
            }

            StyledText {
                text: root.isMuted ? qsTr("MUTED") : `${Math.round(root.value * 100)}%`
                font: Tokens.font.label.large
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3onSurface)
            }
        }

        Item {
            visible: root.vertical
            anchors.fill: parent

            StyledText {
                anchors.top: parent.top
                anchors.topMargin: Tokens.padding.large
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.isMuted ? qsTr("0%") : `${Math.round(root.value * 100)}%`
                font: Tokens.font.label.small
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3onSurface)
            }

            MaterialIcon {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.padding.large
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.icon
                fontStyle: Tokens.font.icon.small
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)
            }
        }
    }
}
