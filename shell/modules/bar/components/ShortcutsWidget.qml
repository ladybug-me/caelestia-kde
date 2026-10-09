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

    implicitWidth: isHorizontal ? Tokens.sizes.bar.innerWidth : layout.implicitWidth
    implicitHeight: isHorizontal ? layout.implicitHeight : Tokens.sizes.bar.innerWidth

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
                root.popouts.currentName = "shortcuts";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            } else if (mouse.button === Qt.RightButton) {
                root.popouts.currentName = "shortcutscontext";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
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

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.medium

            Repeater {
                model: [
                    { name: qsTr("Nexus"), action: "nexus", icon: "dashboard" },
                    { name: qsTr("Launcher"), action: "launcher", icon: "apps" },
                    { name: qsTr("Overview"), action: "overview", icon: "view_array" },
                    { name: qsTr("Dashboard"), action: "dashboard", icon: "dashboard" },
                    { name: qsTr("Screenshot"), action: "screenshot", icon: "screenshot_region" },
                    { name: qsTr("Record"), action: "screenRecording", icon: "screen_record" },
                ]

                delegate: IconButton {
                    required property var modelData

                    type: IconButton.Tonal
                    isRound: true
                    icon: modelData.icon
                    onClicked: {
                        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "drawers", "toggle", modelData.action]);
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.medium

            Repeater {
                model: [
                    { name: qsTr("Terminal"), cmd: GlobalConfig.general.apps.terminal, icon: "terminal" },
                    { name: qsTr("Browser"), cmd: ["firefox"], icon: "web" },
                    { name: qsTr("Editor"), cmd: ["code"], icon: "code" },
                    { name: qsTr("Files"), cmd: ["nemo"], icon: "folder" },
                ]

                delegate: IconButton {
                    required property var modelData

                    type: IconButton.Tonal
                    isRound: true
                    icon: modelData.icon
                    onClicked: Launch.exec(modelData.cmd);
                }
            }
        }
    }
}
