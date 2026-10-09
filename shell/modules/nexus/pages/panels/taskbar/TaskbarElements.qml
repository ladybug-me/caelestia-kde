pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Elements & Modules")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Main sections")
        }

        NavRow {
            first: true
            icon: "workspaces"
            label: qsTr("Workspaces")
            status: qsTr("Indicators, window icons")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "waving_hand"
            label: qsTr("Greeter")
            status: qsTr("Greeting display, popout")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "widgets"
            label: qsTr("Tray")
            status: qsTr("System tray icons")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            icon: "signal_cellular_alt"
            label: qsTr("Status icons")
            status: qsTr("Visible indicators")
            onClicked: root.nState.openSubPage(10)
        }

        NavRow {
            icon: "schedule"
            label: qsTr("Clock")
            status: qsTr("Date, icon, background")
            onClicked: root.nState.openSubPage(11)
        }

        NavRow {
            icon: "dock"
            label: qsTr("Dock")
            status: qsTr("Positioning, recoloring")
            onClicked: root.nState.openSubPage(12)
        }

        NavRow {
            icon: "code"
            label: qsTr("GitHub")
            status: qsTr("Contributions, token setup")
            onClicked: root.nState.openSubPage(13)
        }

        NavRow {
            icon: "graphic_eq"
            label: qsTr("Now playing")
            status: qsTr("Media widget, visualiser, volume")
            onClicked: root.nState.openSubPage(19)
        }

        NavRow {
            icon: "partly_cloudy_day"
            label: qsTr("Weather")
            status: qsTr("Widget units")
            onClicked: root.nState.openSubPage(20)
        }

        NavRow {
            icon: "speed"
            label: qsTr("Performance")
            status: qsTr("Widget pill")
            onClicked: root.nState.openSubPage(21)
        }

        NavRow {
            last: true
            icon: "update"
            label: qsTr("Updates")
            status: qsTr("Indicator visibility, automatic checks")
            onClicked: root.nState.openSubPage(17)
        }
    }
}
