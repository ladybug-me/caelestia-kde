import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

ButtonBase {
    id: root

    property alias icon: label.text
    readonly property alias label: label
    // Opt-in: a glyph that swaps on an infrequent state change (play to pause) grows in
    // instead of snapping, the same cross-fade the bar's status icons use.
    property alias animateIcon: label.animate

    // A Material ligature is a poor label, but it beats an unnamed button. A
    // caller that knows the action should set accessibleName itself.
    accessibleName: icon.replace(/_/g, " ")

    font: Tokens.font.icon.medium
    padding: type === IconButton.Text ? Tokens.padding.extraSmall / 2 : Tokens.padding.small

    activeColour: type === IconButton.Filled ? Colours.palette.m3primary : Colours.palette.m3secondary
    inactiveColour: {
        if (!isToggle && type === IconButton.Filled)
            return Colours.palette.m3primary;
        return type === IconButton.Filled ? Colours.tPalette.m3surfaceContainer : Colours.palette.m3secondaryContainer;
    }
    activeOnColour: type === IconButton.Filled ? Colours.palette.m3onPrimary : type === IconButton.Tonal ? Colours.palette.m3onSecondary : Colours.palette.m3primary
    inactiveOnColour: {
        if (!isToggle && type === IconButton.Filled)
            return Colours.palette.m3onPrimary;
        return type === IconButton.Tonal ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant;
    }

    implicitWidth: implicitHeight
    implicitHeight: label.implicitHeight + padding * 2

    MaterialIcon {
        id: label

        anchors.centerIn: parent
        anchors.verticalCenterOffset: Centering.pixelAlign(parent.height, height)
        color: root.onColour
        fontStyle: root.font
        fill: !root.isToggle || root.internalChecked ? 1 : 0

        Behavior on fill {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
