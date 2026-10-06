pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services

/// Adapter over the C++ NmQt (NetworkManagerQt/D-Bus) singleton.
/// Forwards the QML-facing network API to the D-Bus backend and keeps the
/// AccessPoint/SavedProfile/EthernetDevice object models rebuilt in sync.
Singleton {
    id: root


    readonly property bool isConnected: NmQt.isConnected
    property bool wifiEnabled: NmQt.wifiEnabled
    readonly property bool scanning: NmQt.scanning
    readonly property string connectingSsid: NmQt.connectingSsid

    readonly property var wirelessDeviceDetails: NmQt.wirelessDeviceDetails
    readonly property var ethernetDeviceDetails: NmQt.ethernetDeviceDetails

    property list<EthernetDevice> __ethernetDevices: []
    readonly property list<EthernetDevice> ethernetDevices: __ethernetDevices
    readonly property EthernetDevice activeEthernet: __ethernetDevices.find(d => d.connected) ?? null
    readonly property bool hasAvailableEthernet: __ethernetDevices.some(d => d.state !== "unavailable")
    property string ethernetSpeed: ""
    property string ethernetDataUsage: ""

    readonly property var vpnConnections: NmQt.vpnConnections
    readonly property var activeVpn: NmQt.activeVpn
    property string vpnPendingConnection: NmQt.vpnPendingConnection

    /// Wi-Fi access point. Exposed as the service itself rather than as three
    /// copied properties: supported, enabled, the name and whether an enable is
    /// in flight all change together, and splitting them across an adapter is
    /// what makes a switch have to guess which of the three is authoritative.
    readonly property HotspotController hotspot: NmQt.hotspot

    property list<string> savedConnections: NmQt.savedConnections
    property list<string> savedConnectionSsids: NmQt.savedConnectionSsids
    property list<SavedProfile> __savedConnectionProfiles: []
    readonly property list<SavedProfile> savedConnectionProfiles: __savedConnectionProfiles

    readonly property list<AccessPoint> networks: __networks
    property list<AccessPoint> __networks: []

    property AccessPoint active: null

    property var pendingConnection: null

    readonly property alias connectionCheckTimer: connectionCheckTimer
    readonly property alias immediateCheckTimer: immediateCheckTimer



    signal connectionSuccessful(string ssid)
    signal connectionFailed(string ssid)

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
        };
        NmQt.connectToNetwork(ssid, password, bssid, wrappedCallback);
        if (!immediateResult) {
            root.pendingConnection = { ssid: ssid, bssid: bssid || "", callback: callback };
            connectionCheckTimer.start();
            immediateCheckTimer.checkCount = 0;
            immediateCheckTimer.start();
        }
    }

    function connectToNetworkByUuid(uuid: string, callback: var): void { NmQt.connectToNetworkByUuid(uuid, callback); }

    function loadSavedConnections(callback: var): void { NmQt.loadSavedConnections(callback); }

    function connectVpn(connectionName: string, callback: var): void { NmQt.connectVpn(connectionName, callback); }
    function disconnectVpn(connectionName: string, callback: var): void { NmQt.disconnectVpn(connectionName, callback); }

    function hasSavedProfile(ssid: string): bool { return NmQt.hasSavedProfile(ssid); }
    function forgetNetwork(ssid: string, callback: var): void { NmQt.forgetNetwork(ssid, callback); }
    function forgetNetworkByUuid(uuid: string, callback: var): void { NmQt.forgetNetworkByUuid(uuid, callback); }

    function disconnectFromNetwork(): void { NmQt.disconnectFromNetwork(); }

    function rescanWifi(): void { NmQt.rescanWifi(); }
    function enableWifi(enabled: bool, callback: var): void { NmQt.enableWifi(enabled, callback); }
    function toggleWifi(callback: var): void { NmQt.toggleWifi(callback); }

    function getWirelessDeviceDetails(interfaceName: string, callback: var): void {
        NmQt.getWirelessDeviceDetails(interfaceName, callback);
    }

    function getEthernetDeviceDetails(interfaceName: string, callback: var): void {
        NmQt.getEthernetDeviceDetails(interfaceName, callback);
    }

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

    function getIpv4Config(connectionId: string, callback: var): void {
        NmQt.getIpv4Config(connectionId, callback);
    }

    function setIpv4Config(connectionId: string, config: var, callback: var): void {
        NmQt.setIpv4Config(connectionId, config, callback);
    }

    function setAutoconnect(connectionId: string, enabled: bool, callback: var): void {
        NmQt.setAutoconnect(connectionId, enabled, callback);
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

    function rebuildSavedProfiles(): void {
        const rawList = NmQt.savedConnectionProfiles;
        const ssidCounts = {};

        for (const raw of rawList)
            ssidCounts[raw.ssid] = (ssidCounts[raw.ssid] || 0) + 1;

        const oldByUuid = new Map();
        for (const profile of __savedConnectionProfiles) {
            if (profile && profile.uuid)
                oldByUuid.set(profile.uuid, profile);
        }

        const newList = [];
        for (const raw of rawList) {
            const duplicate = ssidCounts[raw.ssid] > 1;
            const existing = oldByUuid.get(raw.uuid);
            if (existing) {
                existing.lastIpcObject = raw;
                existing.duplicate = duplicate;
                newList.push(existing);
                oldByUuid.delete(raw.uuid);
            } else {
                newList.push(savedProfileComp.createObject(root, { lastIpcObject: raw, duplicate: duplicate }));
            }
        }

        oldByUuid.forEach(profile => profile.destroy());

        root.__savedConnectionProfiles = newList;
    }

    Component.onCompleted: {
        rebuildNetworkList();
        rebuildEthernetDevices();
        rebuildSavedProfiles();
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
        function onSavedConnectionProfilesChanged(): void {
            rebuildSavedProfiles();
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


    Component {
        id: apComp

        AccessPoint {}
    }

    Component {
        id: ethDevComp

        EthernetDevice {}
    }

    Component {
        id: savedProfileComp

        SavedProfile {}
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

    component SavedProfile: QtObject {
        required property var lastIpcObject

        property bool duplicate: false

        readonly property string ssid: lastIpcObject.ssid ?? ""
        readonly property string id: lastIpcObject.id ?? ""
        readonly property string uuid: lastIpcObject.uuid ?? ""
        readonly property string path: lastIpcObject.path ?? ""
        readonly property string security: lastIpcObject.security ?? ""
        readonly property bool active: lastIpcObject.active ?? false

        readonly property string disambiguator: id && id !== ssid ? id : uuid.slice(-4).toUpperCase()
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
