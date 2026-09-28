import ".."
import QtQuick
import qs.components

Item {
    id: root

    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    required property color overlayColor
    property bool showAimLines: true

    property bool breathingBorderOnly: false

    // Overlay to darken screen
    // Base dark overlay around region
    Rectangle {
        id: darkenOverlay

        z: 1
        visible: !root.breathingBorderOnly
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX - darkenOverlay.border.width
            topMargin: root.regionY - darkenOverlay.border.width
        }
        width: root.regionWidth + darkenOverlay.border.width * 2
        height: root.regionHeight + darkenOverlay.border.width * 2
        color: "transparent"
        border.color: root.overlayColor
        border.width: Math.max(root.width, root.height)
    }

    Rectangle {
        id: selectionBorder

        z: 9
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX) - borderWidth
            topMargin: Math.round(root.regionY) - borderWidth
        }
        width: Math.round(root.regionWidth) + borderWidth * 2
        height: Math.round(root.regionHeight) + borderWidth * 2

        border.color: root.color
        color: "transparent"

        property int borderWidth: 1

        opacity: 0.9

        SequentialAnimation on opacity {
            running: root.breathingBorderOnly
            loops: Animation.Infinite

            NumberAnimation { from: 0.9; to: 0.3; duration: 1200; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.3; to: 0.9; duration: 1200; easing.type: Easing.InOutQuad }
        }
    }

    StyledText {
        z: 2
        visible: !root.breathingBorderOnly
        anchors {
            top: selectionBorder.bottom
            right: selectionBorder.right
            margins: 8
        }
        color: root.color
        text: `${Math.round(root.regionWidth)} x ${Math.round(root.regionHeight)}`
    }

    Rectangle {
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        x: root.mouseX
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: root.color
    }
    Rectangle {
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        y: root.mouseY
        anchors {
            left: parent.left
            right: parent.right
        }
        height: 1
        color: root.color
    }
}
