pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("System & Services")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("System")
        }

        NavRow {
            first: true
            icon: "power_settings_new"
            label: qsTr("Session")
            status: qsTr("Power, lock, and logout options")
            onClicked: root.nState.openSubPage(12)
        }

        NavRow {
            icon: "build"
            label: qsTr("System Services")
            status: qsTr("Lyrics, GPU, and system integration")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "language"
            label: qsTr("Language & Region")
            status: qsTr("System locale, spellcheck, and formats")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            icon: "accessibility_new"
            label: qsTr("Accessibility")
            status: qsTr("Vision, hearing, and interaction aids")
            onClicked: root.nState.openSubPage(5)
        }

        NavRow {
            icon: "storage"
            label: qsTr("Storage")
            status: qsTr("Mount points, free space, and drives")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            last: true
            icon: "info"
            label: qsTr("About")
            status: qsTr("Hardware, OS version, and shell info")
            onClicked: root.nState.openSubPage(11)
        }

        SectionHeader {
            text: qsTr("Services & Extensions")
        }

        NavRow {
            first: true
            icon: "sports_esports"
            label: qsTr("Discord Rich Presence")
            status: qsTr("Broadcast your activity to Discord")
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "calendar_today"
            label: qsTr("Calendar")
            status: qsTr("Sync calendar events and accounts")
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "rocket_launch"
            label: qsTr("Startup Applications")
            status: qsTr("Manage apps launched upon login")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "extension"
            label: qsTr("Plugins")
            status: qsTr("Manage installed extensions and add-ons")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "system_update"
            label: qsTr("Updates")
            status: qsTr("Check for package and system updates")
            onClicked: root.nState.openSubPage(10)
        }
    }
}
