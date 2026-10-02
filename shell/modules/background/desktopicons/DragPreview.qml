import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Rendered off screen and grabbed into the image that follows the pointer
// during a drag: the pressed icon and its label, with a badge when several
// files go along.
Item {
    id: root

    required property var controller
    property string key
    property int count: 1

    readonly property bool isGroup: controller.isGroupKey(key)

    width: controller.cellWidth
    height: controller.cellHeight

    IconTile {
        anchors.fill: parent
        iconSize: root.controller.iconSize
        materialYou: root.controller.materialYou
        vibrant: root.controller.vibrant
        isGroup: root.isGroup
        entry: root.controller.entryOf(root.key)
        groupName: ""
        groupMembers: root.isGroup ? root.controller.groupEntries(root.controller.nameOf(root.key)) : []
        enabled: false
        appear: 1
        opacity: 0.9
    }

    StyledRect {
        visible: root.count > 1
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: (root.width - root.controller.iconSize) / 2 - width / 3
        implicitWidth: Math.max(height, countText.implicitWidth + Tokens.padding.small * 2)
        implicitHeight: countText.implicitHeight + Tokens.padding.small
        radius: height / 2
        color: Colours.palette.m3primary

        StyledText {
            id: countText

            anchors.centerIn: parent
            text: root.count
            color: Colours.palette.m3onPrimary
            font: Tokens.font.label.small
        }
    }
}
