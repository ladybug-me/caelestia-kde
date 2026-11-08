pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

// The floating card the desktop's panels hang off: one elevation, one fold, one
// clamped placement, one click catcher. Only what goes inside differs, so a panel
// declares its rows and leaves the rest here.
Elevation {
    id: root

    property bool open: false
    // Where the card would like its top-left corner. It stays on the screen either way.
    property point target: Qt.point(0, 0)

    readonly property real edge: Tokens.padding.large
    readonly property alias layout: body

    default property alias content: body.data

    x: Math.max(root.edge, Math.min(root.parent.width - root.width - root.edge, root.target.x))
    y: Math.max(root.edge, Math.min(root.parent.height - root.height - root.edge, root.target.y))
    radius: Tokens.rounding.large
    level: 2
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : 0.9
    transformOrigin: Item.TopLeft

    Behavior on opacity {
        Anim {
            type: Anim.FastEffects
        }
    }

    Behavior on scale {
        Anim {
            type: Anim.FastSpatial
        }
    }

    // The card takes the clicks that land on it and leaves the rest of the desktop
    // alone: this is an inspector, not a modal.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

    StyledRect {
        anchors.fill: parent
        radius: parent.radius
        color: GlobalConfig.appearance.pitchBlack ? "#000000" : Colours.palette.m3surfaceContainerLow

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium
        }
    }
}
