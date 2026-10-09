pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Compact weather entry: icon plus temperature. Hover opens the popout.
StyledRect {
    id: root

    required property var popouts

    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    implicitWidth: isHorizontal ? contentLayout.implicitWidth + Tokens.padding.medium * 2 : Tokens.sizes.bar.innerWidth
    implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : contentLayout.implicitHeight + Tokens.padding.medium * 2

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0)
    radius: Tokens.rounding.full

    visible: enabled && Weather.temp !== ""

    Component.onCompleted: Weather.reload()

    RowLayout {
        id: contentLayout

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: Weather.icon
            color: Colours.palette.m3secondary
            fontStyle: Tokens.font.icon.builders.medium.build()
        }

        StyledText {
            visible: root.isHorizontal
            text: Weather.temp
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurface
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (!root.popouts)
                return;
            root.popouts.currentName = "weathercontext";
            root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
            root.popouts.hasCurrent = true;
            mouse.accepted = true;
        }
    }
}
