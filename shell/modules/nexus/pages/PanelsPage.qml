import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Panels")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        NavRow {
            first: true
            icon: "dashboard"
            label: qsTr("Dashboard")
            status: Config.dashboard.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(1)
        }
        NavRow {
            icon: "dock_to_bottom"
            label: qsTr("Taskbar")
            status: Config.bar.persistent ? qsTr("Always visible") : Config.bar.showOnHover ? qsTr("Reveal on hover") : qsTr("Reveal on drag")
            onClicked: root.nState.openSubPage(2)
        }
        NavRow {
            icon: "apps"
            label: qsTr("Launcher")
            status: Config.launcher.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(3)
        }
        NavRow {
            icon: "dock_to_right"
            label: qsTr("Sidebar")
            status: Config.sidebar.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(4)
        }
        NavRow {
            icon: "settings_input_component"
            label: qsTr("Quick toggle")
            status: Config.utilities.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(5)
        }
        NavRow {
            icon: "view_carousel"
            label: qsTr("Overview")
            status: Config.overview.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(16)
        }
        NavRow {
            last: true
            icon: "view_array"
            label: qsTr("Window Switcher")
            status: !Config.tabSwitch.enabled ? qsTr("Disabled") : (Config.tabSwitch.currentDesktopOnly ? qsTr("Current desktop only") : qsTr("All desktops"))
            onClicked: root.nState.openSubPage(18)
        }
    }
}
