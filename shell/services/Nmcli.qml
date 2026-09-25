pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components.misc

/// Thin adapter wrapping the C++ NmQt (NetworkManagerQt/D-Bus) singleton.
/// Preserves the legacy Nmcli API surface so existing QML consumers continue
/// to work without changes, while the actual heavy lifting is done by the
/// robust D-Bus backend instead of shelling out to nmcli.
Singleton {
    id: root

    // =========================================================================
    //  Delegated properties - sourced from NmQt (C++ backend)
    // =========================================================================

    readonly property bool isConnected: NmQt.isConnected
    property bool wifiEnabled: NmQt.wifiEnabled
    readonly property bool scanning: NmQt.scanning
    readonly property string connectingSsid: NmQt.connectingSsid

    readonly property var wirelessDeviceDetails: NmQt.wirelessDeviceDetails
    readonly property var ethernetDeviceDetails: NmQt.ethernetDeviceDetails

    // Ethernet devices are rebuilt as typed EthernetDevice objects so both the
    // legacy bar popout (`.interface`) and the Nexus pages (`.iface`) resolve.
    property list<EthernetDevice> __ethernetDevices: []
    readonly property list<EthernetDevice> ethernetDevices: __ethernetDevices
    readonly property EthernetDevice activeEthernet: __ethernetDevices.find(d => d.connected) ?? null
    readonly property bool hasAvailableEthernet: __ethernetDevices.some(d => d.state !== "unavailable")
    property string ethernetSpeed: ""
    property string ethernetDataUsage: ""
    readonly property var savedConnectionSecurity: NmQt.savedConnectionSecurity

    readonly property var vpnConnections: NmQt.vpnConnections
    readonly property var activeVpn: NmQt.activeVpn
    property string vpnPendingConnection: NmQt.vpnPendingConnection

    readonly property bool hotspotSupported: NmQt.hotspotSupported
    readonly property bool hotspotEnabled: NmQt.hotspotEnabled
    readonly property string hotspotSsid: NmQt.hotspotSsid

    property list<string> savedConnections: NmQt.savedConnections
    property list<string> savedConnectionSsids: NmQt.savedConnectionSsids

    readonly property var activeProcesses: []

    // =========================================================================
    //  AccessPoint list - built reactively from NmQt QVariantList
    // =========================================================================

    readonly property list<AccessPoint> networks: __networks
    property list<AccessPoint> __networks: []

    property AccessPoint active: null

    property var deviceStatus: null
    property var wirelessInterfaces: []
    property var ethernetInterfaces: []
    readonly property bool connecting: wirelessInterfaces.some(i => isConnectingState(i.state))
    property string activeInterface: ""
    property string activeConnection: ""
    property var wifiConnectionQueue: []
    property int currentSsidQueryIndex: 0
    property var pendingConnection: null

    readonly property string deviceTypeWifi: "wifi"
    readonly property string deviceTypeEthernet: "ethernet"
    readonly property string connectionTypeWireless: "802-11-wireless"
    readonly property string connectionTypeVpn: "vpn"
    readonly property string connectionTypeWireGuard: "wireguard"
    readonly property string nmcliCommandDevice: "device"
    readonly property string nmcliCommandConnection: "connection"
    readonly property string nmcliCommandWifi: "wifi"
    readonly property string nmcliCommandRadio: "radio"
    readonly property string deviceStatusFields: "DEVICE,TYPE,STATE,CONNECTION"
    readonly property string connectionListFields: "NAME,TYPE"
    readonly property string wirelessSsidField: "802-11-wireless.ssid"
    readonly property string networkListFields: "SSID,SIGNAL,SECURITY"
    readonly property string networkDetailFields: "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY"
    readonly property string securityKeyMgmt: "802-11-wireless-security.key-mgmt"
    readonly property string securityPsk: "802-11-wireless-security.psk"
    readonly property string keyMgmtWpaPsk: "wpa-psk"
    readonly property string connectionParamType: "type"
    readonly property string connectionParamConName: "con-name"
    readonly property string connectionParamIfname: "ifname"
    readonly property string connectionParamSsid: "ssid"
    readonly property string connectionParamPassword: "password"
    readonly property string connectionParamBssid: "802-11-wireless.bssid"

    readonly property alias connectionCheckTimer: connectionCheckTimer
    readonly property alias immediateCheckTimer: immediateCheckTimer

    // Guards against spurious notifications at shell startup.
    // Becomes true ~3 s after the shell is ready so we don't toast
    // "Wi-Fi connected" for the network that was already active.


    signal connectionSuccessful(string ssid)
    signal connectionFailed(string ssid)
    signal monitorEvent()

    function rebuildActive(): void {
        const raw = NmQt.active;
        if (raw && raw.ssid && raw.ssid.length > 0) {
            const found = __networks.find(n => n.ssid === raw.ssid) ?? null;
            if (found) {
                root.active = found;
            } else if (!root.active || root.active.ssid !== raw.ssid) {
                root.active = apComp.createObject(root, { lastIpcObject: raw });
            }
            if (root.pendingConnection && root.active && root.active.ssid && root.active.ssid.toLowerCase().trim() === root.pendingConnection.ssid.toLowerCase().trim()) {
                const pending = root.pendingConnection;
                root.pendingConnection = null;
                connectionCheckTimer.stop();
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
                root.connectionSuccessful(pending.ssid);
                if (pending.callback && typeof pending.callback === "function") {
                    pending.callback({ success: true, output: "Connected", error: "", exitCode: 0 });
                }
            }
        } else if (root.active !== null) {
            root.active = null;
        }
    }

    function rebuildNetworkList(): void {
        const rawList = NmQt.networks;
        const newList = [];
        const oldMap = new Map();

        for (let i = 0; i < __networks.length; i++) {
            const ap = __networks[i];
            if (ap && ap.ssid) {
                const key = ap.bssid || ap.ssid;
                oldMap.set(key, ap);
            }
        }

        for (let i = 0; i < rawList.length; i++) {
            const raw = rawList[i];
            const key = raw.bssid || raw.ssid;
            const existing = oldMap.get(key);
            if (existing) {
                existing.lastIpcObject = raw;
                newList.push(existing);
                oldMap.delete(key);
            } else {
                newList.push(apComp.createObject(root, { lastIpcObject: raw }));
            }
        }

        oldMap.forEach(ap => {
            ap.destroy();
        });

        root.__networks = newList;
    }

    // =========================================================================
    //  Delegated methods
    // =========================================================================

    function detectPasswordRequired(error: string): bool {
        if (!error || error.length === 0) return false;
        return (error.includes("Secrets were required")
            || error.includes("Secrets were required, but not provided")
            || error.includes("No secrets provided")
            || error.includes("802-11-wireless-security.psk")
            || error.includes("password for")
            || (error.includes("password") && !error.includes("Connection activated") && !error.includes("successfully"))
            || (error.includes("Secrets") && !error.includes("Connection activated") && !error.includes("successfully")));
    }

    function parseNetworkOutput(output: string): list<var> {
        const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
        const rep = new RegExp("\\\\:", "g");
        const rep2 = new RegExp(PLACEHOLDER, "g");
        return (output || "").trim().split("\n").filter(line => line && line.length > 0).map(n => {
            const net = n.replace(rep, PLACEHOLDER).split(":");
            return {
                active: net[0] === "yes",
                strength: parseInt(net[1] || "0", 10) || 0,
                frequency: parseInt(net[2] || "0", 10) || 0,
                ssid: (net[3]?.replace(rep2, ":") ?? "").trim(),
                bssid: (net[4]?.replace(rep2, ":") ?? "").trim(),
                security: (net[5] ?? "").trim()
            };
        }).filter(n => n.ssid && n.ssid.length > 0);
    }

    function deduplicateNetworks(networks: list<var>): list<var> {
        if (!networks || networks.length === 0) return [];
        const networkMap = new Map();
        for (const network of networks) {
            const existing = networkMap.get(network.ssid);
            if (!existing) networkMap.set(network.ssid, network);
            else if (network.active && !existing.active) networkMap.set(network.ssid, network);
            else if (!network.active && !existing.active && network.strength > existing.strength) networkMap.set(network.ssid, network);
        }
        return Array.from(networkMap.values());
    }

    function isConnectionCommand(command: list<string>): bool {
        if (!command || command.length === 0) return false;
        return command.includes(root.nmcliCommandWifi) || command.includes(root.nmcliCommandConnection);
    }

    function parseDeviceStatusOutput(output: string, filterType: string): list<var> {
        if (!output || output.length === 0) return [];
        const interfaces = [];
        const lines = output.trim().split("\n");
        for (const line of lines) {
            const parts = line.split(":");
            if (parts.length >= 2) {
                const deviceType = parts[1];
                let shouldInclude = (filterType === "both")
                    || (filterType === root.deviceTypeWifi && deviceType === root.deviceTypeWifi)
                    || (filterType === root.deviceTypeEthernet && deviceType === root.deviceTypeEthernet);
                if (shouldInclude) {
                    interfaces.push({ device: parts[0] || "", type: parts[1] || "", state: parts[2] || "", connection: parts[3] || "" });
                }
            }
        }
        return interfaces;
    }

    function isConnectedState(state: string): bool {
        if (!state || state.length === 0) return false;
        return state === "100 (connected)" || state === "connected" || state.startsWith("connected");
    }

    function isConnectingState(state: string): bool {
        return !!state && state.startsWith("connecting");
    }

    function executeCommand(args: list<string>, callback: var): void {
        if (callback && typeof callback === "function")
            callback({ success: false, output: "", error: "executeCommand removed - use NmQt", exitCode: -1 });
    }

    function executeShellCommand(cmd: list<string>, env: var, callback: var): void {
        if (callback && typeof callback === "function")
            callback({ success: false, output: "", error: "executeShellCommand removed - use NmQt", exitCode: -1 });
    }

    function connectEthernet(connectionName: string, interfaceName: string, callback: var): void {
        NmQt.connectEthernet(connectionName, interfaceName, callback);
    }

    function disconnectEthernet(connectionName: string, callback: var): void {
        NmQt.disconnectEthernet(connectionName, callback);
    }

    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        let immediateResult = null;
        const wrappedCallback = result => {
            immediateResult = result;
            if (result && !result.success) {
                root.pendingConnection = null;
                connectionCheckTimer.stop();
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
                root.connectionFailed(ssid);
                if (callback && typeof callback === "function") callback(result);
            } else if (result && result.needsPassword) {
                root.pendingConnection = null;
                connectionCheckTimer.stop();
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
                if (callback && typeof callback === "function") callback(result);
            }
            // If success is true and needsPassword is false, do not stop timers.
            // Wait for active connection state to update.
        };
        NmQt.connectToNetworkWithPasswordCheck(ssid, isSecure, wrappedCallback, bssid);
        if (!immediateResult) {
            root.pendingConnection = { ssid: ssid, bssid: bssid || "", callback: callback };
            connectionCheckTimer.start();
            immediateCheckTimer.checkCount = 0;
            immediateCheckTimer.start();
        }
    }

    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        let immediateResult = null;
        const wrappedCallback = result => {
            immediateResult = result;
            if (result && !result.success) {
                root.pendingConnection = null;
                connectionCheckTimer.stop();
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
                root.connectionFailed(ssid);
                if (callback && typeof callback === "function") callback(result);
            }
            // If success is true, do not stop timers.
            // Wait for active connection state to update.
        };
        NmQt.connectToNetwork(ssid, password, bssid, wrappedCallback);
        if (!immediateResult) {
            root.pendingConnection = { ssid: ssid, bssid: bssid || "", callback: callback };
            connectionCheckTimer.start();
            immediateCheckTimer.checkCount = 0;
            immediateCheckTimer.start();
        }
    }

    function connectWireless(ssid: string, password: string, bssid: string, callback: var, retryCount: int): void {
        connectToNetwork(ssid, password, bssid, callback);
    }

    function createConnectionWithPassword(ssid: string, bssidUpper: string, password: string, callback: var): void {
        NmQt.connectToNetwork(ssid, password, bssidUpper, callback);
    }

    function checkAndDeleteConnection(ssid: string, callback: var): void {
        NmQt.forgetNetwork(ssid, callback);
    }

    function activateConnection(connectionName: string, callback: var): void {
        NmQt.connectEthernet(connectionName, "", callback);
    }

    function loadSavedConnections(callback: var): void { NmQt.loadSavedConnections(callback); }
    function loadVpnConnections(callback: var): void { NmQt.loadVpnConnections(callback); }

    function parseConnectionList(output: string, callback: var): void {
        if (callback && typeof callback === "function") callback(root.savedConnectionSsids);
    }

    function isVpnConnectionType(type: string): bool {
        const normalized = (type || "").toLowerCase().trim();
        return normalized === root.connectionTypeVpn || normalized === root.connectionTypeWireGuard;
    }

    function connectVpn(connectionName: string, callback: var): void { NmQt.connectVpn(connectionName, callback); }
    function disconnectVpn(connectionName: string, callback: var): void { NmQt.disconnectVpn(connectionName, callback); }

    function queryNextSsid(callback: var): void {
        root.wifiConnectionQueue = [];
        root.currentSsidQueryIndex = 0;
        if (callback && typeof callback === "function") callback(root.savedConnectionSsids);
    }

    function hasSavedProfile(ssid: string): bool { return NmQt.hasSavedProfile(ssid); }
    function forgetNetwork(ssid: string, callback: var): void { NmQt.forgetNetwork(ssid, callback); }

    function enableHotspot(ssid: string, password: string, callback: var): void {
        NmQt.enableHotspot(ssid, password, callback);
    }

    function disableHotspot(callback: var): void {
        NmQt.disableHotspot(callback);
    }

    /// Start or stop the hotspot from a one-tap toggle, using the name and
    /// password kept in the settings. A hotspot that has never been set up is
    /// not started: one tap should not share an open network, so the toggle
    /// points at the settings page instead. The failure keeps its toast here,
    /// where both the utilities tile and the bar popout get it.
    function toggleHotspot(): void {
        if (NmQt.hotspotEnabled) {
            NmQt.disableHotspot(reportHotspotFailure);
            return;
        }

        if (GlobalConfig.services.hotspotSsid.length === 0 && GlobalConfig.services.hotspotPassword.length === 0) {
            Toaster.toast(qsTr("Hotspot"), qsTr("Give it a name and a password in Settings > Network > Hotspot"), "wifi_tethering");
            return;
        }

        NmQt.enableHotspot(GlobalConfig.services.hotspotSsid, GlobalConfig.services.hotspotPassword, reportHotspotFailure);
    }

    function reportHotspotFailure(result: var): void {
        if (!result || result.success)
            return;
        Toaster.toast(qsTr("Hotspot"), result.error || qsTr("The hotspot could not be started"), "wifi_tethering");
    }

    function disconnect(interfaceName: string, callback: var): void {
        NmQt.disconnectFromNetwork();
        if (callback && typeof callback === "function") callback("Disconnected");
    }

    function disconnectFromNetwork(): void { NmQt.disconnectFromNetwork(); }

    function refreshStatus(callback: var): void {
        if (callback && typeof callback === "function") {
            callback({ connected: root.isConnected, interface: root.activeInterface, connection: root.activeConnection });
        }
    }

    function bringInterfaceUp(interfaceName: string, callback: var): void {
        NmQt.connectEthernet("", interfaceName, callback);
    }

    function bringInterfaceDown(interfaceName: string, callback: var): void {
        if (callback && typeof callback === "function")
            callback({ success: false, output: "", error: "Not implemented", exitCode: -1 });
    }

    function scanWirelessNetworks(interfaceName: string, callback: var): void {
        NmQt.rescanWifi();
        if (callback && typeof callback === "function")
            callback({ success: true, output: "Scan triggered", error: "", exitCode: 0 });
    }

    function rescanWifi(): void { NmQt.rescanWifi(); }
    function enableWifi(enabled: bool, callback: var): void { NmQt.enableWifi(enabled, callback); }
    function toggleWifi(callback: var): void { NmQt.toggleWifi(callback); }

    function getWifiStatus(callback: var): void {
        if (callback && typeof callback === "function") callback(NmQt.wifiEnabled);
    }

    function getNetworks(callback: var): void { NmQt.getNetworks(callback); }
    function getWirelessSSIDs(interfaceName: string, callback: var): void { NmQt.getNetworks(callback); }

    function handlePasswordRequired(proc: var, error: string, output: string, exitCode: int): bool {
        return false; // NmQt handles password detection internally
    }

    function checkPendingConnection(): void { } // timer handles this

    function cidrToSubnetMask(cidr: string): string {
        const cidrNum = parseInt(cidr, 10);
        if (isNaN(cidrNum) || cidrNum < 0 || cidrNum > 32) return "";
        const mask = (0xffffffff << (32 - cidrNum)) >>> 0;
        return `${(mask >>> 24) & 0xff}.${(mask >>> 16) & 0xff}.${(mask >>> 8) & 0xff}.${mask & 0xff}`;
    }

    function getWirelessDeviceDetails(interfaceName: string, callback: var): void {
        NmQt.getWirelessDeviceDetails(interfaceName, callback);
    }

    function getEthernetDeviceDetails(interfaceName: string, callback: var): void {
        NmQt.getEthernetDeviceDetails(interfaceName, callback);
    }

    function refreshOnConnectionChange(): void {
        emit: monitorEvent();
    }

    // =========================================================================
    //  Upstream-sync parity surface (network page rewrite)
    // =========================================================================

    function findNetwork(ssid: string): var {
        return networks.find(n => n.ssid === ssid) ?? null;
    }

    function securityLabel(keyMgmt: string): string {
        switch ((keyMgmt || "").trim().toLowerCase()) {
        case "":
        case "none":
            return qsTr("Open");
        case "sae":
            return "WPA3";
        case "wpa-psk":
            return "WPA2";
        case "wpa-eap":
        case "wpa-eap-suite-b-192":
            return qsTr("Enterprise");
        case "owe":
            return qsTr("Enhanced Open");
        case "ieee8021x":
            return "802.1X";
        default:
            return keyMgmt.trim();
        }
    }

    function savedSecurityFor(ssid: string): string {
        if (!ssid || ssid.length === 0) return "";
        return (root.savedConnectionSecurity || {})[ssid.toLowerCase().trim()] || "";
    }

    function getEthernetInterfaces(callback: var): void {
        const names = root.__ethernetDevices.map(d => d.iface);
        if (callback && typeof callback === "function") callback(names);
    }

    function getEthernetSpeed(interfaceName: string): void {
        root.ethernetSpeed = NmQt.ethernetSpeed(interfaceName);
    }

    function getEthernetDataUsage(interfaceName: string, callback: var): void {
        root.ethernetDataUsage = NmQt.ethernetDataUsage(interfaceName);
        if (callback && typeof callback === "function") callback(root.ethernetDataUsage);
    }

    function getIpv4Config(connectionName: string, callback: var): void {
        NmQt.getIpv4Config(connectionName, callback);
    }

    function setIpv4Config(connectionName: string, config: var, callback: var): void {
        NmQt.setIpv4Config(connectionName, config, callback);
    }

    function setAutoconnect(connectionName: string, enabled: bool, callback: var): void {
        NmQt.setAutoconnect(connectionName, enabled, callback);
    }

    function addHiddenNetwork(ssid: string, password: string, security: string, hidden: bool, callback: var): void {
        NmQt.addHiddenNetwork(ssid, password, security, hidden, callback);
    }

    function rebuildEthernetDevices(): void {
        const rawList = NmQt.ethernetDevices;
        const newList = [];

        for (let i = 0; i < rawList.length; i++) {
            const existing = __ethernetDevices[i];
            if (existing) {
                existing.lastIpcObject = rawList[i];
                newList.push(existing);
            } else {
                newList.push(ethDevComp.createObject(root, { lastIpcObject: rawList[i] }));
            }
        }

        for (let j = newList.length; j < __ethernetDevices.length; j++) {
            __ethernetDevices[j].destroy();
        }

        root.__ethernetDevices = newList;
    }

    // NmQt populates its own network cache in its C++ constructor, before this
    // Connections block exists to observe networksChanged — without this, the
    // adapter's list stays empty until NetworkManager emits another change.
    Component.onCompleted: {
        rebuildNetworkList();
        rebuildEthernetDevices();
        rebuildActive();
    }



    Connections {
        function onNetworksChanged(): void {
            rebuildNetworkList();
            rebuildActive();
        }
        function onEthernetDevicesChanged(): void {
            rebuildEthernetDevices();
        }
        function onWifiEnabledChanged(): void {
            root.wifiEnabled = NmQt.wifiEnabled;
        }
        function onVpnPendingConnectionChanged(): void {
            root.vpnPendingConnection = NmQt.vpnPendingConnection;
        }
        function onSavedConnectionsChanged(): void {
            root.savedConnections = NmQt.savedConnections;
        }
        function onSavedConnectionSsidsChanged(): void {
            root.savedConnectionSsids = NmQt.savedConnectionSsids;
        }
        function onConnectionFailed(ssid: string): void {
            root.connectionFailed(ssid);
        }
        function onActiveChanged(): void {
            rebuildNetworkList();
            rebuildActive();
        }

        target: NmQt
    }

    Timer {
        id: connectionCheckTimer

        interval: 20000

        onTriggered: {
            if (root.pendingConnection) {
                const connected = root.active && root.active.ssid && root.active.ssid.toLowerCase().trim() === root.pendingConnection.ssid.toLowerCase().trim();
                if (!connected) {
                    const pending = root.pendingConnection;
                    const failedSsid = pending.ssid;
                    root.pendingConnection = null;
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    root.connectionFailed(failedSsid);
                    if (pending.callback && typeof pending.callback === "function") {
                        pending.callback({
                            success: false, output: "", error: "Connection timeout",
                            exitCode: -1, needsPassword: false
                        });
                    }
                } else {
                    const pending = root.pendingConnection;
                    root.pendingConnection = null;
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    root.connectionSuccessful(pending.ssid);
                    if (pending.callback && typeof pending.callback === "function") {
                        pending.callback({
                            success: true, output: "Connected", error: "", exitCode: 0
                        });
                    }
                }
            }
        }
    }

    Timer {
        id: immediateCheckTimer

        property int checkCount: 0

        interval: 500
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (root.pendingConnection) {
                checkCount++;
                const connected = root.active && root.active.ssid && root.active.ssid.toLowerCase().trim() === root.pendingConnection.ssid.toLowerCase().trim();
                if (connected) {
                    connectionCheckTimer.stop();
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    const pending = root.pendingConnection;
                    root.pendingConnection = null;
                    root.connectionSuccessful(pending.ssid);
                    if (pending.callback && typeof pending.callback === "function") {
                        pending.callback({
                            success: true, output: "Connected", error: "", exitCode: 0
                        });
                    }
                } else if (checkCount >= 6) {
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                }
            } else {
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
            }
        }
    }

    // =========================================================================
    //  Components
    // =========================================================================

    Component {
        id: commandProc

        QtObject {}
    }

    Component {
        id: apComp

        AccessPoint {}
    }

    Component {
        id: ethDevComp

        EthernetDevice {}
    }

    component AccessPoint: QtObject {
        required property var lastIpcObject

        readonly property string ssid: lastIpcObject.ssid ?? ""
        readonly property string bssid: lastIpcObject.bssid ?? ""
        readonly property int strength: lastIpcObject.strength ?? 0
        readonly property int frequency: lastIpcObject.frequency ?? 0
        readonly property bool active: lastIpcObject.active ?? false
        readonly property string security: lastIpcObject.security ?? ""
        readonly property bool isSecure: (lastIpcObject.security ?? "").length > 0
    }

    component EthernetDevice: QtObject {
        required property var lastIpcObject

        readonly property string iface: lastIpcObject.interface ?? ""
        readonly property string type: lastIpcObject.type ?? ""
        readonly property string state: deviceStateName(lastIpcObject.state)
        readonly property string connection: lastIpcObject.connection ?? ""
        readonly property bool connected: lastIpcObject.connected ?? false
        readonly property string ipAddress: lastIpcObject.ipAddress ?? ""
        readonly property string gateway: lastIpcObject.gateway ?? ""
        readonly property var dns: lastIpcObject.dns ?? []
        readonly property string subnet: lastIpcObject.subnet ?? ""
        readonly property string macAddress: lastIpcObject.macAddress ?? ""
        readonly property string speed: lastIpcObject.speed ?? ""

        function deviceStateName(state: var): string {
            const names = ["unknown", "unmanaged", "unavailable", "disconnected", "prepare", "config", "need-auth", "ip-config", "ip-check", "secondaries", "activated", "deactivating", "failed"];
            if (typeof state === "number" && state >= 0 && state < names.length)
                return names[state];
            return state ?? "unknown";
        }
    }
}
