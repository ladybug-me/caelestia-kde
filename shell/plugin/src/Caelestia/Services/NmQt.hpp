// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <qqmlintegration.h>

#include <NetworkManagerQt/ConnectionSettings>
#include <NetworkManagerQt/Device>
#include <NetworkManagerQt/WirelessDevice>
#include <QDateTime>
#include <QJSValue>
#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace caelestia::services {

/**
 * NetworkManager Qt / D-Bus singleton replacing the nmcli-shelling-out
 * approach of the old Nmcli.qml.
 *
 * All properties reactively update via NetworkManagerQt signals — no
 * command-line parsing, no locale assumptions, no repeated process spawning.
 */
class NmQt : public QObject {
    Q_OBJECT

    // -- General state --
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY isConnectedChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(QString connectingSsid READ connectingSsid NOTIFY connectingSsidChanged)

    // -- WiFi networks --
    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)
    Q_PROPERTY(QVariantMap active READ active NOTIFY activeChanged)

    // -- Saved connections --
    Q_PROPERTY(QStringList savedConnections READ savedConnections NOTIFY savedConnectionsChanged)
    Q_PROPERTY(QStringList savedConnectionSsids READ savedConnectionSsids NOTIFY savedConnectionSsidsChanged)

    // -- Ethernet --
    Q_PROPERTY(QVariantMap activeEthernet READ activeEthernet NOTIFY activeEthernetChanged)
    Q_PROPERTY(QVariantList ethernetDevices READ ethernetDevices NOTIFY ethernetDevicesChanged)

    // -- VPN --
    Q_PROPERTY(QVariantList vpnConnections READ vpnConnections NOTIFY vpnConnectionsChanged)
    Q_PROPERTY(QVariantMap activeVpn READ activeVpn NOTIFY activeVpnChanged)
    Q_PROPERTY(QString vpnPendingConnection READ vpnPendingConnection NOTIFY vpnPendingConnectionChanged)

    // -- Device details --
    Q_PROPERTY(QVariantMap wirelessDeviceDetails READ wirelessDeviceDetails NOTIFY wirelessDeviceDetailsChanged)
    Q_PROPERTY(QVariantMap ethernetDeviceDetails READ ethernetDeviceDetails NOTIFY ethernetDeviceDetailsChanged)

    // -- Saved connection security (ssid -> key-mgmt, e.g. "wpa-psk") --
    Q_PROPERTY(QVariantMap savedConnectionSecurity READ savedConnectionSecurity NOTIFY savedConnectionSecurityChanged)

    // -- Wi-Fi hotspot --
    Q_PROPERTY(bool hotspotSupported READ hotspotSupported NOTIFY hotspotSupportedChanged)
    Q_PROPERTY(bool hotspotEnabled READ hotspotEnabled NOTIFY hotspotEnabledChanged)
    Q_PROPERTY(QString hotspotSsid READ hotspotSsid NOTIFY hotspotSsidChanged)

    QML_ELEMENT
    QML_SINGLETON

public:
    explicit NmQt(QObject* parent = nullptr);
    ~NmQt() override;

    // -- Property accessors --
    bool isConnected() const;
    bool wifiEnabled() const;
    bool scanning() const;
    QString connectingSsid() const;

    QVariantList networks() const;
    QVariantMap active() const;

    QStringList savedConnections() const;
    QStringList savedConnectionSsids() const;

    QVariantMap activeEthernet() const;
    QVariantList ethernetDevices() const;

    QVariantList vpnConnections() const;
    QVariantMap activeVpn() const;
    QString vpnPendingConnection() const;

    QVariantMap wirelessDeviceDetails() const;
    QVariantMap ethernetDeviceDetails() const;
    QVariantMap savedConnectionSecurity() const;

    bool hotspotSupported() const;
    bool hotspotEnabled() const;
    QString hotspotSsid() const;

    // -- QML-invokable actions --

    /// Refresh the WiFi network list. Optionally invoke callback(list).
    Q_INVOKABLE void getNetworks(QJSValue callback = {});

    /// Connect to a WiFi network.
    Q_INVOKABLE void connectToNetwork(
        const QString& ssid, const QString& password, const QString& bssid, QJSValue callback = {});

    /// Try connecting with a saved password first; fall back to asking.
    Q_INVOKABLE void connectToNetworkWithPasswordCheck(
        const QString& ssid, bool isSecure, QJSValue callback = {}, const QString& bssid = {});

    /// Disconnect from the currently active WiFi network.
    Q_INVOKABLE void disconnectFromNetwork();

    /// Remove a saved connection profile by SSID.
    Q_INVOKABLE void forgetNetwork(const QString& ssid, QJSValue callback = {});

    /// Enable or disable WiFi radio.
    Q_INVOKABLE void enableWifi(bool enabled, QJSValue callback = {});

    /// Toggle WiFi radio state.
    Q_INVOKABLE void toggleWifi(QJSValue callback = {});

    /// Trigger a WiFi rescan.
    Q_INVOKABLE void rescanWifi();

    /// Connect an Ethernet device.
    Q_INVOKABLE void connectEthernet(
        const QString& connectionName, const QString& interfaceName, QJSValue callback = {});

    /// Disconnect an Ethernet device.
    Q_INVOKABLE void disconnectEthernet(const QString& connectionName, QJSValue callback = {});

    /// Connect a VPN connection.
    Q_INVOKABLE void connectVpn(const QString& connectionName, QJSValue callback = {});

    /// Disconnect a VPN connection.
    Q_INVOKABLE void disconnectVpn(const QString& connectionName, QJSValue callback = {});

    /// Reload the saved-connections lists.
    Q_INVOKABLE void loadSavedConnections(QJSValue callback = {});

    /// Reload the VPN connections list.
    Q_INVOKABLE void loadVpnConnections(QJSValue callback = {});

    /// Check whether a saved profile exists for the given SSID.
    Q_INVOKABLE bool hasSavedProfile(const QString& ssid) const;

    /// Retrieve detailed info for a wireless device.
    Q_INVOKABLE void getWirelessDeviceDetails(const QString& interfaceName, QJSValue callback = {});

    /// Retrieve detailed info for an ethernet device.
    Q_INVOKABLE void getEthernetDeviceDetails(const QString& interfaceName, QJSValue callback = {});

    /// Read IPv4 settings of a saved connection (matched by name or SSID).
    Q_INVOKABLE void getIpv4Config(const QString& connectionName, QJSValue callback = {});

    /// Write IPv4 settings to a saved connection.
    Q_INVOKABLE void setIpv4Config(const QString& connectionName, const QVariantMap& config, QJSValue callback = {});

    /// Toggle autoconnect on a saved connection.
    Q_INVOKABLE void setAutoconnect(const QString& connectionName, bool enabled, QJSValue callback = {});

    /// Create and activate a hidden WiFi network.
    Q_INVOKABLE void addHiddenNetwork(
        const QString& ssid, const QString& password, const QString& security, bool hidden, QJSValue callback = {});

    /// Turn the Wi-Fi hotspot on: create or update the shell's access point
    /// profile and activate it. An empty password shares an open network.
    Q_INVOKABLE void enableHotspot(const QString& ssid, const QString& password, QJSValue callback = {});

    /// Turn the Wi-Fi hotspot off, leaving its profile saved.
    Q_INVOKABLE void disableHotspot(QJSValue callback = {});

    /// Formatted link speed (e.g. "1000 Mb/s"), empty if unknown.
    Q_INVOKABLE QString ethernetSpeed(const QString& interfaceName) const;

    /// Formatted cumulative RX+TX bytes, empty if unknown.
    Q_INVOKABLE QString ethernetDataUsage(const QString& interfaceName) const;

signals:
    void isConnectedChanged();
    void wifiEnabledChanged();
    void scanningChanged();
    void connectingSsidChanged();

    void networksChanged();
    void activeChanged();

    void savedConnectionsChanged();
    void savedConnectionSsidsChanged();

    void activeEthernetChanged();
    void ethernetDevicesChanged();

    void vpnConnectionsChanged();
    void activeVpnChanged();

    void vpnPendingConnectionChanged();

    void wirelessDeviceDetailsChanged();
    void ethernetDeviceDetailsChanged();
    void savedConnectionSecurityChanged();

    void hotspotSupportedChanged();
    void hotspotEnabledChanged();
    void hotspotSsidChanged();

    /// Emitted when a connection attempt fails outright.
    void connectionFailed(const QString& ssid);

private slots:
    // -- NetworkManager signal handlers --
    void onWirelessEnabledChanged(bool enabled);
    void onWirelessHardwareEnabledChanged(bool enabled);
    void onNetworkDevicesChanged();
    void onActiveConnectionsChanged();
    void onConnectionsChanged();
    void onDeviceStateChanged(NetworkManager::Device::State newState, NetworkManager::Device::State oldState,
        NetworkManager::Device::StateChangeReason reason);
    void onScanFinished(const QDateTime& dateTime);
    void onAccessPointAppeared(const QString& apPath);
    void onAccessPointDisappeared(const QString& apPath);

    /// Re-sync all state once NetworkManagerQt/NM itself is fully settled.
    void onNetworkManagerReady();

private:
    // -- Helpers --
    void refreshNetworks();
    void refreshDevices();
    void refreshEthernetDevices();
    void refreshSavedConnections();
    void refreshVpnConnections();
    void refreshWirelessDeviceDetails(const QString& interfaceName = {});
    void refreshEthernetDeviceDetails(const QString& interfaceName = {});
    void refreshHotspot();

    /// The wireless device the hotspot can run on: the first one that advertises
    /// access point support, else null when no device can run one.
    static NetworkManager::WirelessDevice::Ptr hotspotDevice();

    /// The access point that is already up.
    struct RunningHotspot {
        /// Object path of the active connection, empty when the hotspot is off.
        QString path;
        /// The name it broadcasts, empty when the hotspot is off.
        QString ssid;
    };

    static RunningHotspot runningHotspot();

    /// Build the access point profile the shell saves and activates.
    static NMVariantMapMap buildHotspotSettings(const QString& ssid, const QString& password, const QString& uuid);

    /// Build a QVariantMap for a single access point.
    static QVariantMap buildApMap(
        const QString& ssid, const QString& bssid, int strength, int frequency, bool active, const QString& security);

    /// Build a standardised result object for a JS callback.
    static QJSValue buildResult(QJSEngine* engine, bool success, const QString& output = {}, const QString& error = {},
        int exitCode = 0, bool needsPassword = false);

    void invokeCallback(QJSValue callback, bool success, const QString& output = {}, const QString& error = {},
        int exitCode = 0, bool needsPassword = false);

    // -- State --
    QVariantList m_networks;
    QVariantMap m_active;
    QStringList m_savedConnections;
    QStringList m_savedConnectionSsids;
    QVariantMap m_activeEthernet;
    QVariantList m_ethernetDevices;
    QVariantList m_vpnConnections;
    QVariantMap m_activeVpn;
    QString m_vpnPendingConnection;
    QVariantMap m_wirelessDeviceDetails;
    QVariantMap m_ethernetDeviceDetails;
    QVariantMap m_savedConnectionSecurity;
    QString m_connectingSsid;
    bool m_wifiEnabled = true;
    bool m_scanning = false;
    bool m_initialised = false;

    // Hotspot state. The ssid is the one the active access point broadcasts, so
    // it follows a hotspot started elsewhere instead of only the shell's own.
    bool m_hotspotSupported = false;
    bool m_hotspotEnabled = false;
    QString m_hotspotSsid;

    // Track the wireless device UNI for scan/connection operations.
    QString m_wirelessDeviceUni;
    QString m_ethernetDeviceUni;
};

} // namespace caelestia::services
