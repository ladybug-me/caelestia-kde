pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

/// A value with a close button, for lists the user types into. The focus allow-list and
/// the muted notification apps are the same control, so they share it.
StyledRect {
    id: root

    property string label

    signal removed

    width: implicitWidth
    height: implicitHeight
    implicitWidth: chipLayout.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: chipLayout.implicitHeight + Tokens.padding.extraSmall * 2
    color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
    radius: Tokens.rounding.large

    RowLayout {
        id: chipLayout

        x: Tokens.padding.medium
        y: Tokens.padding.extraSmall
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: root.label
        }

        MaterialIcon {
            text: "close"
            font: Tokens.font.icon.small

            StateLayer {
                onClicked: root.removed()
            }
        }
    }
}
