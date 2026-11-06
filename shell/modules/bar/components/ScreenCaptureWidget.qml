pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property var popouts

    property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: (root.popouts.hasCurrent && (root.popouts.currentName === "screencapture" || root.popouts.currentName === "rearrangecontext"))
        ? Colours.palette.m3secondaryContainer
        : (clickArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent")
    radius: Tokens.rounding.full

    visible: enabled

    Behavior on color {
        CAnim {}
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: Recorder.running ? "screen_record" : "photo_camera"
        color: (root.popouts.hasCurrent && (root.popouts.currentName === "screencapture" || root.popouts.currentName === "rearrangecontext"))
            ? Colours.palette.m3onSecondaryContainer
            : Colours.palette.m3primary
        fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()

        Behavior on color {
            CAnim {}
        }
    }

    MouseArea {
        id: clickArea

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (root.popouts.hasCurrent && root.popouts.currentName === "screencapture") {
                    root.popouts.currentName = "";
                    root.popouts.hasCurrent = false;
                } else {
                    root.popouts.currentName = "screencapture";
                    root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                    root.popouts.hasCurrent = true;
                }
            } else if (mouse.button === Qt.RightButton) {
                if (root.popouts.hasCurrent && root.popouts.currentName === "rearrangecontext") {
                    root.popouts.currentName = "";
                    root.popouts.hasCurrent = false;
                } else {
                    root.popouts.currentName = "rearrangecontext";
                    root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                    root.popouts.hasCurrent = true;
                }
            }
            mouse.accepted = true;
        }

        onEntered: {
            if (Config.bar.showOnHover && !root.popouts.hasCurrent) {
                root.popouts.currentName = "screencapture";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            }
        }

        onExited: {
            if (Config.bar.showOnHover && root.popouts.currentName === "screencapture" && !root.popouts.hasCurrent) {
                root.popouts.currentName = "";
                root.popouts.hasCurrent = false;
            }
        }
    }
}
