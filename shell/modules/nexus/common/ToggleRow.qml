import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledSwitch {
    id: root

    property string subtext
    property var reset
    property alias first: bg.first
    property alias last: bg.last
    readonly property alias bg: bg

    Layout.fillWidth: true

    horizontalPadding: Tokens.padding.largeIncreased
    verticalPadding: Tokens.padding.medium
    font: Tokens.font.body.small

    implicitWidth: implicitContentWidth + implicitIndicatorWidth + horizontalPadding * 2
    implicitHeight: Math.max(implicitContentHeight, implicitIndicatorHeight) + verticalPadding * 2
    cLayer: 2

    indicator.anchors.verticalCenter: verticalCenter
    indicator.anchors.right: right
    indicator.anchors.rightMargin: root.horizontalPadding

    onPressed: stateLayer.press(stateLayer.mouseX, stateLayer.mouseY)

    background: ConnectedRect {
        id: bg

        StateLayer {
            id: stateLayer

            disabled: !root.enabled
            manualPressOverride: root.pressed
        }
    }

    contentItem: Item {
        anchors.left: parent.left
        anchors.right: root.indicator.left
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: Tokens.spacing.medium

        implicitWidth: column.implicitWidth + (resetBtn.visible ? resetBtn.implicitWidth + Tokens.spacing.small : 0)
        implicitHeight: Math.max(column.implicitHeight, resetBtn.visible ? resetBtn.implicitHeight : 0)

        SettingResetButton {
            id: resetBtn

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: root.reset
        }

        Column {
            id: column

            anchors.left: parent.left
            anchors.right: resetBtn.visible ? resetBtn.left : parent.right
            anchors.rightMargin: resetBtn.visible ? Tokens.spacing.small : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                id: label

                anchors.left: parent.left
                anchors.right: parent.right

                text: root.text
                font: root.font
                elide: Text.ElideRight
            }

            StyledText {
                anchors.left: parent.left
                anchors.right: parent.right

                visible: root.subtext
                text: root.subtext
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }
}
