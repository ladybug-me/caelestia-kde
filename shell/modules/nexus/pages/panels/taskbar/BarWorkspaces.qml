pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> displayTypeItems: [
        MenuItem {
            property int value: BarWorkspaceDisplay.Shapes

            text: qsTr("Shape")
        },
        MenuItem {
            property int value: BarWorkspaceDisplay.Text

            text: qsTr("Text")
        }
    ]

    title: qsTr("Workspaces")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Component.onCompleted: {
            let len = Kwin.workspaces.length;
            if (len > 0 && GlobalConfig.bar.workspaces.shown !== len) {
                GlobalConfig.bar.workspaces.shown = len;
            }
        }

        Connections {
            function onWorkspacesChanged(): void {
                let len = Kwin.workspaces.length;
                if (len > 0 && GlobalConfig.bar.workspaces.shown !== len) {
                    GlobalConfig.bar.workspaces.shown = len;
                }
            }

            target: Kwin
        }

        StepperRow {
            first: true
            label: qsTr("Shown")
            subtext: qsTr("Number of workspaces displayed")
            value: Config.bar.workspaces.shown
            from: 1
            to: 20
            stepSize: 1
            onMoved: v => {
                GlobalConfig.bar.workspaces.shown = v;
                let d = Kwin.workspaces;
                let count = d.length;
                while (count < v) {
                    Kwin.createWorkspace("Desktop " + (count + 1));
                    count++;
                }
                while (count > v) {
                    Kwin.removeWorkspace(d[count - 1].id);
                    count--;
                }
            }
        }

        ToggleRow {
            text: qsTr("Active indicator")
            checked: Config.bar.workspaces.activeIndicator
            onToggled: GlobalConfig.bar.workspaces.activeIndicator = checked
        }

        ToggleRow {
            text: qsTr("Active trail")
            checked: Config.bar.workspaces.activeTrail
            onToggled: GlobalConfig.bar.workspaces.activeTrail = checked
        }

        ToggleRow {
            text: qsTr("Occupied background")
            checked: Config.bar.workspaces.occupiedBg
            onToggled: GlobalConfig.bar.workspaces.occupiedBg = checked
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Indicator style")
            subtext: qsTr("Draw each workspace as a material shape or as its number")
            active: Config.bar.workspaces.displayType === BarWorkspaceDisplay.Text ? root.displayTypeItems[1] : root.displayTypeItems[0]
            menuItems: root.displayTypeItems
            onSelected: item => GlobalConfig.bar.workspaces.displayType = item.value
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show windows")
            subtext: qsTr("Show icons of open windows on each workspace")
            checked: Config.bar.workspaces.showWindows
            onToggled: GlobalConfig.bar.workspaces.showWindows = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show unoccupied")
            subtext: qsTr("Show workspaces that are inactive and empty")
            checked: Config.bar.workspaces.showUnoccupied
            onToggled: GlobalConfig.bar.workspaces.showUnoccupied = checked
        }

        ToggleRow {
            text: qsTr("Windows on special workspaces")
            checked: Config.bar.workspaces.showWindowsOnSpecialWorkspaces
            onToggled: GlobalConfig.bar.workspaces.showWindowsOnSpecialWorkspaces = checked
        }

        StepperRow {
            label: qsTr("Max window icons")
            value: Config.bar.workspaces.maxWindowIcons
            from: 0
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.bar.workspaces.maxWindowIcons = v
        }

        ToggleRow {
            last: true
            text: qsTr("Per monitor")
            subtext: qsTr("Hide workspaces not on the current monitor")
            checked: Config.bar.workspaces.perMonitor
            onToggled: GlobalConfig.bar.workspaces.perMonitor = checked
        }
    }
}

