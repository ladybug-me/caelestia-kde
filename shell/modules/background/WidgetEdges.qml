pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// Where every desktop card ends. A plugin may paint over the widgets -- the wallpaper
// depth one redraws the wallpaper's foreground above them -- so an edge drawn inside a
// card disappears along with the card. Drawn here instead, above every background
// layer, a widget behind a hill keeps its content hidden but still shows its outline.
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
}
