pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts

    property string view: "wireless" // "wireless" or "ethernet"
    property var passwordNetwork: null
    property bool showPasswordDialog: false
    property bool _isSidebarOpen: false

    readonly property var activeDeviceDetails: root.view === "wireless" ? Nmcli.wirelessDeviceDetails : Nmcli.ethernetDeviceDetails
    readonly property var activeDetails: {
        const d = root.activeDeviceDetails;
        if (!d || typeof d !== "object" || Object.keys(d).length === 0)
            return { visible: false, rows: [] };

        const dnsList = Array.isArray(d.dns) ? d.dns : [];
        return {
            visible: true,
            rows: [
                { label: qsTr("IP address"), value: d.ipAddress ?? "" },
                { label: qsTr("Subnet mask"), value: d.subnet ?? "" },
                { label: qsTr("Gateway"), value: d.gateway ?? "" },
                { label: qsTr("DNS"), value: dnsList.join(", ") },
                { label: qsTr("MAC address"), value: d.macAddress ?? "" }
            ]
        };
    }

    // Injected by Content.qml's Popout.
    property real scaleOffset: 1.0
    property real fontScale: 1.0

    spacing: Tokens.spacing.medium * scaleOffset
    width: Math.max(400 * scaleOffset, _isSidebarOpen ? (Tokens.sizes.sidebar.width * scaleOffset) - Tokens.padding.extraLargeIncreased : 0)

    RowLayout {
        Layout.topMargin: Tokens.padding.small * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        Layout.rightMargin: Tokens.padding.small * root.scaleOffset
        Layout.fillWidth: true
        spacing: Tokens.spacing.small * root.scaleOffset

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Network")
            font.weight: 500
            font.pointSize: Tokens.font.title.small.pointSize * root.fontScale
        }

        IconButton {
            icon: "settings"
            font: Tokens.font.icon.medium
            type: IconButton.Tonal
            isRound: true
            inactiveColour: Colours.tPalette.m3surfaceContainerHigh
            inactiveOnColour: Colours.palette.m3onSurfaceVariant
            onClicked: root.popouts.detachRequested("network")
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitWidth: cardLayout.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: cardLayout

            width: parent.width - Tokens.padding.medium * 2 * root.scaleOffset
            x: Tokens.padding.medium * root.scaleOffset
            y: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.small * root.scaleOffset

    // Wireless section
    StyledText {
        visible: root.view === "wireless"

        Layout.topMargin: visible ? Tokens.padding.medium * root.scaleOffset : 0
        Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
        text: qsTr("Wireless")
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
    }

    PopoutToggleRow {
        visible: root.view === "wireless"
        scaleOffset: root.scaleOffset
        fontScale: root.fontScale
        label: qsTr("Enabled")
        checked: Nmcli.wifiEnabled
        toggle.onToggled: Nmcli.enableWifi(checked)
    }

    // Sits with the Wi-Fi switch rather than in the settings page because it is
    // the same kind of thing: one tap on the radio this machine broadcasts.
    // Hidden on a device that cannot run an access point at all.
    PopoutToggleRow {
        id: hotspotRow

        visible: root.view === "wireless" && Nmcli.hotspotSupported
        scaleOffset: root.scaleOffset
        fontScale: root.fontScale
        label: qsTr("Hotspot")

        toggle.onToggled: {
            // Putting the backend state back runs this again, and a switch that
            // already matches it is not an instruction to try.
            if (checked === Nmcli.hotspotEnabled)
                return;
            Nmcli.toggleHotspot();
        }

        // A Binding, not a plain binding: the switch writes checked itself when
        // it is tapped, which would leave it showing the tap rather than what the
        // hotspot is doing.
        Binding on checked {
            value: Nmcli.hotspotEnabled
        }
    }

    StyledText {
        visible: root.view === "wireless"

        Layout.topMargin: visible ? Tokens.spacing.small * root.scaleOffset : 0
        Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
        text: qsTr("%1 networks available").arg(Nmcli.networks.length) // qmllint disable missing-property
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
    }

    Repeater {
        visible: root.view === "wireless"
        model: ScriptModel {
            values: [...Nmcli.networks].sort((a, b) => {
                if (a.active !== b.active)
                    return b.active - a.active;
                return b.strength - a.strength;
            }).slice(0, 8)
        }

        StyledRect {
            id: networkItem

            required property Nmcli.AccessPoint modelData
            readonly property bool isConnecting: Nmcli.connectingSsid === modelData?.ssid
            readonly property bool loading: networkItem.isConnecting

            Layout.fillWidth: true
            Layout.preferredWidth: 0
            implicitHeight: networkRow.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
            visible: root.view === "wireless"
            radius: Tokens.rounding.small * root.scaleOffset
            color: networkItem.modelData?.active ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

            RowLayout {
                id: networkRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                spacing: Tokens.spacing.small * root.scaleOffset

                MaterialIcon {
                    text: Icons.getNetworkIcon(networkItem.modelData?.strength ?? 0)
                    color: networkItem.modelData?.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                }

                MaterialIcon {
                    visible: networkItem.modelData?.isSecure ?? false
                    text: "lock"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle.pointSize: Tokens.font.icon.small.pointSize * root.fontScale
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    elide: Text.ElideRight
                    text: networkItem.modelData?.ssid ?? ""
                    color: networkItem.modelData?.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                }

                Item {
                    Layout.preferredWidth: Tokens.font.icon.medium.pointSize * root.scaleOffset
                    Layout.preferredHeight: width

                    CircularIndicator {
                        anchors.fill: parent
                        running: networkItem.loading
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: networkItem.modelData?.active ? "check_circle" : "radio_button_unchecked"
                        color: networkItem.modelData?.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                        opacity: networkItem.loading ? 0 : 1
                    }
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: networkItem.radius
                disabled: networkItem.loading || !Nmcli.wifiEnabled

                onClicked: {
                    if (networkItem.modelData?.active) {
                        Nmcli.disconnectFromNetwork();
                    } else if (networkItem.modelData) {
                        NetworkConnection.handleConnect(networkItem.modelData, null, network => {
                            // Password is required - show password dialog
                            const networkSnapshot = {
                                ssid: network.ssid,
                                bssid: network.bssid || "",
                                isSecure: network.isSecure ?? true,
                                strength: network.strength ?? 0
                            };
                            NetworkConnection.passwordNetwork = networkSnapshot;
                            root.passwordNetwork = networkSnapshot;
                            root.showPasswordDialog = true;
                            root.popouts.currentName = "wirelesspassword";
                        });

                        // Connecting state is tracked by NmQt.connectingSsid and
                        // cleared by the backend on success, failure, or cancel.
                    }
                }
            }
        }
    }

    StyledRect {
        visible: root.view === "wireless"

        Layout.topMargin: visible ? Tokens.spacing.small * root.scaleOffset : 0
        Layout.fillWidth: true
        implicitHeight: rescanBtn.implicitHeight + Tokens.padding.small * root.scaleOffset

        radius: Tokens.rounding.full * root.scaleOffset
        color: Colours.palette.m3primaryContainer

        StateLayer {
            color: Colours.palette.m3onPrimaryContainer
            disabled: Nmcli.scanning || !Nmcli.wifiEnabled
            onClicked: Nmcli.rescanWifi()
        }

        RowLayout {
            id: rescanBtn

            anchors.centerIn: parent
            spacing: Tokens.spacing.small * root.scaleOffset
            opacity: Nmcli.scanning ? 0 : 1

            MaterialIcon {
                id: scanIcon

                Layout.topMargin: Math.round(fontInfo.pointSize * 0.0575)
                animate: true
                text: "wifi_find"
                color: Colours.palette.m3onPrimaryContainer
                fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
            }

            StyledText {
                Layout.topMargin: -Math.round(scanIcon.fontInfo.pointSize * 0.0575)
                text: qsTr("Rescan networks")
                color: Colours.palette.m3onPrimaryContainer
                font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        CircularIndicator {
            anchors.centerIn: parent
            strokeWidth: Tokens.padding.extraSmall / 2 * root.scaleOffset
            bgColour: "transparent"
            implicitSize: parent.implicitHeight - Tokens.padding.large * root.scaleOffset
            running: Nmcli.scanning
        }
    }

    // VPN section. Deliberately not gated on root.view: a saved VPN profile is
    // reachable whether the machine is on Wi-Fi or docked on Ethernet, and a
    // wired connection is exactly when the VPN profiles matter.
    PopoutSection {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.small * root.scaleOffset
        scaleOffset: root.scaleOffset
        fontScale: root.fontScale
        title: qsTr("VPN")
        expanded: false

        StyledText {
            Layout.topMargin: Tokens.spacing.extraSmall * root.scaleOffset
            Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
            text: qsTr("%1 profiles available").arg(Nmcli.vpnConnections.length)
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
        }

        Repeater {
            model: ScriptModel {
                values: [...Nmcli.vpnConnections].slice(0, 8)
            }

            StyledRect {
                id: vpnItem

                required property var modelData
                readonly property bool loading: Nmcli.vpnPendingConnection === modelData?.name

                Layout.fillWidth: true
                Layout.preferredWidth: 0
                implicitHeight: vpnRow.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
                radius: Tokens.rounding.small * root.scaleOffset
                color: vpnItem.modelData?.connected ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

                RowLayout {
                    id: vpnRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        text: "vpn_key"
                        color: vpnItem.modelData?.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        elide: Text.ElideRight
                        text: vpnItem.modelData?.name ?? ""
                        color: vpnItem.modelData?.connected ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                    }

                    Item {
                        Layout.preferredWidth: Tokens.font.icon.medium.pointSize * root.scaleOffset
                        Layout.preferredHeight: width

                        CircularIndicator {
                            anchors.fill: parent
                            running: vpnItem.loading
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: vpnItem.modelData?.connected ? "check_circle" : "radio_button_unchecked"
                            color: vpnItem.modelData?.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                            opacity: vpnItem.loading ? 0 : 1
                        }
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: vpnItem.radius
                    disabled: vpnItem.loading

                    onClicked: {
                        if (vpnItem.modelData?.connected) {
                            Nmcli.disconnectVpn(vpnItem.modelData.name, () => {});
                        } else if (vpnItem.modelData?.name) {
                            Nmcli.connectVpn(vpnItem.modelData.name, () => {});
                        }
                    }
                }
            }
        }

        StyledText {
            visible: Nmcli.vpnConnections.length === 0
            Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
            text: qsTr("No VPN profiles found")
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
        }
    }

    // Ethernet section
    StyledText {
        visible: root.view === "ethernet"

        Layout.topMargin: visible ? Tokens.padding.medium * root.scaleOffset : 0
        Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
        text: qsTr("Ethernet")
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
    }

    StyledText {
        visible: root.view === "ethernet"

        Layout.topMargin: visible ? Tokens.spacing.small * root.scaleOffset : 0
        Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
        text: qsTr("%1 devices available").arg(Nmcli.ethernetDevices.length)
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
    }

    Repeater {
        visible: root.view === "ethernet"
        model: ScriptModel {
            values: [...Nmcli.ethernetDevices].sort((a, b) => {
                if (a.connected !== b.connected)
                    return b.connected - a.connected;
                return (a.iface || "").localeCompare(b.iface || "");
            }).slice(0, 8)
        }

        StyledRect {
            id: ethernetItem

            required property var modelData
            readonly property bool loading: false

            Layout.fillWidth: true
            Layout.preferredWidth: 0
            implicitHeight: ethernetRow.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
            visible: root.view === "ethernet"
            radius: Tokens.rounding.small * root.scaleOffset
            color: ethernetItem.modelData?.connected ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

            RowLayout {
                id: ethernetRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                spacing: Tokens.spacing.small * root.scaleOffset

                MaterialIcon {
                    text: "cable"
                    color: ethernetItem.modelData?.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    elide: Text.ElideRight
                    text: ethernetItem.modelData?.interface || qsTr("Unknown")
                    color: ethernetItem.modelData?.connected ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                }

                Item {
                    Layout.preferredWidth: Tokens.font.icon.medium.pointSize * root.scaleOffset
                    Layout.preferredHeight: width

                    CircularIndicator {
                        anchors.fill: parent
                        running: ethernetItem.loading
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: ethernetItem.modelData?.connected ? "check_circle" : "radio_button_unchecked"
                        color: ethernetItem.modelData?.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                        opacity: ethernetItem.loading ? 0 : 1
                    }
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: ethernetItem.radius
                disabled: ethernetItem.loading

                onClicked: {
                    if (ethernetItem.modelData?.connected && ethernetItem.modelData?.connection) {
                        Nmcli.disconnectEthernet(ethernetItem.modelData.connection, () => {});
                    } else if (ethernetItem.modelData) {
                        Nmcli.connectEthernet(ethernetItem.modelData.connection || "", ethernetItem.modelData.interface || "", () => {});
                    }
                }
            }
        }
    }

    // Connection details (IP / subnet / gateway / DNS / MAC) for the active device
    PopoutSection {
        visible: root.activeDetails.visible
        Layout.fillWidth: true
        Layout.topMargin: visible ? Tokens.padding.medium * root.scaleOffset : 0
        scaleOffset: root.scaleOffset
        fontScale: root.fontScale
        title: qsTr("Connection details")
        expanded: false

        Repeater {
            model: root.activeDetails.rows

            RowLayout {
                required property var modelData

                visible: (modelData?.value ?? "") !== ""

                Layout.fillWidth: true
                Layout.rightMargin: Tokens.padding.extraSmall * root.scaleOffset
                spacing: Tokens.spacing.small * root.scaleOffset

                StyledText {
                    text: modelData?.label ?? ""
                    font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: modelData?.value ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                    font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                }
            }
        }
    }
        }
    }

    Connections {
        function onActiveChanged(): void {
            // Reset local dialog tracking if we successfully connected
            if (root.showPasswordDialog && root.passwordNetwork && Nmcli.active && Nmcli.active.ssid === root.passwordNetwork.ssid) {
                root.showPasswordDialog = false;
                root.passwordNetwork = null;
            }
        }

        function onScanningChanged(): void {
            if (!Nmcli.scanning)
                scanIcon.rotation = 0;
        }

        target: Nmcli
    }

    Connections {
        function onCurrentNameChanged(): void {
            // Clear password network when leaving password dialog
            if (root.popouts.currentName !== "wirelesspassword" && root.showPasswordDialog) {
                root.showPasswordDialog = false;
                root.passwordNetwork = null;
            }
        }

        target: root.popouts
    }
}
