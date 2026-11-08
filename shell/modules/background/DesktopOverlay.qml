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

    // Typed, so the three things this draws stay the icons layer's business: the cards
    // (not every tile) and the two rectangles it measures.
    property DesktopIcons icons: null

    readonly property var cards: root.icons ? root.icons.cardTiles : []
    readonly property point origin: root.icons ? root.icons.widgetOrigin : Qt.point(0, 0)

    // The icons layer hides itself (the Plasma widget editor, a screen with the desktop
    // turned off); the chrome goes with it rather than staying over the bare wallpaper.
    visible: root.icons !== null && root.icons.visible

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

        // The icons item hands the box over in window coordinates, unlike the cards: it
        // measures from its own corner rather than from the grid.
        visible: root.icons ? root.icons.bandShown : false
        x: band.x
        y: band.y
        width: band.width
        height: band.height
        radius: Tokens.rounding.small
        color: Qt.alpha(Colours.palette.m3primary, 0.18)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.7)
    }
}
