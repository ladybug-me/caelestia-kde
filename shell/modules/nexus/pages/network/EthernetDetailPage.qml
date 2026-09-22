pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Detail / settings sub-page for an ethernet device. Reached by tapping an
// ethernet row on NetworkPage.
PageBase {
    id: root

    readonly property string ifaceName: nState.selectedEthernetInterface
    readonly property Nmcli.EthernetDevice device: Nmcli.ethernetDevices.find(d => d.iface === root.ifaceName) ?? null
    readonly property var details: Nmcli.ethernetDeviceDetails
    readonly property string connectionName: root.device?.connection ?? ""

    title: root.device?.connection || root.ifaceName || qsTr("Ethernet")
    isSubPage: true

    Component.onCompleted: {
        Nmcli.getEthernetDeviceDetails(root.ifaceName, () => {});
        Nmcli.getEthernetSpeed(root.ifaceName);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---- Action button --------------------------------------------------
        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * 0.5)
            spacing: Tokens.spacing.small

            ButtonBase {
                id: connectBtn

                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: root.device?.connected ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer
                inactiveOnColour: root.device?.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer

                implicitWidth: connectLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: connectLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    if (root.device?.connected)
                        Nmcli.disconnectEthernet(root.connectionName);
                    else
                        Nmcli.connectEthernet(root.connectionName, root.ifaceName);
                }

                ColumnLayout {
                    id: connectLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.device?.connected ? "link_off" : "link"
                        color: connectBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.device?.connected ? qsTr("Disconnect") : qsTr("Connect")
                        color: connectBtn.onColour
                    }
                }
            }
        }

        // ---- Connection info ------------------------------------------------
        SectionHeader {
            first: true
            text: qsTr("Connection")
        }

        InfoRow {
            first: true
            icon: "link"
            label: qsTr("Status")
            value: root.device?.connected ? qsTr("Connected") : qsTr("Not connected")
        }

        InfoRow {
            icon: "settings_ethernet"
            label: qsTr("Interface")
            value: root.ifaceName || qsTr("—")
        }

        InfoRow {
            icon: "speed"
            label: qsTr("Speed")
            visible: Nmcli.ethernetSpeed.length > 0
            value: Nmcli.ethernetSpeed
        }

        InfoRow {
            icon: "lan"
            label: qsTr("IP address")
            value: root.details?.ipAddress || qsTr("—")
        }

        InfoRow {
            icon: "router"
            label: qsTr("Gateway")
            value: root.details?.gateway || qsTr("—")
        }

        InfoRow {
            last: true
            icon: "memory"
            label: qsTr("MAC address")
            value: root.details?.macAddress || qsTr("—")
        }

        Ipv4ConfigSection {
            Layout.fillWidth: true
            connectionName: root.connectionName
        }
    }
}
