import ".."
import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

Rectangle {
    id: root

    required property var clientDimensions

    property color colBackground: Qt.alpha("#88111111", 0.9)
    property color colForeground: "#ddffffff"
    property bool showLabel: true
    property bool showIcon: false
    property bool targeted: false
    property color borderColor
    property color fillColor: "transparent"
    property string text: ""
    property string iconName: ""
    property real textPadding: 10

    z: 2
    color: fillColor
    border.color: borderColor
    border.width: targeted ? 4 : 2
    radius: 4

    Behavior on color {
        animation: ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    visible: opacity > 0
    Behavior on opacity {
        animation: NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    x: clientDimensions.at[0]

    y: clientDimensions.at[1]

    width: clientDimensions.size[0]

    height: clientDimensions.size[1]

    Loader {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: root.textPadding
            leftMargin: root.textPadding
        }
        
        active: root.showLabel
        sourceComponent: Rectangle {
            property real verticalPadding: 5
            property real horizontalPadding: 10

            radius: 10
            color: root.colBackground
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
            implicitWidth: regionInfoRow.implicitWidth + horizontalPadding * 2
            implicitHeight: regionInfoRow.implicitHeight + verticalPadding * 2

            Row {
                id: regionInfoRow

                anchors.centerIn: parent
                spacing: 4

                Loader {
                    id: regionIconLoader

                    active: root.showIcon
                    visible: active
                    sourceComponent: IconImage {
                        implicitSize: 18
                        source: Quickshell.iconPath(root.iconName.toLowerCase(), "image-missing")
                    }
                }

                StyledText {
                    id: regionText

                    text: root.text
                    color: root.colForeground
                }
            }
        }
    }
}