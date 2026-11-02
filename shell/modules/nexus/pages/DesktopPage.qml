pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Desktop & Tiling")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        NavRow {
            first: true
            icon: "desktop_windows"
            label: qsTr("Desktop")
            status: Config.background.disableQuickshellDesktop ? qsTr("Disabled (Plasma)") : (Config.background.desktopIconsEnabled ? qsTr("Icons enabled") : qsTr("Icons disabled"))
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            icon: "extension"
            label: qsTr("Desktop Addons")
            status: qsTr("Visualiser, auto-hide, styling")
            enabled: !Config.background.disableQuickshellDesktop
            opacity: enabled ? 1.0 : 0.5
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "menu_open"
            label: qsTr("Right Click Menu")
            status: qsTr("Configure desktop right click menu")
            enabled: !Config.background.disableQuickshellDesktop
            opacity: enabled ? 1.0 : 0.5
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            last: true
            icon: "view_quilt"
            label: qsTr("Window Tiling")
            status: Config.general.krohnkiteEnabled ? qsTr("Enabled (Krohnkite)") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(3)
        }
    }
}

