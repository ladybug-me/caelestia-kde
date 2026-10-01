pragma Singleton

import QtQuick
import qs.services

QtObject {
    id: root

    property var passwordNetwork: null

    function disconnectFirstIfNeeded(isTarget: bool, connect: var): void {
        if (Nmcli.active && !isTarget) {
            Nmcli.disconnectFromNetwork();
            Qt.callLater(connect);
        } else {
            connect();
        }
    }

    function handleConnect(network, session, onPasswordNeeded): void {
        if (!network) {
            return;
        }

        root.disconnectFirstIfNeeded(Nmcli.active?.ssid === network.ssid, () => {
            root.connectToNetwork(network, session, onPasswordNeeded);
        });
    }

    function connectToSavedProfile(uuid, onResult): void {
        if (!uuid) {
            return;
        }

        const isTarget = !!Nmcli.savedConnectionProfiles.find(p => p.uuid === uuid)?.active;
        root.disconnectFirstIfNeeded(isTarget, () => {
            Nmcli.connectToNetworkByUuid(uuid, onResult || null);
        });
    }

    function connectToNetwork(network, session, onPasswordNeeded): void {
        if (!network) {
            return;
        }

        if (network.isSecure) {
            const hasSavedProfile = Nmcli.hasSavedProfile(network.ssid);

            if (hasSavedProfile) {
                Nmcli.connectToNetwork(network.ssid, "", network.bssid, null);
            } else {
                Nmcli.connectToNetworkWithPasswordCheck(network.ssid, network.isSecure, result => {
                    if (result.needsPassword) {
                        if (Nmcli.pendingConnection) {
                            Nmcli.connectionCheckTimer.stop();
                            Nmcli.immediateCheckTimer.stop();
                            Nmcli.immediateCheckTimer.checkCount = 0;
                            Nmcli.pendingConnection = null;
                        }

                        if (session && session.network) {
                            session.network.showPasswordDialog = true;
                            session.network.pendingNetwork = network;
                        } else if (onPasswordNeeded) {
                            onPasswordNeeded(network);
                        }
                    }
                }, network.bssid);
            }
        } else {
            Nmcli.connectToNetwork(network.ssid, "", network.bssid, null);
        }
    }

    function connectWithPassword(network, password, onResult): void {
        if (!network) {
            return;
        }

        Nmcli.connectToNetwork(network.ssid, password || "", network.bssid || "", onResult || null);
    }
}
