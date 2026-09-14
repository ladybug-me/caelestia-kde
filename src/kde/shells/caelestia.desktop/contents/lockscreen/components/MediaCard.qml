/*
    SPDX-FileCopyrightText: 2024 ladybug-me
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import ".."
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root

    property var mediaInfo: ({})  // renamed from mediaInfo (review)
    readonly property bool hasMedia: Boolean(mediaInfo && mediaInfo.title)
    property real centerScale: 1.0

    property color clSurface: "#0a0f0f"
    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimary: "#9bd0cc"

    signal previousRequested()
    signal playPauseRequested()
    signal nextRequested()

    property real cardRadius: 26
    radius: cardRadius
    color: clSurfaceContainer
    clip: true

    implicitHeight: mediaContent.implicitHeight + 28 * root.centerScale

    // Album art background; only shown while media plays.
    Item {
        id: bgContainer
        anchors.fill: parent
        visible: root.hasMedia
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: maskRect
        }

        Image {
            anchors.fill: parent
            source: root.hasMedia ? (root.mediaInfo.artUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }

        Rectangle {
            anchors.fill: parent
            color: root.clSurface
            opacity: 0.6
        }
    }

    Rectangle {
        id: maskRect
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    ColumnLayout {
        id: mediaContent
        anchors.centerIn: parent
        width: parent.width * 0.9
        spacing: 6 * root.centerScale
        // Dim while nothing is playing, as upstream does.
        opacity: root.hasMedia ? 1.0 : 0.55
        Behavior on opacity { NumberAnimation { duration: 300 } }

        Text {
            Layout.fillWidth: true
            text: root.hasMedia ? (root.mediaInfo.title || "") : qsTr("Nothing playing")
            font { pixelSize: LockScreenConfig.sizeMedium; family: LockScreenConfig.fontHeading; weight: Font.Medium }
            color: root.clSurfaceFg
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            text: root.hasMedia ? (root.mediaInfo.artist || "") : qsTr("Try playing some music!")
            font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontHeading }
            color: root.clSurfaceVariantFg
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14 * root.centerScale
            Layout.topMargin: 8 * root.centerScale

            // Previous - disabled when !canGoPrevious (as upstream)
            Rectangle {
                implicitWidth: 36 * root.centerScale
                implicitHeight: 36 * root.centerScale
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                radius: 18 * root.centerScale
                color: Qt.rgba(255, 255, 255, root.hasMedia ? 0.1 : 0.06)

                Text {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    font.family: LockScreenConfig.fontIcon
                    font.pixelSize: LockScreenConfig.sizeLarge
                    color: root.hasMedia ? root.clSurfaceFg : root.clSurfaceVariantFg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasMedia
                    onClicked: root.previousRequested()
                }
            }

            // Play/Pause - pill shape, primary color when active
            Rectangle {
                implicitWidth: 60 * root.centerScale
                implicitHeight: 38 * root.centerScale
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                radius: 19 * root.centerScale
                color: root.hasMedia ? root.clPrimary : Qt.rgba(255, 255, 255, 0.08)

                Text {
                    anchors.centerIn: parent
                    text: (root.hasMedia && root.mediaInfo.status === "Playing") ? "pause" : "play_arrow"
                    font.family: LockScreenConfig.fontIcon
                    font.pixelSize: LockScreenConfig.sizeVeryLarge
                    color: root.hasMedia ? root.clSurface : root.clSurfaceVariantFg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasMedia
                    onClicked: root.playPauseRequested()
                }
            }

            // Next - disabled when !canGoNext (as upstream)
            Rectangle {
                implicitWidth: 36 * root.centerScale
                implicitHeight: 36 * root.centerScale
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                radius: 18 * root.centerScale
                color: Qt.rgba(255, 255, 255, root.hasMedia ? 0.1 : 0.06)

                Text {
                    anchors.centerIn: parent
                    text: "skip_next"
                    font.family: LockScreenConfig.fontIcon
                    font.pixelSize: LockScreenConfig.sizeLarge
                    color: root.hasMedia ? root.clSurfaceFg : root.clSurfaceVariantFg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasMedia
                    onClicked: root.nextRequested()
                }
            }
        }
    }
}
