pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Display & Sound")

    Component.onCompleted: Displays.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Display")
        }

        NavRow {
            first: true
            last: true
            icon: "display_settings"
            label: qsTr("Displays")
            status: qsTr("%1 display(s) connected").arg(Displays.outputs.length)
            onClicked: root.nState.openSubPage(11)
        }

        SectionHeader {
            text: qsTr("Sound & Audio")
        }

        NavRow {
            first: true
            icon: "volume_up"
            label: qsTr("Audio")
            status: Audio.muted ? qsTr("Muted") : qsTr("%1%").arg(Math.round(Audio.volume * 100))
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "tune"
            label: qsTr("App Volumes")
            status: Audio.appStreams.length === 0 ? qsTr("No apps playing audio") : Audio.appStreams.length === 1 ? qsTr("1 app playing audio") : qsTr("%1 apps playing audio").arg(Audio.appStreams.length)
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "music_note"
            label: qsTr("Sounds")
            status: qsTr("Notification and feedback sounds")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            last: true
            icon: "notifications_off"
            label: qsTr("Muted Apps")
            status: qsTr("Applications that send without sound")
            onClicked: root.nState.openSubPage(5)
        }

        SectionHeader {
            text: qsTr("Notifications")
        }

        NavRow {
            first: true
            icon: "notifications"
            label: qsTr("Notification Behaviour")
            status: qsTr("Position, timeout, and display behavior")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "campaign"
            label: qsTr("Toasts")
            status: qsTr("Fullscreen behavior, appearance, and sound")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "tune"
            label: qsTr("Toast Events")
            status: qsTr("Choose which system changes show a toast")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            last: true
            icon: "do_not_disturb_on"
            label: qsTr("Focus Sessions")
            status: Focus.active ? qsTr("Running until %1").arg(Focus.activeEnd()) : qsTr("Do Not Disturb on a schedule")
            onClicked: root.nState.openSubPage(9)
        }
    }
}
