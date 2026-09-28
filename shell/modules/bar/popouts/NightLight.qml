pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    required property PopoutState popouts

    property bool _isSidebarOpen: false

    property real scaleOffset: 1.0
    property real fontScale: 1.0

    implicitWidth: Math.max(300 * scaleOffset, _isSidebarOpen ? (Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) * scaleOffset) - Tokens.padding.extraLargeIncreased : 0)
    spacing: Tokens.spacing.medium * scaleOffset

    StyledText {
        Layout.topMargin: Tokens.padding.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        text: qsTr("Night Light")
        font.weight: 500
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
    }

    IconTextButton {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small * root.scaleOffset
        inactiveColour: NightColor.autoMode ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceVariant
        inactiveOnColour: NightColor.autoMode ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        verticalPadding: Tokens.padding.small * root.scaleOffset
        text: NightColor.autoMode ? qsTr("Auto") : qsTr("Manual")
        icon: "routine"
        
        onClicked: {
            NightColor.toggleAutoMode();
        }
    }

    StyledText {
        visible: NightColor.autoMode
        Layout.topMargin: Tokens.spacing.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        text: qsTr("Daylight Temperature (%1K)").arg(Math.round(2000 + daySlider.pos * 4500))
        font.weight: Font.Medium
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
        font.features: { "tnum": 1 }
    }

    CustomMouseArea {
        visible: NightColor.autoMode
        Layout.fillWidth: true
        implicitHeight: Tokens.padding.medium * 3 * root.scaleOffset

        onWheel: event => {
            if (event.angleDelta.y > 0)
                NightColor.setDayTemperature(Math.min(6500, NightColor.dayTemperature + 100));
            else if (event.angleDelta.y < 0)
                NightColor.setDayTemperature(Math.max(2000, NightColor.dayTemperature - 100));
        }

        StyledSlider {
            id: daySlider

            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight

            value: Math.max(0, Math.min(1, (NightColor.dayTemperature - 2000) / 4500))
            onInteraction: v => NightColor.previewTemperature(Math.round(2000 + v * 4500))
            onReleased: v => {
                NightColor.stopPreview();
                NightColor.setDayTemperature(Math.round(2000 + v * 4500));
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        text: NightColor.autoMode ? qsTr("Nightlight Temperature (%1K)").arg(Math.round(2000 + nightSlider.pos * 4500)) : qsTr("Temperature (%1K)").arg(Math.round(2000 + nightSlider.pos * 4500))
        font.weight: Font.Medium
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
        font.features: { "tnum": 1 }
    }

    CustomMouseArea {
        Layout.fillWidth: true
        implicitHeight: Tokens.padding.medium * 3 * root.scaleOffset

        onWheel: event => {
            if (event.angleDelta.y > 0)
                NightColor.setNightTemperature(Math.min(6500, NightColor.nightTemperature + 100));
            else if (event.angleDelta.y < 0)
                NightColor.setNightTemperature(Math.max(2000, NightColor.nightTemperature - 100));
        }

        StyledSlider {
            id: nightSlider

            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight

            value: Math.max(0, Math.min(1, (NightColor.nightTemperature - 2000) / 4500))
            onInteraction: v => NightColor.previewTemperature(Math.round(2000 + v * 4500))
            onReleased: v => {
                NightColor.stopPreview();
                NightColor.setNightTemperature(Math.round(2000 + v * 4500));
            }
        }
    }
}
