pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Detail / settings sub-page for the active Wi-Fi network. Reached by tapping
// the active network row (settings icon) on NetworkPage.
PageBase {
    id: root

    readonly property string ssid: nState.selectedNetworkSsid
    readonly property var ap: Nmcli.findNetwork(root.ssid)
    readonly property var details: Nmcli.wirelessDeviceDetails
    readonly property bool isActive: !!Nmcli.active && Nmcli.active.ssid === root.ssid

    property bool autoconnect: true

    function loadAutoconnect(): void {
        if (!root.ssid)
            return;
        Nmcli.getIpv4Config(root.ssid, cfg => {
            if (cfg)
                root.autoconnect = cfg.autoconnect;
        });
    }

    // Close if the network is no longer active (e.g. disconnected elsewhere).
    // ...But not when the page was opened from saved networks
    onApChanged: {
        if (!nState.networkDetailsFromSaved && !root.ap)
            nState.closeSubPage();
    }

    title: root.ssid || qsTr("Network")
    isSubPage: true

    Component.onCompleted: {
        Nmcli.getWirelessDeviceDetails("", () => {});
        loadAutoconnect();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---- Action buttons --------------------------------------------------
        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * (root.isActive ? 0.7 : 0.5))
            spacing: Tokens.spacing.small

            ButtonBase {
                id: forgetBtn

                fillWidth: true
                shapeMorph: root.isActive
                isRound: true
                inactiveColour: Colours.palette.m3errorContainer
                inactiveOnColour: Colours.palette.m3onErrorContainer

                implicitWidth: forgetLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: forgetLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    Nmcli.forgetNetwork(root.ssid);
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: forgetLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "delete"
                        color: forgetBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Forget")
                        color: forgetBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: disconnectBtn

                visible: root.isActive
                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer

                implicitWidth: disconnectLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: disconnectLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    Nmcli.disconnectFromNetwork();
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: disconnectLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "link_off"
                        color: disconnectBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Disconnect")
                        color: disconnectBtn.onColour
                    }
                }
            }
        }

        // ---- Connection info (only shows when active) ---------------------------------
        SectionHeader {
            first: true
            text: qsTr("Connection")
            visible: root.isActive
        }

        InfoRow {
            first: true
            icon: "signal_wifi_4_bar"
            label: qsTr("Signal")
            value: root.ap ? qsTr("%1%").arg(root.ap.strength) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "lock"
            label: qsTr("Security")
            value: root.ap?.security || qsTr("Open")
            visible: root.isActive
        }

        InfoRow {
            icon: "graphic_eq"
            label: qsTr("Frequency")
            value: root.ap && root.ap.frequency > 0 ? qsTr("%1 MHz").arg(root.ap.frequency) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "lan"
            label: qsTr("IP address")
            value: root.details?.ipAddress || qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "router"
            label: qsTr("Gateway")
            value: root.details?.gateway || qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            last: true
            icon: "memory"
            label: qsTr("MAC address")
            value: root.details?.macAddress || qsTr("—")
            visible: root.isActive
        }

        // ---- Behaviour -------------------------------------------------------
        SectionHeader {
            first: !root.isActive
            text: qsTr("Behaviour")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            last: true
            text: qsTr("Connect automatically")
            subtext: qsTr("Join this network when it's in range")
            checked: root.autoconnect
            onToggled: {
                root.autoconnect = checked;
                Nmcli.setAutoconnect(root.ssid, checked, () => {});
            }
        }

        Ipv4ConfigSection {
            Layout.fillWidth: true
            connectionName: root.ssid
        }
    }
}
