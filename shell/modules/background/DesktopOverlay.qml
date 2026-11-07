pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.services

// The desktop's own chrome, drawn above every background layer: the edge of each card
// and the box a drag selects with. A plugin may repaint the wallpaper over the widgets
// -- the wallpaper depth one redraws its foreground above them -- so anything drawn
// inside the icons layer disappears wherever that foreground covers it.
Item {
    id: root

    property var icons: null

    readonly property var cards: root.icons ? Object.values(root.icons.tiles) : []
    readonly property point origin: root.icons ? root.icons.widgetOrigin : Qt.point(0, 0)

    Repeater {
        model: root.cards

        Item {
            id: slot

            required property var modelData

            readonly property var rect: modelData.edgeRect

            x: root.origin.x + rect.x
            y: root.origin.y + rect.y
            width: rect.width
            height: rect.height
            opacity: modelData.opacity
            visible: modelData.edgeShown || modelData.frameShown

            Rectangle {
                anchors.fill: parent
                radius: slot.modelData.edgeRadius
                color: "transparent"
                border.width: slot.modelData.edgeWidth
                border.color: slot.modelData.edgeColor
            }

            Rectangle {
                anchors.fill: parent
                visible: slot.modelData.frameShown
                radius: slot.modelData.edgeRadius
                color: "transparent"
                border.width: 2
                border.color: Colours.palette.m3primary
            }
        }
    }

    Rectangle {
        readonly property rect band: root.icons ? root.icons.bandRect : Qt.rect(0, 0, 0, 0)

        visible: root.icons ? root.icons.bandShown : false
        x: root.origin.x + band.x
        y: root.origin.y + band.y
        width: band.width
        height: band.height
        radius: Tokens.rounding.small
        color: Qt.alpha(Colours.palette.m3primary, 0.18)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.7)
    }
}
