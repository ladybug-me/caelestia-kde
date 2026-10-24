pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var popouts

    property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    visible: enabled

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "toggle_on"
        color: (root.popouts.hasCurrent && (root.popouts.currentName === "shortcuts" || root.popouts.currentName === "elementscontext"))
            ? Colours.palette.m3onSecondaryContainer
            : Colours.palette.m3primary
        fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
    }

    MouseArea {
        id: clickArea

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (root.popouts.hasCurrent && root.popouts.currentName === "shortcuts") {
                    root.popouts.currentName = "";
                    root.popouts.hasCurrent = false;
                } else {
                    root.popouts.currentName = "shortcuts";
                    root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                    root.popouts.hasCurrent = true;
                }
            } else if (mouse.button === Qt.RightButton) {
                if (root.popouts.hasCurrent && root.popouts.currentName === "elementscontext") {
                    root.popouts.currentName = "";
                    root.popouts.hasCurrent = false;
                } else {
                    root.popouts.currentName = "elementscontext";
                    root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                    root.popouts.hasCurrent = true;
                }
            }
            mouse.accepted = true;
        }

        onEntered: {
            if (Config.bar.showOnHover && !root.popouts.hasCurrent) {
                root.popouts.currentName = "shortcuts";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            }
        }

        onExited: {
            if (Config.bar.showOnHover && root.popouts.currentName === "shortcuts" && !root.popouts.hasCurrent) {
                root.popouts.currentName = "";
                root.popouts.hasCurrent = false;
            }
        }
    }
}