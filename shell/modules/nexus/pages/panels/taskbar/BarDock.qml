pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Dock")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Enable component")
            checked: {
                for (let i = 0; i < Config.bar.entries.length; i++) {
                    if (Config.bar.entries[i].id === "dock")
                        return Config.bar.entries[i].enabled;
                }
                return false;
            }
            onToggled: {
                let newEntries = [...GlobalConfig.bar.entries];
                let found = false;
                for (let i = 0; i < newEntries.length; i++) {
                    if (newEntries[i].id === "dock") {
                        newEntries[i].enabled = checked;
                        if (!newEntries[i].zone)
                            newEntries[i].zone = "middle";
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    newEntries.push({ id: "dock", enabled: checked, zone: "middle" });
                }

                GlobalConfig.bar.entries = newEntries;
            }
        }



        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Icon size")
            subtext: qsTr("Size of app icons in the dock")
            value: Config.bar.dock.iconSize
            from: 20
            to: Math.max(20, Tokens.sizes.bar.innerWidth)
            stepSize: 2
            onMoved: v => GlobalConfig.bar.dock.iconSize = v
        }



        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Recolor icons")
            subtext: qsTr("Recolor application icons using the system theme")
            checked: Config.bar.dock.recolourIcons
            onToggled: GlobalConfig.bar.dock.recolourIcons = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show app badges")
            subtext: qsTr("Show the count, progress and urgency an app publishes for its dock icon")
            checked: Config.bar.dock.showBadges
            onToggled: GlobalConfig.bar.dock.showBadges = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Filter by current desktop")
            subtext: qsTr("Only show applications and windows belonging to the active virtual desktop")
            checked: Config.bar.dock.currentDesktopOnly
            onToggled: GlobalConfig.bar.dock.currentDesktopOnly = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Ungroup windows")
            subtext: qsTr("Give every window its own dock icon instead of combining them under one app")
            checked: Config.bar.dock.ungroupWindows
            onToggled: GlobalConfig.bar.dock.ungroupWindows = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Preview window on desktop")
            subtext: qsTr("Highlight and show the window itself on the workspace while hovering over dock previews")
            checked: Config.bar.dock.previewOnDesktop
            onToggled: GlobalConfig.bar.dock.previewOnDesktop = checked
        }
    }
}
