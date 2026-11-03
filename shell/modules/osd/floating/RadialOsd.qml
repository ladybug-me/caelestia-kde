pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
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

    implicitWidth: 120
    implicitHeight: 120

    StyledRect {
        id: bgRect

        anchors.fill: parent
        radius: Surface.panelRounding
        color: Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 1)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        CircularProgress {
            anchors.centerIn: parent
            implicitSize: 92
            strokeWidth: 6
            value: root.progress
            fgColour: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)
            bgColour: Colours.palette.m3surfaceContainerHighest
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: root.icon
                fontStyle: Tokens.font.icon.large
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3primary)
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.isMuted ? qsTr("MUTED") : `${Math.round(root.value * 100)}%`
                font: Tokens.font.label.medium
                color: root.isMuted ? Colours.palette.m3error : (root.isOverAmplified ? Colours.palette.m3tertiary : Colours.palette.m3onSurface)
            }
        }
    }
}
