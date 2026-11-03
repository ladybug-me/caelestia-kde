import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    property bool first
    property bool last
    property bool isSelected: false

    color: isSelected ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 4) : Colours.tPalette.m3surfaceContainer
    border.width: isSelected ? 2 : 0
    border.color: Colours.palette.m3primary
    topLeftRadius: isSelected ? Tokens.rounding.extraLargeIncreased : first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    topRightRadius: isSelected ? Tokens.rounding.extraLargeIncreased : first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    bottomLeftRadius: isSelected ? Tokens.rounding.extraLargeIncreased : last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    bottomRightRadius: isSelected ? Tokens.rounding.extraLargeIncreased : last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

    Behavior on topLeftRadius {
        Anim {}
    }
    Behavior on topRightRadius {
        Anim {}
    }
    Behavior on bottomLeftRadius {
        Anim {}
    }
    Behavior on bottomRightRadius {
        Anim {}
    }

    Behavior on color {
        CAnim {}
    }
}
