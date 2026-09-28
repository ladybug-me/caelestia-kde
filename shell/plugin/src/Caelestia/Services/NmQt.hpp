// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <qqmlintegration.h>

#include <NetworkManagerQt/Connection>
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

    Q_PROPERTY(bool isConnected READ isConnected NOTIFY isConnectedChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(QString connectingSsid READ connectingSsid NOTIFY connectingSsidChanged)

    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)
    Q_PROPERTY(QVariantMap active READ active NOTIFY activeChanged)

    Q_PROPERTY(QStringList savedConnections READ savedConnections NOTIFY savedConnectionsChanged)
    Q_PROPERTY(QStringList savedConnectionSsids READ savedConnectionSsids NOTIFY savedConnectionSsidsChanged)
    Q_PROPERTY(QVariantList savedConnectionProfiles READ savedConnectionProfiles NOTIFY savedConnectionProfilesChanged)

    Q_PROPERTY(QVariantMap activeEthernet READ activeEthernet NOTIFY activeEthernetChanged)
    Q_PROPERTY(QVariantList ethernetDevices READ ethernetDevices NOTIFY ethernetDevicesChanged)

    Q_PROPERTY(QVariantList vpnConnections READ vpnConnections NOTIFY vpnConnectionsChanged)
    Q_PROPERTY(QVariantMap activeVpn READ activeVpn NOTIFY activeVpnChanged)
    Q_PROPERTY(QString vpnPendingConnection READ vpnPendingConnection NOTIFY vpnPendingConnectionChanged)

    Q_PROPERTY(QVariantMap wirelessDeviceDetails READ wirelessDeviceDetails NOTIFY wirelessDeviceDetailsChanged)
    Q_PROPERTY(QVariantMap ethernetDeviceDetails READ ethernetDeviceDetails NOTIFY ethernetDeviceDetailsChanged)

    QML_ELEMENT
    QML_SINGLETON

public:
    explicit NmQt(QObject* parent = nullptr);
    ~NmQt() override;

    bool isConnected() const;
    bool wifiEnabled() const;
    bool scanning() const;
    QString connectingSsid() const;

    QVariantList networks() const;
    QVariantMap active() const;

    QStringList savedConnections() const;
    QStringList savedConnectionSsids() const;
    QVariantList savedConnectionProfiles() const;

    QVariantMap activeEthernet() const;
    QVariantList ethernetDevices() const;

    QVariantList vpnConnections() const;
    QVariantMap activeVpn() const;
    QString vpnPendingConnection() const;

    QVariantMap wirelessDeviceDetails() const;
    QVariantMap ethernetDeviceDetails() const;

    Q_INVOKABLE void getNetworks(QJSValue callback = {});

    Q_INVOKABLE void connectToNetwork(
        const QString& ssid, const QString& password, const QString& bssid, QJSValue callback = {});

    Q_INVOKABLE void connectToNetworkWithPasswordCheck(
        const QString& ssid, bool isSecure, QJSValue callback = {}, const QString& bssid = {});

    Q_INVOKABLE void disconnectFromNetwork();

    Q_INVOKABLE void forgetNetwork(const QString& ssid, QJSValue callback = {});

    Q_INVOKABLE void forgetNetworkByUuid(const QString& uuid, QJSValue callback = {});

    Q_INVOKABLE void connectToNetworkByUuid(const QString& uuid, QJSValue callback = {});

    Q_INVOKABLE void enableWifi(bool enabled, QJSValue callback = {});

    Q_INVOKABLE void toggleWifi(QJSValue callback = {});

    Q_INVOKABLE void rescanWifi();

    Q_INVOKABLE void connectEthernet(
        const QString& connectionName, const QString& interfaceName, QJSValue callback = {});

    Q_INVOKABLE void disconnectEthernet(const QString& connectionName, QJSValue callback = {});

    Q_INVOKABLE void connectVpn(const QString& connectionName, QJSValue callback = {});

    Q_INVOKABLE void disconnectVpn(const QString& connectionName, QJSValue callback = {});

    Q_INVOKABLE void loadSavedConnections(QJSValue callback = {});

    Q_INVOKABLE void loadVpnConnections(QJSValue callback = {});

    Q_INVOKABLE bool hasSavedProfile(const QString& ssid) const;

    Q_INVOKABLE void getWirelessDeviceDetails(const QString& interfaceName, QJSValue callback = {});

    Q_INVOKABLE void getEthernetDeviceDetails(const QString& interfaceName, QJSValue callback = {});

    Q_INVOKABLE void getIpv4Config(const QString& connectionId, QJSValue callback = {});

    Q_INVOKABLE void setIpv4Config(const QString& connectionId, const QVariantMap& config, QJSValue callback = {});

    Q_INVOKABLE void setAutoconnect(const QString& connectionId, bool enabled, QJSValue callback = {});

    Q_INVOKABLE void addHiddenNetwork(
        const QString& ssid, const QString& password, const QString& security, bool hidden, QJSValue callback = {});

    Q_INVOKABLE QString ethernetSpeed(const QString& interfaceName) const;

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
    void savedConnectionProfilesChanged();

    void activeEthernetChanged();
    void ethernetDevicesChanged();

    void vpnConnectionsChanged();
    void activeVpnChanged();

    void vpnPendingConnectionChanged();

    void wirelessDeviceDetailsChanged();
    void ethernetDeviceDetailsChanged();

    void connectionFailed(const QString& ssid);

private slots:
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

    void onNetworkManagerReady();

private:
    void refreshNetworks();
    void refreshDevices();
    void refreshEthernetDevices();
    void refreshSavedConnections();
    void refreshVpnConnections();
    void refreshWirelessDeviceDetails(const QString& interfaceName = {});
    void refreshEthernetDeviceDetails(const QString& interfaceName = {});

    void activateProfile(const NetworkManager::Connection::Ptr& conn, const NetworkManager::WirelessDevice::Ptr& device,
        QJSValue callback);

    static QVariantMap buildApMap(
        const QString& ssid, const QString& bssid, int strength, int frequency, bool active, const QString& security);

    static QJSValue buildResult(QJSEngine* engine, bool success, const QString& output = {}, const QString& error = {},
        int exitCode = 0, bool needsPassword = false);

    void invokeCallback(QJSValue callback, bool success, const QString& output = {}, const QString& error = {},
        int exitCode = 0, bool needsPassword = false);

    QVariantList m_networks;
    QVariantMap m_active;
    QStringList m_savedConnections;
    QStringList m_savedConnectionSsids;
    QVariantList m_savedConnectionProfiles;
    QVariantMap m_activeEthernet;
    QVariantList m_ethernetDevices;
    QVariantList m_vpnConnections;
    QVariantMap m_activeVpn;
    QString m_vpnPendingConnection;
    QVariantMap m_wirelessDeviceDetails;
    QVariantMap m_ethernetDeviceDetails;
    QString m_connectingSsid;
    bool m_wifiEnabled = true;
    bool m_scanning = false;
    bool m_initialised = false;

    QString m_wirelessDeviceUni;
    QString m_ethernetDeviceUni;
};

} // namespace caelestia::services
