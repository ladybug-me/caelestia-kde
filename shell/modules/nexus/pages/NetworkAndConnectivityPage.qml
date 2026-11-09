pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Network & Connectivity")
    isSubPage: false

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Network")
        }

        NavRow {
            first: true
            icon: "wifi"
            label: qsTr("Network")
            status: Nmcli.activeWifiSsid ? Nmcli.activeWifiSsid : (Nmcli.wifiEnabled ? qsTr("Disconnected") : qsTr("Disabled"))
            onClicked: root.nState.openSubPage(13)
        }

        NavRow {
            icon: "network_check"
            label: qsTr("All Networks")
            status: qsTr("%1 available").arg(Nmcli.networks.length)
            onClicked: root.nState.openSubPage(5)
        }

        NavRow {
            icon: "history"
            label: qsTr("Saved Networks")
            status: qsTr("Manage known connections")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "wifi_tethering"
            label: qsTr("Hotspot")
            status: Nmcli.hotspot.active ? qsTr("Active") : qsTr("Inactive")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            last: true
            icon: "vpn_key"
            label: qsTr("Proxy")
            status: qsTr("Network proxy settings")
            onClicked: root.nState.openSubPage(8)
        }

        SectionHeader {
            text: qsTr("Bluetooth")
        }

        NavRow {
            first: true
            icon: "bluetooth"
            label: qsTr("Bluetooth")
            status: (Bluetooth.defaultAdapter?.enabled ?? false) ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(10)
        }

        NavRow {
            last: true
            icon: "add_circle"
            label: qsTr("Pair New Device")
            status: qsTr("Search for nearby Bluetooth devices")
            onClicked: root.nState.openSubPage(12)
        }
    }
}
