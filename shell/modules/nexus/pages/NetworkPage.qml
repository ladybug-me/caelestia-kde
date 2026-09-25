pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Network")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            running: root.visible && Nmcli.wifiEnabled
            repeat: true
            triggeredOnStart: true
            interval: GlobalConfig.nexus.networkRescanInterval
            onTriggered: Nmcli.rescanWifi()
        }

        Timer {
            id: wifiScanDelay

            interval: 100
            onTriggered: Nmcli.rescanWifi()
        }

        Connections {
            function onWifiEnabledChanged(): void {
                if (Nmcli.wifiEnabled)
                    wifiScanDelay.start();
            }

            target: Nmcli
        }

        Loader {
            Layout.fillWidth: true
            active: Nmcli.hasAvailableEthernet
            visible: active
            asynchronous: true

            sourceComponent: EthernetSection {
                nState: root.nState
                cappedWidth: root.cappedWidth
            }
        }

        ToggleRow {
            Layout.topMargin: Nmcli.hasAvailableEthernet ? Tokens.spacing.large : 0
            first: true
            text: qsTr("Wi-Fi")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: Nmcli.wifiEnabled
            onToggled: Nmcli.enableWifi(checked)
        }

        NetworkList {
            Layout.bottomMargin: Nmcli.wifiEnabled && Nmcli.networks.length > GlobalConfig.nexus.maxNetworksShown ? 0 : -parent.spacing
            nState: root.nState
            limit: GlobalConfig.nexus.maxNetworksShown

            Behavior on Layout.bottomMargin {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // All networks button, only when > max networks
        ConnectedRect {
            Layout.fillWidth: true
            Layout.preferredHeight: Nmcli.wifiEnabled && Nmcli.networks.length > GlobalConfig.nexus.maxNetworksShown ? showAllLayout.implicitHeight + Tokens.padding.medium * 2 : 0
            clip: true

            Behavior on Layout.preferredHeight {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            StateLayer {
                onClicked: root.nState.openSubPage(5) // All networks sub-page
            }

            RowLayout {
                id: showAllLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "expand_content"
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Show all networks (%1)").arg(Nmcli.networks.length)
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    text: "chevron_right"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }
            }
        }

        // Saved networks button
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: savedNetworksLayout.implicitHeight + savedNetworksLayout.anchors.margins * 2

            StateLayer {
                onClicked: root.nState.openSubPage(6) // Saved networks sub-page
            }

            RowLayout {
                id: savedNetworksLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "bookmark"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    fill: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Saved networks")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    text: "chevron_right"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: addNetworkLayout.implicitHeight + addNetworkLayout.anchors.margins * 2

            StateLayer {
                onClicked: root.nState.openSubPage(2) // Add network sub-page
            }

            RowLayout {
                id: addNetworkLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "add"
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Add network")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: hotspotLayout.implicitHeight + hotspotLayout.anchors.margins * 2
            last: true

            StateLayer {
                onClicked: root.nState.openSubPage(7) // Hotspot sub-page
            }

            RowLayout {
                id: hotspotLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "wifi_tethering"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Hotspot")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: Nmcli.hotspotEnabled
                    text: Nmcli.hotspotSsid
                    color: Colours.palette.m3primary
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    text: "chevron_right"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }
            }
        }

        SectionHeader {
            text: qsTr("VPN connections")
        }

        ItemList {
            id: vpnList

            showList: true
            placeholderIcon: "vpn_key_off"
            placeholderText: qsTr("No VPN profiles found")

            model: ScriptModel {
                values: [...Nmcli.vpnConnections]
            }

            delegate: StyledRect {
                id: vpn

                required property var modelData
                readonly property bool loading: Nmcli.vpnPendingConnection === modelData.name
                readonly property bool connected: modelData.connected === true
                property real textOpacity: loading ? 0.5 : 1

                anchors.left: vpnList.list.contentItem.left
                anchors.right: vpnList.list.contentItem.right
                implicitHeight: vpnLayout.implicitHeight + vpnLayout.anchors.margins * 2
                radius: Tokens.rounding.extraSmall
                color: "transparent"

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                StateLayer {
                    disabled: vpn.loading
                    onClicked: {
                        if (vpn.loading)
                            return;

                        if (vpn.connected) {
                            Nmcli.disconnectVpn(vpn.modelData.name, () => {});
                        } else {
                            Nmcli.connectVpn(vpn.modelData.name, () => {});
                        }
                    }
                }

                RowLayout {
                    id: vpnLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: vpnIcon.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: vpn.connected ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                        MaterialIcon {
                            id: vpnIcon

                            anchors.centerIn: parent
                            text: "vpn_key"
                            color: vpn.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.medium
                            opacity: vpn.textOpacity
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: vpn.textOpacity

                        StyledText {
                            Layout.fillWidth: true
                            text: vpn.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: vpn.connected ? qsTr("Connected") : qsTr("Available")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        implicitWidth: height

                        AnimLoader {
                            anchors.centerIn: parent
                            sourceComp: vpn.loading ? vpnLoadingComp : vpnActionComp

                            Component {
                                id: vpnActionComp

                                MaterialIcon {
                                    text: vpn.connected ? "link_off" : "link"
                                    color: vpn.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.medium
                                    opacity: vpn.textOpacity
                                }
                            }

                            Component {
                                id: vpnLoadingComp

                                LoadingIndicator {
                                    implicitSize: Math.round(Tokens.font.icon.medium.pointSize * 1.3)
                                }
                            }
                        }
                    }
                }
            }
        }

        // VPN providers (WireGuard, WARP, NetBird, Tailscale)
        ToggleRow {
            Layout.topMargin: Tokens.spacing.large
            first: true
            text: qsTr("VPN providers")
            subtext: qsTr("WireGuard, WARP, NetBird, and Tailscale")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: VPN.connected
            enabled: !VPN.connecting && !VPN.disconnecting && VPN.providers.length > 0
            onToggled: VPN.toggle()

            Timer {
                running: root.visible
                repeat: true
                triggeredOnStart: true
                interval: 5000
                onTriggered: {
                    VPN.checkStatus();
                    if (VPN.connected)
                        VPN.refreshStats();
                }
            }
        }

        ItemList {
            id: providerList

            showList: true
            placeholderIcon: "add_circle"
            placeholderText: qsTr("No VPN providers configured")

            model: ScriptModel {
                values: [...VPN.providers]
            }

            delegate: Item {
                id: provider

                required property var modelData
                required property int index
                readonly property bool isSelected: modelData.id === VPN.selectedProvider
                readonly property bool isConnected: isSelected && VPN.connected

                anchors.left: providerList.list.contentItem.left
                anchors.right: providerList.list.contentItem.right
                implicitHeight: providerLayout.implicitHeight + providerLayout.anchors.margins * 2

                StateLayer {
                    disabled: provider.isSelected
                    radius: Tokens.rounding.extraSmall
                    onClicked: {
                        if (!provider.isSelected)
                            VPN.setActiveProvider(provider.index);
                    }
                }

                RowLayout {
                    id: providerLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: providerIcon.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: provider.isConnected ? Colours.palette.m3primaryContainer : provider.isSelected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            id: providerIcon

                            anchors.centerIn: parent
                            text: provider.isConnected || provider.isSelected ? "vpn_key" : "vpn_key_off"
                            fill: provider.isConnected ? 1 : 0
                            color: provider.isConnected ? Colours.palette.m3onPrimaryContainer : provider.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                            animate: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: provider.modelData.displayName || provider.modelData.name
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (!provider.isSelected)
                                    return qsTr("Tap to select");
                                if (VPN.connecting)
                                    return qsTr("Connecting...");
                                if (VPN.disconnecting)
                                    return qsTr("Disconnecting...");
                                switch (VPN.status.state) {
                                case "connected":
                                    return qsTr("Connected");
                                case "needs-auth":
                                    return VPN.status.reason || qsTr("Authentication required");
                                case "error":
                                    return VPN.status.reason || qsTr("An error occurred");
                                default:
                                    return qsTr("Selected");
                                }
                            }
                            color: {
                                if (!provider.isSelected)
                                    return Colours.palette.m3onSurfaceVariant;
                                switch (VPN.status.state) {
                                case "connected":
                                    return Colours.palette.m3primary;
                                case "needs-auth":
                                case "error":
                                    return Colours.palette.m3error;
                                default:
                                    return Colours.palette.m3secondary;
                                }
                            }
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Item {
                        Layout.rightMargin: Tokens.spacing.small
                        opacity: provider.isConnected && root?.cappedWidth > Tokens.sizes.nexus.networkShowVpnDetailWidth ? 1 : 0
                        visible: opacity > 0

                        implicitWidth: provider.isConnected && root?.cappedWidth > Tokens.sizes.nexus.networkShowVpnDetailWidth ? providerDetailRow.implicitWidth : 0
                        implicitHeight: providerDetailRow.implicitHeight

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        RowLayout {
                            id: providerDetailRow

                            anchors.right: parent.right
                            spacing: Tokens.spacing.large

                            ColumnLayout {
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: qsTr("Interface")
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: provider.modelData.interface
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            ColumnLayout {
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: qsTr("Current Ping")
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: Tokens.spacing.small

                                    StyledRect {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: Math.round(Tokens.font.body.small.pointSize * 0.7)
                                        implicitHeight: implicitWidth
                                        radius: Tokens.rounding.full
                                        color: VPN.pingMs <= 80 ? Colours.palette.m3primary : VPN.pingMs <= 150 ? Colours.palette.m3tertiary : Colours.palette.m3error
                                    }

                                    StyledText {
                                        text: qsTr("%1 ms").arg(VPN.pingMs)
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.small
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }

                    IconButton {
                        implicitWidth: implicitHeight + (Tokens.padding.large - padding) * 2
                        type: IconButton.Tonal
                        isRound: true
                        icon: "edit"
                        onClicked: {
                            root.nState.editingVpnIndex = provider.index;
                            root.nState.openSubPage(4); // Add/edit provider sub-page
                        }
                    }
                }
            }
        }

        RowButton {
            last: true
            icon: "add"
            text: qsTr("Add provider")
            onClicked: {
                root.nState.editingVpnIndex = -1;
                root.nState.openSubPage(4); // Add/edit provider sub-page
            }
        }
    }
}
