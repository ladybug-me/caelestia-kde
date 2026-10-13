pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.utils
import qs.modules.bar
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> windowGroupingItems: [
        MenuItem {
            property int value: DockWindowGrouping.Combined

            text: qsTr("Group all windows")
        },
        MenuItem {
            property int value: DockWindowGrouping.PinnedFirst

            text: qsTr("Pinned icon holds first window")
        },
        MenuItem {
            property int value: DockWindowGrouping.Ungrouped

            text: qsTr("No grouping")
        }
    ]

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
            checked: BarWidgets.isEnabled(Config.bar, "dock")
            // Custom reset: enabled state lives in bar.entries, default is true
            reset: ({
                customGet: () => BarWidgets.isEnabled(GlobalConfig.bar, "dock"),
                customDef: true,
                customSet: v => BarWidgets.setEnabled(GlobalConfig.bar, "dock", v)
            })
            onToggled: BarWidgets.setEnabled(GlobalConfig.bar, "dock", checked)
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Icon size")
            subtext: qsTr("Size of app icons in the dock")
            reset: ({ node: GlobalConfig.bar.dock, setting: "iconSize" })
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
            reset: ({ node: GlobalConfig.bar.dock, setting: "recolourIcons" })
            checked: Config.bar.dock.recolourIcons
            onToggled: GlobalConfig.bar.dock.recolourIcons = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show app badges")
            subtext: qsTr("Show the count, progress and urgency an app publishes for its dock icon")
            reset: ({ node: GlobalConfig.bar.dock, setting: "showBadges" })
            checked: Config.bar.dock.showBadges
            onToggled: GlobalConfig.bar.dock.showBadges = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Filter by current desktop")
            subtext: qsTr("Only show applications and windows belonging to the active virtual desktop")
            reset: ({ node: GlobalConfig.bar.dock, setting: "currentDesktopOnly" })
            checked: Config.bar.dock.currentDesktopOnly
            onToggled: GlobalConfig.bar.dock.currentDesktopOnly = checked
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Window grouping")
            subtext: qsTr("How windows of one app share a dock icon: grouped, pinned icon holds the first window only, or every window on its own icon")
            active: Config.bar.dock.windowGrouping === DockWindowGrouping.Ungrouped ? root.windowGroupingItems[2] : Config.bar.dock.windowGrouping === DockWindowGrouping.PinnedFirst ? root.windowGroupingItems[1] : root.windowGroupingItems[0]
            menuItems: root.windowGroupingItems
            onSelected: item => GlobalConfig.bar.dock.windowGrouping = item.value
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Preview window on desktop")
            subtext: qsTr("Highlight and show the window itself on the workspace while hovering over dock previews")
            reset: ({ node: GlobalConfig.bar.dock, setting: "previewOnDesktop" })
            checked: Config.bar.dock.previewOnDesktop
            onToggled: GlobalConfig.bar.dock.previewOnDesktop = checked
        }
    }
}
