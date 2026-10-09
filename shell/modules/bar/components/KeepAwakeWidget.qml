pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

    implicitWidth: isHorizontal ? Tokens.sizes.bar.innerWidth : Tokens.sizes.bar.innerWidth
    implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0)
    radius: Tokens.rounding.full

    visible: enabled

    MouseArea {
        id: clickArea

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        onClicked: {
            if (mouse.button === Qt.LeftButton) {
                IdleInhibitor.enabled = !IdleInhibitor.enabled;
            } else if (mouse.button === Qt.RightButton) {
                root.popouts.currentName = "keepawakecontext";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            }
            mouse.accepted = true;
        }

        onEntered: {
            if (Config.bar.showOnHover && !root.popouts.hasCurrent) {
                root.popouts.currentName = "keepawake";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            }
        }

        onExited: {
            if (Config.bar.showOnHover && root.popouts.currentName === "keepawake" && !root.popouts.hasCurrent) {
                root.popouts.currentName = "";
                root.popouts.hasCurrent = false;
            }
        }
    }

    Item {
        id: content

        anchors.centerIn: parent

        width: root.isHorizontal ? Tokens.sizes.bar.innerWidth : Tokens.sizes.bar.innerWidth
        height: root.isHorizontal ? Tokens.sizes.bar.innerWidth : Tokens.sizes.bar.innerWidth

        StyledRect {
            id: button

            anchors.centerIn: parent

            implicitWidth: isHorizontal ? Tokens.sizes.bar.innerWidth : implicitHeight
            implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : implicitHeight

            radius: Tokens.rounding.full
            color: IdleInhibitor.enabled ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: "coffee"
                color: IdleInhibitor.enabled ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.build()
            }

            MouseArea {
                anchors.fill: parent
                onClicked: IdleInhibitor.enabled = !IdleInhibitor.enabled
            }
        }

        Loader {
            id: activeChip

            sourceComponent: StyledRect {
                implicitWidth: text.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: text.implicitHeight + Tokens.padding.small

                radius: Tokens.rounding.full
                color: Colours.palette.m3primary

                StyledText {
                    id: text

                    anchors.centerIn: parent
                    text: IdleInhibitor.enabled ? qsTr("Active since %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, Units.twelveHourClock ? "hh:mm a" : "hh:mm")) : qsTr("Inactive")
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.body.builders.small.size(Math.round(Tokens.font.body.small.pointSize * 0.9)).build()
                }
            }

            active: IdleInhibitor.enabled
            anchors.top: button.bottom
            anchors.horizontalCenter: button.horizontalCenter
            anchors.topMargin: IdleInhibitor.enabled ? Tokens.spacing.small : 0
            opacity: IdleInhibitor.enabled ? 1 : 0
            scale: IdleInhibitor.enabled ? 1 : 0.5

            Behavior on opacity {
                Anim { type: Anim.StandardSmall }
            }

            Behavior on scale {
                Anim { type: Anim.StandardSmall }
            }
        }
    }
}
