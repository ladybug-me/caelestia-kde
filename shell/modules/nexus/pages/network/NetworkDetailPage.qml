pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string ssid: nState.selectedNetworkSsid
    readonly property string uuid: nState.selectedNetworkUuid
    readonly property Nmcli.SavedProfile profile: Nmcli.savedConnectionProfiles.find(p => p.uuid === root.uuid) ?? null
    readonly property var ap: Nmcli.findNetwork(root.ssid)
    readonly property var details: Nmcli.wirelessDeviceDetails
    readonly property bool isActive: root.profile ? root.profile.active : (!!Nmcli.active && Nmcli.active.ssid === root.ssid)
    readonly property bool canConnect: !!root.profile && !root.isActive && !!root.ap

    property bool autoconnect: true

    function loadAutoconnect(): void {
        if (!root.uuid)
            return;
        Nmcli.getIpv4Config(root.uuid, cfg => {
            if (cfg)
                root.autoconnect = cfg.autoconnect;
        });
    }

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

        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * (root.isActive || root.canConnect ? 0.7 : 0.5))
            spacing: Tokens.spacing.small

            NetworkActionButton {
                icon: "delete"
                label: qsTr("Forget")
                error: true
                shapeMorph: root.isActive
                visible: !!root.profile
                onClicked: {
                    Nmcli.forgetNetworkByUuid(root.uuid);
                    root.nState.closeSubPage();
                }
            }

            NetworkActionButton {
                icon: "wifi"
                label: qsTr("Connect")
                visible: root.canConnect
                onClicked: {
                    NetworkConnection.connectToSavedProfile(root.uuid);
                    root.nState.closeSubPage();
                }
            }

            NetworkActionButton {
                icon: "link_off"
                label: qsTr("Disconnect")
                visible: root.isActive
                onClicked: {
                    Nmcli.disconnectFromNetwork();
                    root.nState.closeSubPage();
                }
            }
        }

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
                Nmcli.setAutoconnect(root.uuid, checked, () => {});
            }
        }

        Ipv4ConfigSection {
            Layout.fillWidth: true
            connectionId: root.uuid
        }
    }

    component NetworkActionButton: ButtonBase {
        id: action

        property string icon
        property string label
        property bool error

        fillWidth: true
        shapeMorph: true
        isRound: true
        inactiveColour: action.error ? Colours.palette.m3errorContainer : Colours.palette.m3primaryContainer
        inactiveOnColour: action.error ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimaryContainer

        implicitWidth: actionLayout.implicitWidth + Tokens.padding.extraLarge * 2
        implicitHeight: actionLayout.implicitHeight + Tokens.padding.medium * 2

        ColumnLayout {
            id: actionLayout

            anchors.centerIn: parent
            spacing: 0

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: action.icon
                color: action.onColour
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: action.label
                color: action.onColour
            }
        }
    }
}
