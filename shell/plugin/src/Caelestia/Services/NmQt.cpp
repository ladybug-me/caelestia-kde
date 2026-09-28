// SPDX-License-Identifier: GPL-3.0-only
#include "NmQt.hpp"

#include <NetworkManagerQt/AccessPoint>
#include <NetworkManagerQt/ActiveConnection>
#include <NetworkManagerQt/Connection>
#include <NetworkManagerQt/ConnectionSettings>
#include <NetworkManagerQt/Device>
#include <NetworkManagerQt/IpAddress>
#include <NetworkManagerQt/Ipv4Setting>
#include <NetworkManagerQt/Manager>
#include <NetworkManagerQt/Settings>
#include <NetworkManagerQt/Utils>
#include <NetworkManagerQt/WiredDevice>
#include <NetworkManagerQt/WirelessDevice>
#include <NetworkManagerQt/WirelessNetwork>
#include <NetworkManagerQt/WirelessSecuritySetting>
#include <NetworkManagerQt/WirelessSetting>
#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QHostAddress>
#include <QJSEngine>
#include <QList>
#include <QLoggingCategory>
#include <QSet>
#include <QSharedPointer>
#include <algorithm>

Q_LOGGING_CATEGORY(lcNmQt, "caelestia.services.nmqt", QtInfoMsg)

namespace caelestia::services {

namespace {

bool isPhysicalInterface(const QString& name) {
    static const bool sysClassNetPresent = QFileInfo(QStringLiteral("/sys/class/net")).isDir();
    if (!sysClassNetPresent) {
        return true;
    }
    return QFileInfo::exists(QStringLiteral("/sys/class/net/%1/device").arg(name));
}

QString keyMgmtToString(NetworkManager::WirelessSecuritySetting::KeyMgmt k) {
    switch (k) {
    case NetworkManager::WirelessSecuritySetting::Ieee8021x:
        return QStringLiteral("ieee8021x");
    case NetworkManager::WirelessSecuritySetting::WpaPsk:
        return QStringLiteral("wpa-psk");
    case NetworkManager::WirelessSecuritySetting::WpaEap:
        return QStringLiteral("wpa-eap");
    case NetworkManager::WirelessSecuritySetting::WpaEapSuiteB192:
        return QStringLiteral("wpa-eap-suite-b-192");
    case NetworkManager::WirelessSecuritySetting::SAE:
        return QStringLiteral("sae");
    case NetworkManager::WirelessSecuritySetting::OWE:
        return QStringLiteral("owe");
    case NetworkManager::WirelessSecuritySetting::Wep:
        return QStringLiteral("wep");
    case NetworkManager::WirelessSecuritySetting::WpaNone:
        return QStringLiteral("wpa-none");
    default:
        return QString();
    }
}

/// The SSID a connection holds, as the raw bytes NetworkManager stores it as.
/// Empty for every connection type that is not wireless.
QByteArray ssidOf(const NetworkManager::Connection::Ptr& conn) {
    if (!conn || !conn->settings())
        return {};

    const auto ws = conn->settings()->setting(NetworkManager::Setting::SettingType::Wireless);
    if (!ws)
        return {};

    const auto* wireless = static_cast<NetworkManager::WirelessSetting*>(ws.data());
    return wireless->ssid();
}

QList<NetworkManager::Connection::Ptr> connectionsWithSettings() {
    QList<NetworkManager::Connection::Ptr> conns;
    for (const auto& conn : NetworkManager::listConnections()) {
        if (conn && conn->settings())
            conns.append(conn);
    }
    return conns;
}

QList<NetworkManager::Connection::Ptr> connectionsForSsid(const QString& ssid) {
    QList<NetworkManager::Connection::Ptr> matches;
    for (const auto& conn : connectionsWithSettings()) {
        if (ssidOf(conn) == ssid.toUtf8())
            matches.append(conn);
    }
    return matches;
}

/// Resolve one exact saved profile. Matching the connection id or the SSID as
/// well would land on whichever duplicate NetworkManager enumerates first.
NetworkManager::Connection::Ptr findConnectionByUuid(const QString& uuid) {
    if (uuid.isEmpty())
        return {};

    for (const auto& conn : connectionsWithSettings()) {
        if (conn->uuid() == uuid)
            return conn;
    }
    return {};
}

NetworkManager::Connection::Ptr findConnectionByName(const QString& name) {
    if (name.isEmpty())
        return {};

    for (const auto& conn : connectionsWithSettings()) {
        if (conn->uuid() == name)
            return conn;
        if (conn->settings()->id() == name)
            return conn;
        if (ssidOf(conn) == name.toUtf8())
            return conn;
    }
    return {};
}

NetworkManager::WirelessDevice::Ptr findWirelessDevice() {
    for (const auto& dev : NetworkManager::networkInterfaces()) {
        if (auto wd = dev.dynamicCast<NetworkManager::WirelessDevice>())
            return wd;
    }
    return {};
}

} // namespace

NmQt::NmQt(QObject* parent)
    : QObject(parent) {

    auto* notifier = NetworkManager::notifier();
    if (!notifier) {
        qCWarning(lcNmQt) << "NetworkManager notifier unavailable — is NetworkManager running?";
        return;
    }

    connect(notifier, &NetworkManager::Notifier::wirelessEnabledChanged, this, &NmQt::onWirelessEnabledChanged);
    connect(notifier, &NetworkManager::Notifier::wirelessHardwareEnabledChanged, this,
        &NmQt::onWirelessHardwareEnabledChanged);

    connect(notifier, &NetworkManager::Notifier::deviceAdded, this, &NmQt::onNetworkDevicesChanged);
    connect(notifier, &NetworkManager::Notifier::deviceRemoved, this, &NmQt::onNetworkDevicesChanged);

    connect(notifier, &NetworkManager::Notifier::activeConnectionsChanged, this, &NmQt::onActiveConnectionsChanged);

    connect(notifier, &NetworkManager::Notifier::serviceAppeared, this, &NmQt::onNetworkManagerReady);
    connect(notifier, &NetworkManager::Notifier::isStartingUpChanged, this, &NmQt::onNetworkManagerReady);

    if (auto* settingsNotifier = NetworkManager::settingsNotifier()) {
        connect(
            settingsNotifier, &NetworkManager::SettingsNotifier::connectionAdded, this, &NmQt::onConnectionsChanged);
        connect(
            settingsNotifier, &NetworkManager::SettingsNotifier::connectionRemoved, this, &NmQt::onConnectionsChanged);
    }

    m_wifiEnabled = NetworkManager::isWirelessEnabled();
    refreshDevices();
    refreshSavedConnections();
    refreshVpnConnections();
    refreshWirelessDeviceDetails();
    refreshEthernetDeviceDetails();

    m_initialised = true;

    qCInfo(lcNmQt) << "NmQt initialised (NetworkManagerQt D-Bus backend)";
}

NmQt::~NmQt() = default;

// ---
//  Property accessors
// ---

bool NmQt::isConnected() const {
    return NetworkManager::status() == NetworkManager::Status::Connected ||
           NetworkManager::status() == NetworkManager::Status::ConnectedLinkLocal ||
           NetworkManager::status() == NetworkManager::Status::ConnectedSiteOnly;
}

bool NmQt::wifiEnabled() const {
    return m_wifiEnabled;
}

bool NmQt::scanning() const {
    return m_scanning;
}

QString NmQt::connectingSsid() const {
    return m_connectingSsid;
}

QVariantList NmQt::networks() const {
    return m_networks;
}

QVariantMap NmQt::active() const {
    return m_active;
}

QStringList NmQt::savedConnections() const {
    return m_savedConnections;
}

QStringList NmQt::savedConnectionSsids() const {
    return m_savedConnectionSsids;
}

QVariantList NmQt::savedConnectionProfiles() const {
    return m_savedConnectionProfiles;
}

QVariantMap NmQt::activeEthernet() const {
    return m_activeEthernet;
}

QVariantList NmQt::ethernetDevices() const {
    return m_ethernetDevices;
}

QVariantList NmQt::vpnConnections() const {
    return m_vpnConnections;
}

QVariantMap NmQt::activeVpn() const {
    return m_activeVpn;
}

QString NmQt::vpnPendingConnection() const {
    return m_vpnPendingConnection;
}

QVariantMap NmQt::wirelessDeviceDetails() const {
    return m_wirelessDeviceDetails;
}

QVariantMap NmQt::ethernetDeviceDetails() const {
    return m_ethernetDeviceDetails;
}

void NmQt::getNetworks(QJSValue callback) {
    refreshNetworks();
    if (callback.isCallable()) {
        auto arr = qjsEngine(this)->toScriptValue(m_networks);
        callback.call({ arr });
    }
}

void NmQt::connectToNetwork(const QString& ssid, const QString& password, const QString& bssid, QJSValue callback) {
    const NetworkManager::WirelessDevice::Ptr wifiDev = findWirelessDevice();
    if (!wifiDev) {
        qCWarning(lcNmQt) << "connectToNetwork: no wireless device found";
        invokeCallback(callback, false, {}, QStringLiteral("No wireless device"), -1);
        return;
    }

    NetworkManager::AccessPoint::Ptr targetAp;
    for (const auto& apPath : wifiDev->accessPoints()) {
        const auto ap = wifiDev->findAccessPoint(apPath);
        if (!ap || ap->ssid() != ssid)
            continue;
        if (!bssid.isEmpty()) {
            if (ap->hardwareAddress().compare(bssid, Qt::CaseInsensitive) == 0) {
                targetAp = ap;
                break;
            }
            continue;
        }
        if (!targetAp || ap->signalStrength() > targetAp->signalStrength())
            targetAp = ap;
    }

    const bool apIsOpen = targetAp && !targetAp->wpaFlags() && !targetAp->rsnFlags() &&
                          !targetAp->capabilities().testFlag(NetworkManager::AccessPoint::Privacy);

    const NetworkManager::Connection::Ptr existingConn = connectionsForSsid(ssid).value(0);

    if (existingConn && password.isEmpty()) {
        activateProfile(existingConn, wifiDev, callback);
        return;
    }

    if (password.isEmpty() && !apIsOpen) {
        qCInfo(lcNmQt) << "connectToNetwork:" << ssid << "needs password";
        m_connectingSsid.clear();
        emit connectingSsidChanged();
        invokeCallback(callback, false, {}, QStringLiteral("Secrets were required, but not provided"), -1, true);
        return;
    }

    NetworkManager::ConnectionSettings settings(NetworkManager::ConnectionSettings::Wireless);
    settings.setId(ssid);
    settings.setUuid(NetworkManager::ConnectionSettings::createNewUuid());

    auto wirelessSetting =
        settings.setting(NetworkManager::Setting::SettingType::Wireless).dynamicCast<NetworkManager::WirelessSetting>();
    if (!wirelessSetting) {
        invokeCallback(callback, false, {}, QStringLiteral("Could not create wireless settings"), -1);
        return;
    }

    wirelessSetting->setSsid(ssid.toUtf8());
    wirelessSetting->setMode(NetworkManager::WirelessSetting::Infrastructure);
    wirelessSetting->setInitialized(true);

    QString specificObject;
    if (!bssid.isEmpty())
        wirelessSetting->setBssid(NetworkManager::macAddressFromString(bssid));
    if (targetAp)
        specificObject = targetAp->uni();

    if (!password.isEmpty()) {
        auto securitySetting = settings.setting(NetworkManager::Setting::SettingType::WirelessSecurity)
                                   .dynamicCast<NetworkManager::WirelessSecuritySetting>();
        if (!securitySetting) {
            invokeCallback(callback, false, {}, QStringLiteral("Could not create wireless security settings"), -1);
            return;
        }

        const bool useSae = targetAp && targetAp->rsnFlags().testFlag(NetworkManager::AccessPoint::KeyMgmtSAE);
        securitySetting->setKeyMgmt(
            useSae ? NetworkManager::WirelessSecuritySetting::SAE : NetworkManager::WirelessSecuritySetting::WpaPsk);
        securitySetting->setPsk(password);
        securitySetting->setInitialized(true);
        wirelessSetting->setSecurity(securitySetting->name());
    }
    // else: open network (apIsOpen) — no wireless-security setting needed.

    QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> reply =
        NetworkManager::addAndActivateConnection(settings.toMap(), wifiDev->uni(), specificObject);
    m_connectingSsid = ssid;
    emit connectingSsidChanged();

    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, ssid, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> r = *w;
        if (r.isError()) {
            qCWarning(lcNmQt) << "addAndActivateConnection failed:" << r.error().message();
            m_connectingSsid.clear();
            emit connectingSsidChanged();
            const auto& errMsg = r.error().message();
            bool needsPw = errMsg.contains(QStringLiteral("Secrets")) || errMsg.contains(QStringLiteral("password")) ||
                           errMsg.contains(QStringLiteral("802-11-wireless-security"));
            invokeCallback(callback, false, {}, errMsg, -1, needsPw);
        } else {
            m_connectingSsid.clear();
            emit connectingSsidChanged();
            invokeCallback(callback, true, QStringLiteral("Connection created and activated"));
        }
    });
}

void NmQt::connectToNetworkWithPasswordCheck(
    const QString& ssid, bool isSecure, QJSValue callback, const QString& bssid) {
    if (!isSecure) {
        connectToNetwork(ssid, QString(), bssid, callback);
        return;
    }

    const bool hasSavedConn = !connectionsForSsid(ssid).isEmpty();

    if (hasSavedConn) {
        connectToNetwork(ssid, QString(), bssid, callback);
    } else {
        invokeCallback(callback, false, {}, QStringLiteral("Secrets were required, but not provided"), -1, true);
    }
}

void NmQt::activateProfile(
    const NetworkManager::Connection::Ptr& conn, const NetworkManager::WirelessDevice::Ptr& device, QJSValue callback) {
    const QString ssid = QString::fromUtf8(ssidOf(conn));
    if (!ssid.isEmpty()) {
        m_connectingSsid = ssid;
        emit connectingSsidChanged();
    }

    QDBusPendingReply<QDBusObjectPath> reply =
        NetworkManager::activateConnection(conn->path(), device->uni(), QString());
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, ssid, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> r = *w;
        if (!ssid.isEmpty()) {
            m_connectingSsid.clear();
            emit connectingSsidChanged();
        }
        if (r.isError()) {
            qCWarning(lcNmQt) << "activateConnection failed:" << r.error().message();
            invokeCallback(callback, false, {}, r.error().message(), -1);
        } else {
            invokeCallback(callback, true, QStringLiteral("Connection activated"));
        }
    });
}

void NmQt::connectToNetworkByUuid(const QString& uuid, QJSValue callback) {
    if (uuid.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection UUID specified"), -1);
        return;
    }

    const NetworkManager::Connection::Ptr target = findConnectionByUuid(uuid);

    if (!target || !target->settings()) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection found for UUID"), -1);
        return;
    }

    const NetworkManager::WirelessDevice::Ptr wifiDev = findWirelessDevice();
    if (!wifiDev) {
        qCWarning(lcNmQt) << "connectToNetworkByUuid: no wireless device found";
        invokeCallback(callback, false, {}, QStringLiteral("No wireless device"), -1);
        return;
    }

    activateProfile(target, wifiDev, callback);
}

void NmQt::disconnectFromNetwork() {
    const auto activeConns = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activeConns) {
        NetworkManager::ActiveConnection::Ptr ac = NetworkManager::findActiveConnection(path);
        if (!ac)
            continue;

        bool isWireless = false;
        for (const auto& devicePath : ac->devices()) {
            const auto dev = NetworkManager::findNetworkInterface(devicePath);
            if (dev && dev->type() == NetworkManager::Device::Wifi) {
                isWireless = true;
                break;
            }
        }

        if (isWireless) {
            NetworkManager::deactivateConnection(path);
            return;
        }
    }

    if (const auto wifiDev = findWirelessDevice())
        wifiDev->disconnectInterface();
}

void NmQt::forgetNetwork(const QString& ssid, QJSValue callback) {
    const auto matches = connectionsForSsid(ssid);

    if (matches.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection found for SSID"), -1);
        return;
    }

    auto remaining = QSharedPointer<int>(new int(matches.size()));
    auto failed = QSharedPointer<QString>(new QString);
    for (const auto& conn : matches) {
        QDBusPendingReply<> reply = conn->remove();
        auto* watcher = new QDBusPendingCallWatcher(reply, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, callback, remaining, failed](QDBusPendingCallWatcher* w) {
                if (w->isError() && failed->isEmpty())
                    *failed = w->error().message();
                w->deleteLater();
                if (--*remaining > 0)
                    return;
                refreshSavedConnections();
                if (failed->isEmpty())
                    invokeCallback(callback, true, QStringLiteral("Deleted"));
                else
                    invokeCallback(callback, false, {}, *failed, -1);
            });
    }
}

void NmQt::forgetNetworkByUuid(const QString& uuid, QJSValue callback) {
    if (uuid.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection UUID specified"), -1);
        return;
    }

    const NetworkManager::Connection::Ptr target = findConnectionByUuid(uuid);

    if (!target) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection found for UUID"), -1);
        return;
    }

    QDBusPendingReply<> reply = target->remove();
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        if (w->isError()) {
            refreshSavedConnections();
            invokeCallback(callback, false, {}, w->error().message(), -1);
            return;
        }
        refreshSavedConnections();
        invokeCallback(callback, true, QStringLiteral("Deleted"));
    });
}

void NmQt::enableWifi(bool enabled, QJSValue callback) {
    NetworkManager::setWirelessEnabled(enabled);
    invokeCallback(callback, true, QStringLiteral("OK"));
}

void NmQt::toggleWifi(QJSValue callback) {
    enableWifi(!m_wifiEnabled, callback);
}

void NmQt::rescanWifi() {
    if (m_scanning) {
        qCInfo(lcNmQt) << "rescanWifi: already scanning, request queued";
        return;
    }

    NetworkManager::WirelessDevice::Ptr wifiDev;
    for (const auto& dev : NetworkManager::networkInterfaces()) {
        auto wd = dev.dynamicCast<NetworkManager::WirelessDevice>();
        if (wd) {
            wifiDev = wd;
            m_wirelessDeviceUni = dev->uni();
            break;
        }
    }

    if (!wifiDev) {
        qCWarning(lcNmQt) << "rescanWifi: no wireless device found";
        return;
    }

    m_scanning = true;
    emit scanningChanged();

    connect(wifiDev.data(), &NetworkManager::WirelessDevice::lastScanChanged, this, &NmQt::onScanFinished,
        Qt::UniqueConnection);

    auto reply = wifiDev->requestScan();
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<> result = *w;
        w->deleteLater();
        if (result.isError()) {
            qCWarning(lcNmQt) << "rescanWifi failed:" << result.error().message();
            m_scanning = false;
            emit scanningChanged();
        }
    });
}

void NmQt::connectEthernet(const QString& connectionName, const QString& interfaceName, QJSValue callback) {
    if (!connectionName.isEmpty()) {
        const auto connPaths = NetworkManager::listConnections();
        for (const auto& conn : connPaths) {
            if (conn && conn->name() == connectionName) {
                QDBusPendingReply<QDBusObjectPath> reply =
                    NetworkManager::activateConnection(conn->path(), interfaceName, QString());
                auto* watcher = new QDBusPendingCallWatcher(reply, this);
                connect(
                    watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
                        w->deleteLater();
                        QDBusPendingReply<QDBusObjectPath> r = *w;
                        invokeCallback(callback, !r.isError(), r.isError() ? QString() : QStringLiteral("Connected"),
                            r.isError() ? r.error().message() : QString());
                        refreshEthernetDevices();
                    });
                return;
            }
        }
    }

    if (!interfaceName.isEmpty()) {
        auto dev = NetworkManager::findNetworkInterface(interfaceName);
        if (!dev)
            dev = NetworkManager::findDeviceByIpFace(interfaceName);
        if (dev) {
            const auto availableConnections = dev->availableConnections();
            if (!availableConnections.isEmpty()) {
                const auto connection = availableConnections.front();
                QDBusPendingReply<QDBusObjectPath> reply =
                    NetworkManager::activateConnection(connection->path(), dev->uni(), QString());
                auto* watcher = new QDBusPendingCallWatcher(reply, this);
                connect(
                    watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
                        w->deleteLater();
                        QDBusPendingReply<QDBusObjectPath> r = *w;
                        invokeCallback(callback, !r.isError(), r.isError() ? QString() : QStringLiteral("Connected"),
                            r.isError() ? r.error().message() : QString());
                        refreshEthernetDevices();
                    });
                return;
            }
        }
    }

    invokeCallback(callback, false, {}, QStringLiteral("No connection name or interface specified"), -1);
}

void NmQt::disconnectEthernet(const QString& connectionName, QJSValue callback) {
    if (connectionName.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection name specified"), -1);
        return;
    }

    const auto activeConns = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activeConns) {
        NetworkManager::ActiveConnection::Ptr ac = NetworkManager::findActiveConnection(path);
        if (!ac)
            continue;
        if (ac->id() == connectionName || ac->uuid() == connectionName) {
            NetworkManager::deactivateConnection(path);
            invokeCallback(callback, true, QStringLiteral("Disconnected"));
            refreshEthernetDevices();
            return;
        }
    }

    invokeCallback(callback, false, {}, QStringLiteral("Connection not active"), -1);
}

void NmQt::connectVpn(const QString& connectionName, QJSValue callback) {
    if (connectionName.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No VPN connection name specified"), -1);
        return;
    }

    m_vpnPendingConnection = connectionName;
    emit vpnPendingConnectionChanged();

    const auto connPaths = NetworkManager::listConnections();
    for (const auto& conn : connPaths) {
        if (conn && (conn->name() == connectionName || conn->uuid() == connectionName)) {
            QDBusPendingReply<QDBusObjectPath> reply =
                NetworkManager::activateConnection(conn->path(), QString(), QString());
            auto* watcher = new QDBusPendingCallWatcher(reply, this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, connectionName, callback](QDBusPendingCallWatcher* w) {
                    w->deleteLater();
                    QDBusPendingReply<QDBusObjectPath> r = *w;
                    invokeCallback(callback, !r.isError(), r.isError() ? QString() : QStringLiteral("Connected"),
                        r.isError() ? r.error().message() : QString());
                    if (m_vpnPendingConnection == connectionName) {
                        m_vpnPendingConnection.clear();
                        emit vpnPendingConnectionChanged();
                    }
                    refreshVpnConnections();
                });
            return;
        }
    }

    invokeCallback(callback, false, {}, QStringLiteral("VPN connection not found"), -1);
    m_vpnPendingConnection.clear();
    emit vpnPendingConnectionChanged();
}

void NmQt::disconnectVpn(const QString& connectionName, QJSValue callback) {
    if (connectionName.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No VPN connection name specified"), -1);
        return;
    }

    m_vpnPendingConnection = connectionName;
    emit vpnPendingConnectionChanged();

    const auto activeConns = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activeConns) {
        NetworkManager::ActiveConnection::Ptr ac = NetworkManager::findActiveConnection(path);
        if (ac && (ac->id() == connectionName || ac->uuid() == connectionName)) {
            NetworkManager::deactivateConnection(path);
            invokeCallback(callback, true, QStringLiteral("Disconnected"));
            if (m_vpnPendingConnection == connectionName) {
                m_vpnPendingConnection.clear();
                emit vpnPendingConnectionChanged();
            }
            refreshVpnConnections();
            return;
        }
    }

    invokeCallback(callback, false, {}, QStringLiteral("VPN connection not active"), -1);
    m_vpnPendingConnection.clear();
    emit vpnPendingConnectionChanged();
}

void NmQt::loadSavedConnections(QJSValue callback) {
    refreshSavedConnections();
    if (callback.isCallable()) {
        auto arr = qjsEngine(this)->toScriptValue(m_savedConnectionProfiles);
        callback.call({ arr });
    }
}

void NmQt::loadVpnConnections(QJSValue callback) {
    refreshVpnConnections();
    if (callback.isCallable()) {
        auto arr = qjsEngine(this)->toScriptValue(m_vpnConnections);
        callback.call({ arr });
    }
}

bool NmQt::hasSavedProfile(const QString& ssid) const {
    if (ssid.isEmpty())
        return false;

    if (!m_active.isEmpty() && m_active.value(QStringLiteral("ssid")).toString() == ssid)
        return true;

    const auto ssidLower = ssid.toLower().trimmed();
    for (const auto& saved : m_savedConnectionSsids) {
        if (saved.toLower().trimmed() == ssidLower)
            return true;
    }

    for (const auto& conn : m_savedConnections) {
        if (conn.toLower().trimmed() == ssidLower)
            return true;
    }

    return false;
}

void NmQt::getWirelessDeviceDetails(const QString& interfaceName, QJSValue callback) {
    refreshWirelessDeviceDetails(interfaceName);
    if (callback.isCallable()) {
        auto engine = qjsEngine(this);
        auto obj = engine->toScriptValue(m_wirelessDeviceDetails);
        callback.call({ obj });
    }
}

void NmQt::getEthernetDeviceDetails(const QString& interfaceName, QJSValue callback) {
    refreshEthernetDeviceDetails(interfaceName);
    if (callback.isCallable()) {
        auto engine = qjsEngine(this);
        auto obj = engine->toScriptValue(m_ethernetDeviceDetails);
        callback.call({ obj });
    }
}

void NmQt::getIpv4Config(const QString& connectionId, QJSValue callback) {
    if (!callback.isCallable())
        return;

    auto* engine = qjsEngine(this);
    if (!engine)
        return;

    const auto conn = findConnectionByName(connectionId);
    if (!conn) {
        callback.call({ QJSValue() });
        return;
    }

    auto cfg = engine->newObject();
    cfg.setProperty(QStringLiteral("method"), QStringLiteral("auto"));
    cfg.setProperty(QStringLiteral("address"), QString());
    cfg.setProperty(QStringLiteral("gateway"), QString());
    cfg.setProperty(QStringLiteral("dns"), QString());
    cfg.setProperty(QStringLiteral("ignoreAutoDns"), false);
    cfg.setProperty(QStringLiteral("autoconnect"), conn->settings()->autoconnect());

    const auto ipv4 = conn->settings()
                          ->setting(NetworkManager::Setting::SettingType::Ipv4)
                          .dynamicCast<NetworkManager::Ipv4Setting>();
    if (!ipv4) {
        callback.call({ cfg });
        return;
    }

    if (ipv4->method() == NetworkManager::Ipv4Setting::Manual) {
        cfg.setProperty(QStringLiteral("method"), QStringLiteral("manual"));
    } else if (ipv4->method() == NetworkManager::Ipv4Setting::Automatic && ipv4->ignoreAutoDns()) {
        cfg.setProperty(QStringLiteral("method"), QStringLiteral("auto-dns"));
    }

    const auto addrs = ipv4->addresses();
    if (!addrs.isEmpty()) {
        QString addr = addrs.first().ip().toString();
        if (addrs.first().prefixLength() > 0)
            addr += QStringLiteral("/") + QString::number(addrs.first().prefixLength());
        cfg.setProperty(QStringLiteral("address"), addr);
    }
    if (!ipv4->gateway().isEmpty())
        cfg.setProperty(QStringLiteral("gateway"), ipv4->gateway());

    QStringList dns;
    for (const auto& d : ipv4->dns())
        dns << d.toString();
    cfg.setProperty(QStringLiteral("dns"), dns.join(QStringLiteral(", ")));
    cfg.setProperty(QStringLiteral("ignoreAutoDns"), ipv4->ignoreAutoDns());

    callback.call({ cfg });
}

void NmQt::setIpv4Config(const QString& connectionId, const QVariantMap& config, QJSValue callback) {
    const auto conn = findConnectionByName(connectionId);
    if (!conn) {
        invokeCallback(callback, false, {}, QStringLiteral("Connection not found"), -1);
        return;
    }
    auto settings = conn->settings();
    if (!settings) {
        invokeCallback(callback, false, {}, QStringLiteral("No connection settings"), -1);
        return;
    }

    const QString method = config.value(QStringLiteral("method")).toString();
    const QString addressStr = config.value(QStringLiteral("address")).toString().trimmed();
    const QString gatewayStr = config.value(QStringLiteral("gateway")).toString().trimmed();
    const QString dnsStr = config.value(QStringLiteral("dns")).toString().trimmed();

    auto ipv4 =
        settings->setting(NetworkManager::Setting::SettingType::Ipv4).dynamicCast<NetworkManager::Ipv4Setting>();
    if (!ipv4) {
        invokeCallback(callback, false, {}, QStringLiteral("No IPv4 setting"), -1);
        return;
    }

    if (method == QLatin1String("manual")) {
        ipv4->setMethod(NetworkManager::Ipv4Setting::Manual);

        QString ip = addressStr;
        int prefix = 24;
        const int slash = addressStr.indexOf(QLatin1Char('/'));
        if (slash >= 0) {
            ip = addressStr.left(slash);
            bool ok = false;
            const int p = addressStr.mid(slash + 1).toInt(&ok);
            if (ok)
                prefix = p;
        }

        NetworkManager::IpAddress addr;
        addr.setIp(QHostAddress(ip));
        addr.setPrefixLength(prefix);
        if (!gatewayStr.isEmpty())
            addr.setGateway(QHostAddress(gatewayStr));
        ipv4->setAddresses({ addr });
        ipv4->setGateway(gatewayStr);
    } else {
        ipv4->setMethod(NetworkManager::Ipv4Setting::Automatic);
        ipv4->setAddresses({});
        ipv4->setGateway(QString());
    }

    const bool customDns = method == QLatin1String("manual") || method == QLatin1String("auto-dns");
    QList<QHostAddress> dnsList;
    if (customDns && !dnsStr.isEmpty()) {
        const auto parts = dnsStr.split(QLatin1Char(','), Qt::SkipEmptyParts);
        for (const auto& part : parts) {
            const QHostAddress a(part.trimmed());
            if (!a.isNull())
                dnsList << a;
        }
    }
    ipv4->setDns(dnsList);
    ipv4->setIgnoreAutoDns(customDns);

    QDBusPendingReply<> reply = conn->update(settings->toMap());
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<> r = *w;
        if (r.isError()) {
            invokeCallback(callback, false, {}, r.error().message(), -1);
            return;
        }
        invokeCallback(callback, true, QStringLiteral("IPv4 updated"));
    });
}

void NmQt::setAutoconnect(const QString& connectionId, bool enabled, QJSValue callback) {
    const auto conn = findConnectionByName(connectionId);
    if (!conn) {
        invokeCallback(callback, false, {}, QStringLiteral("Connection not found"), -1);
        return;
    }

    auto settings = conn->settings();
    settings->setAutoconnect(enabled);

    QDBusPendingReply<> reply = conn->update(settings->toMap());
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<> r = *w;
        if (r.isError()) {
            invokeCallback(callback, false, {}, r.error().message(), -1);
            return;
        }
        invokeCallback(callback, true, QStringLiteral("Autoconnect updated"));
    });
}

void NmQt::addHiddenNetwork(
    const QString& ssid, const QString& password, const QString& security, bool hidden, QJSValue callback) {
    if (ssid.isEmpty()) {
        invokeCallback(callback, false, {}, QStringLiteral("No SSID specified"), -1);
        return;
    }

    const NetworkManager::WirelessDevice::Ptr wifiDev = findWirelessDevice();
    if (!wifiDev) {
        invokeCallback(callback, false, {}, QStringLiteral("No wireless device"), -1);
        return;
    }

    const auto existing = findConnectionByName(ssid);
    if (existing) {
        m_connectingSsid = ssid;
        emit connectingSsidChanged();
        QDBusPendingReply<QDBusObjectPath> reply =
            NetworkManager::activateConnection(existing->path(), wifiDev->uni(), QString());
        auto* watcher = new QDBusPendingCallWatcher(reply, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, ssid, callback](QDBusPendingCallWatcher* w) {
            w->deleteLater();
            QDBusPendingReply<QDBusObjectPath> r = *w;
            if (r.isError()) {
                m_connectingSsid.clear();
                emit connectingSsidChanged();
                invokeCallback(callback, false, {}, r.error().message(), -1);
            } else {
                m_connectingSsid.clear();
                emit connectingSsidChanged();
                invokeCallback(callback, true, QStringLiteral("Connection activated"));
            }
        });
        return;
    }

    const bool secure = !security.isEmpty() && security != QLatin1String("none") && !password.isEmpty();

    NetworkManager::ConnectionSettings settings(NetworkManager::ConnectionSettings::Wireless);
    settings.setId(ssid);
    settings.setUuid(NetworkManager::ConnectionSettings::createNewUuid());

    auto wirelessSetting =
        settings.setting(NetworkManager::Setting::SettingType::Wireless).dynamicCast<NetworkManager::WirelessSetting>();
    if (!wirelessSetting) {
        invokeCallback(callback, false, {}, QStringLiteral("Could not create wireless settings"), -1);
        return;
    }

    wirelessSetting->setSsid(ssid.toUtf8());
    wirelessSetting->setMode(NetworkManager::WirelessSetting::Infrastructure);
    if (hidden)
        wirelessSetting->setHidden(true);
    wirelessSetting->setInitialized(true);

    if (secure) {
        auto securitySetting = settings.setting(NetworkManager::Setting::SettingType::WirelessSecurity)
                                   .dynamicCast<NetworkManager::WirelessSecuritySetting>();
        if (!securitySetting) {
            invokeCallback(callback, false, {}, QStringLiteral("Could not create security settings"), -1);
            return;
        }
        securitySetting->setKeyMgmt(NetworkManager::WirelessSecuritySetting::WpaPsk);
        securitySetting->setPsk(password);
        securitySetting->setInitialized(true);
        wirelessSetting->setSecurity(securitySetting->name());
    }

    QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> reply =
        NetworkManager::addAndActivateConnection(settings.toMap(), wifiDev->uni(), QString());
    m_connectingSsid = ssid;
    emit connectingSsidChanged();

    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, ssid, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> r = *w;
        if (r.isError()) {
            m_connectingSsid.clear();
            emit connectingSsidChanged();
            invokeCallback(callback, false, {}, r.error().message(), -1);
        } else {
            m_connectingSsid.clear();
            emit connectingSsidChanged();
            refreshSavedConnections();
            invokeCallback(callback, true, QStringLiteral("Hidden network added"));
        }
    });
}

QString NmQt::ethernetSpeed(const QString& interfaceName) const {
    if (interfaceName.isEmpty())
        return {};
    QFile f(QStringLiteral("/sys/class/net/%1/speed").arg(interfaceName));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    bool ok = false;
    const int speed = QString::fromLatin1(f.readAll()).trimmed().toInt(&ok);
    if (!ok || speed <= 0)
        return {};
    return QStringLiteral("%1 Mb/s").arg(speed);
}

QString NmQt::ethernetDataUsage(const QString& interfaceName) const {
    if (interfaceName.isEmpty())
        return {};
    quint64 total = 0;
    const char* names[] = { "rx_bytes", "tx_bytes" };
    for (const char* name : names) {
        QFile f(QStringLiteral("/sys/class/net/%1/statistics/%2").arg(interfaceName, name));
        if (f.open(QIODevice::ReadOnly))
            total += QString::fromLatin1(f.readAll()).trimmed().toULongLong();
    }
    if (total == 0)
        return {};
    const QStringList units = { QStringLiteral("B"), QStringLiteral("KB"), QStringLiteral("MB"), QStringLiteral("GB"),
        QStringLiteral("TB") };
    double value = static_cast<double>(total);
    int i = 0;
    while (value >= 1024.0 && i < units.size() - 1) {
        value /= 1024.0;
        ++i;
    }
    return QString::number(value, 'f', (value < 10.0 && i > 0) ? 1 : 0) + QLatin1Char(' ') + units.at(i);
}

void NmQt::onWirelessEnabledChanged(bool enabled) {
    m_wifiEnabled = enabled;
    emit wifiEnabledChanged();
}

void NmQt::onWirelessHardwareEnabledChanged(bool enabled) {
    if (!enabled) {
        m_wifiEnabled = false;
        emit wifiEnabledChanged();
    }
}

void NmQt::onNetworkDevicesChanged() {
    refreshDevices();
    refreshNetworks();
}

void NmQt::onActiveConnectionsChanged() {
    refreshNetworks();
    refreshDevices();
    refreshVpnConnections();
    refreshSavedConnections();
    emit isConnectedChanged();
}

void NmQt::onConnectionsChanged() {
    refreshSavedConnections();
    refreshVpnConnections();
}

void NmQt::onDeviceStateChanged(NetworkManager::Device::State newState, NetworkManager::Device::State oldState,
    NetworkManager::Device::StateChangeReason /*reason*/) {
    Q_UNUSED(oldState)
    const bool wasConnecting = (oldState == NetworkManager::Device::State::NeedAuth ||
                                oldState == NetworkManager::Device::State::ConfiguringHardware ||
                                oldState == NetworkManager::Device::State::ConfiguringIp);

    if (wasConnecting) {
        m_connectingSsid.clear();
        emit connectingSsidChanged();
    }

    switch (newState) {
    case NetworkManager::Device::State::Activated:
        refreshNetworks();
        refreshWirelessDeviceDetails();
        refreshEthernetDeviceDetails();
        break;
    case NetworkManager::Device::State::Failed:
        if (auto* dev = qobject_cast<NetworkManager::Device*>(sender())) {
            auto* wd = qobject_cast<NetworkManager::WirelessDevice*>(dev);
            if (wd) {
                emit connectionFailed(wd->activeAccessPoint() ? wd->activeAccessPoint()->ssid() : QString());
            }
        }
        break;
    default:
        break;
    }

    emit isConnectedChanged();
}

void NmQt::onScanFinished(const QDateTime& /*dateTime*/) {
    m_scanning = false;
    emit scanningChanged();
    refreshNetworks();
}

void NmQt::onAccessPointAppeared(const QString& /*apPath*/) {
    refreshNetworks();
}

void NmQt::onAccessPointDisappeared(const QString& /*apPath*/) {
    refreshNetworks();
}

void NmQt::onNetworkManagerReady() {
    refreshDevices();
    refreshSavedConnections();
    refreshVpnConnections();
    refreshWirelessDeviceDetails();
    refreshEthernetDeviceDetails();
    emit isConnectedChanged();
}

void NmQt::refreshNetworks() {
    NetworkManager::WirelessDevice::Ptr wifiDev;
    for (const auto& dev : NetworkManager::networkInterfaces()) {
        auto wd = dev.dynamicCast<NetworkManager::WirelessDevice>();
        if (wd) {
            wifiDev = wd;
            m_wirelessDeviceUni = dev->uni();
            break;
        }
    }

    if (!wifiDev) {
        if (!m_networks.isEmpty()) {
            m_networks.clear();
            emit networksChanged();
        }
        return;
    }

    connect(
        wifiDev.data(), &NetworkManager::Device::stateChanged, this, &NmQt::onDeviceStateChanged, Qt::UniqueConnection);
    connect(wifiDev.data(), &NetworkManager::WirelessDevice::accessPointAppeared, this, &NmQt::onAccessPointAppeared,
        Qt::UniqueConnection);
    connect(wifiDev.data(), &NetworkManager::WirelessDevice::accessPointDisappeared, this,
        &NmQt::onAccessPointDisappeared, Qt::UniqueConnection);

    QVariantList newList;
    QVariantMap activeAp;
    const auto aps = wifiDev->accessPoints();
    QHash<QString, int> networkIndexes;

    for (const auto& apPath : aps) {
        NetworkManager::AccessPoint::Ptr ap = wifiDev->findAccessPoint(apPath);
        if (!ap || ap->ssid().isEmpty())
            continue;

        int strength = ap->signalStrength();
        int frequency = static_cast<int>(ap->frequency());
        const auto activeAccessPoint = wifiDev->activeAccessPoint();
        bool isActive = activeAccessPoint && activeAccessPoint->uni() == apPath;

        QString security;
        auto wpaFlags = ap->wpaFlags();
        auto rsnFlags = ap->rsnFlags();
        if (wpaFlags || rsnFlags) {
            if (rsnFlags.testFlag(NetworkManager::AccessPoint::KeyMgmtSAE) &&
                rsnFlags.testFlag(NetworkManager::AccessPoint::KeyMgmtPsk))
                security = QStringLiteral("WPA2/WPA3");
            else if (rsnFlags.testFlag(NetworkManager::AccessPoint::KeyMgmtSAE))
                security = QStringLiteral("WPA3");
            else if (rsnFlags)
                security = QStringLiteral("WPA2");
            else if (wpaFlags)
                security = QStringLiteral("WPA");
            else
                security = QStringLiteral("encrypted");
        } else if (ap->capabilities().testFlag(NetworkManager::AccessPoint::Privacy)) {
            security = QStringLiteral("WEP");
        }

        auto map = buildApMap(ap->ssid(), ap->hardwareAddress(), strength, frequency, isActive, security);
        const int existingIndex = networkIndexes.value(ap->ssid(), -1);
        if (existingIndex < 0) {
            networkIndexes.insert(ap->ssid(), newList.size());
            newList.append(map);
        } else {
            const auto existing = newList.at(existingIndex).toMap();
            const bool replace = (isActive && !existing.value(QStringLiteral("active")).toBool()) ||
                                 (!isActive && !existing.value(QStringLiteral("active")).toBool() &&
                                     strength > existing.value(QStringLiteral("strength")).toInt());
            if (replace)
                newList[existingIndex] = map;
        }

        if (isActive)
            activeAp = map;
    }

    std::sort(newList.begin(), newList.end(), [](const QVariant& a, const QVariant& b) {
        auto ma = a.toMap();
        auto mb = b.toMap();
        if (ma.value(QStringLiteral("active")).toBool() != mb.value(QStringLiteral("active")).toBool())
            return ma.value(QStringLiteral("active")).toBool();
        return ma.value(QStringLiteral("strength")).toInt() > mb.value(QStringLiteral("strength")).toInt();
    });

    bool changed = (m_networks != newList);
    if (changed) {
        m_networks = newList;
        emit networksChanged();
    }

    if (m_active != activeAp) {
        m_active = activeAp;
        emit activeChanged();
    }

    if (!m_connectingSsid.isEmpty() && m_active.value(QStringLiteral("ssid")).toString() == m_connectingSsid) {
        m_connectingSsid.clear();
        emit connectingSsidChanged();
    }
}

void NmQt::refreshDevices() {
    refreshEthernetDevices();
    refreshNetworks();
}

void NmQt::refreshEthernetDevices() {
    QVariantList devices;
    QVariantMap activeEth;

    for (const auto& dev : NetworkManager::networkInterfaces()) {
        if (!dev)
            continue;

        if (dev->type() != NetworkManager::Device::Ethernet)
            continue;

        if (!isPhysicalInterface(dev->interfaceName()))
            continue;

        QVariantMap info;
        info[QStringLiteral("interface")] = dev->interfaceName();
        info[QStringLiteral("type")] = QStringLiteral("ethernet");
        info[QStringLiteral("state")] = static_cast<int>(dev->state());
        info[QStringLiteral("connected")] = (dev->state() == NetworkManager::Device::State::Activated);

        if (dev->state() == NetworkManager::Device::State::Activated) {
            const auto activeConns = NetworkManager::activeConnectionsPaths();
            for (const auto& path : activeConns) {
                auto ac = NetworkManager::findActiveConnection(path);
                if (ac && ac->devices().contains(dev->uni())) {
                    info[QStringLiteral("connection")] = ac->id();
                    break;
                }
            }
        }

        devices.append(info);

        if (info[QStringLiteral("connected")].toBool() && activeEth.isEmpty()) {
            activeEth = info;
        }
    }

    bool ethChanged = (m_ethernetDevices != devices);
    bool activeEthChanged = (m_activeEthernet != activeEth);

    if (ethChanged) {
        m_ethernetDevices = devices;
        emit ethernetDevicesChanged();
    }
    if (activeEthChanged) {
        m_activeEthernet = activeEth;
        emit activeEthernetChanged();
    }
}

void NmQt::refreshSavedConnections() {
    QStringList connNames;
    QStringList ssids;
    QVariantList profiles;

    QSet<QString> activeUuids;
    for (const auto& path : NetworkManager::activeConnectionsPaths()) {
        const auto ac = NetworkManager::findActiveConnection(path);
        if (ac)
            activeUuids.insert(ac->uuid());
    }

    for (const auto& conn : connectionsWithSettings()) {
        connNames.append(conn->name());

        const QString ssid = QString::fromUtf8(ssidOf(conn));
        if (ssid.isEmpty())
            continue;

        ssids.append(ssid);

        QString keyMgmt;
        const auto sec = conn->settings()->setting(NetworkManager::Setting::SettingType::WirelessSecurity);
        if (sec) {
            const auto* secSetting = static_cast<NetworkManager::WirelessSecuritySetting*>(sec.data());
            keyMgmt = keyMgmtToString(secSetting->keyMgmt());
        }
        if (keyMgmt.isEmpty())
            keyMgmt = QStringLiteral("none");

        QVariantMap profile;
        profile[QStringLiteral("ssid")] = ssid;
        profile[QStringLiteral("id")] = conn->name();
        profile[QStringLiteral("uuid")] = conn->uuid();
        profile[QStringLiteral("path")] = conn->path();
        profile[QStringLiteral("security")] = keyMgmt;
        profile[QStringLiteral("active")] = activeUuids.contains(conn->uuid());
        profiles.append(profile);
    }

    if (m_savedConnections != connNames) {
        m_savedConnections = connNames;
        emit savedConnectionsChanged();
    }

    if (m_savedConnectionSsids != ssids) {
        m_savedConnectionSsids = ssids;
        emit savedConnectionSsidsChanged();
    }

    if (m_savedConnectionProfiles != profiles) {
        m_savedConnectionProfiles = profiles;
        emit savedConnectionProfilesChanged();
    }
}

void NmQt::refreshVpnConnections() {
    QVariantList vpnList;
    QVariantMap activeVpn;

    QSet<QString> activeVpnNames;
    const auto activeConns = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activeConns) {
        auto ac = NetworkManager::findActiveConnection(path);
        if (!ac)
            continue;
        auto conn = ac->connection();
        if (conn && conn->settings()) {
            auto vs = conn->settings()->setting(NetworkManager::Setting::SettingType::Vpn);
            auto wg = conn->settings()->setting(NetworkManager::Setting::SettingType::WireGuard);
            if (vs || wg) {
                activeVpnNames.insert(ac->id().toLower().trimmed());
            }
        }
    }

    const auto connPaths = NetworkManager::listConnections();
    for (const auto& conn : connPaths) {
        if (!conn || !conn->settings())
            continue;

        auto vs = conn->settings()->setting(NetworkManager::Setting::SettingType::Vpn);
        auto wg = conn->settings()->setting(NetworkManager::Setting::SettingType::WireGuard);
        if (!vs && !wg)
            continue;

        QVariantMap info;
        info[QStringLiteral("name")] = conn->name();
        info[QStringLiteral("type")] = QStringLiteral("vpn");
        info[QStringLiteral("connected")] = activeVpnNames.contains(conn->name().toLower().trimmed());
        vpnList.append(info);

        if (info[QStringLiteral("connected")].toBool())
            activeVpn = info;
    }

    std::sort(vpnList.begin(), vpnList.end(), [](const QVariant& a, const QVariant& b) {
        auto ma = a.toMap();
        auto mb = b.toMap();
        if (ma.value(QStringLiteral("connected")).toBool() != mb.value(QStringLiteral("connected")).toBool())
            return ma.value(QStringLiteral("connected")).toBool();
        return ma.value(QStringLiteral("name")).toString() < mb.value(QStringLiteral("name")).toString();
    });

    if (m_vpnConnections != vpnList) {
        m_vpnConnections = vpnList;
        emit vpnConnectionsChanged();
    }

    if (m_activeVpn != activeVpn) {
        m_activeVpn = activeVpn;
        emit activeVpnChanged();
    }
}

void NmQt::refreshWirelessDeviceDetails(const QString& interfaceName) {
    NetworkManager::WirelessDevice::Ptr wifiDev;
    if (!interfaceName.isEmpty()) {
        auto dev = NetworkManager::findNetworkInterface(interfaceName);
        if (!dev)
            dev = NetworkManager::findDeviceByIpFace(interfaceName);
        wifiDev = dev.dynamicCast<NetworkManager::WirelessDevice>();
    } else {
        for (const auto& dev : NetworkManager::networkInterfaces()) {
            auto wd = dev.dynamicCast<NetworkManager::WirelessDevice>();
            if (wd && dev->state() == NetworkManager::Device::State::Activated) {
                wifiDev = wd;
                break;
            }
        }
    }

    if (!wifiDev) {
        m_wirelessDeviceDetails = {};
        emit wirelessDeviceDetailsChanged();
        return;
    }

    QVariantMap details;
    details[QStringLiteral("ipAddress")] = {};
    details[QStringLiteral("gateway")] = {};
    details[QStringLiteral("dns")] = QVariantList();
    details[QStringLiteral("subnet")] = {};
    details[QStringLiteral("macAddress")] = wifiDev->hardwareAddress();

    const auto activeConns = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activeConns) {
        auto ac = NetworkManager::findActiveConnection(path);
        if (!ac || !ac->devices().contains(wifiDev->uni()))
            continue;

        auto ipv4Config = ac->ipV4Config();
        if (ipv4Config.isValid()) {
            if (!ipv4Config.addresses().isEmpty()) {
                const auto addr = ipv4Config.addresses().first();
                details[QStringLiteral("ipAddress")] = addr.ip().toString();
                details[QStringLiteral("subnet")] = addr.netmask().toString();
            }
            if (!ipv4Config.gateway().isEmpty())
                details[QStringLiteral("gateway")] = ipv4Config.gateway();

            QVariantList dnsList;
            for (const auto& ns : ipv4Config.nameservers())
                dnsList.append(ns.toString());
            details[QStringLiteral("dns")] = dnsList;
        }
        break;
    }

    if (m_wirelessDeviceDetails != details) {
        m_wirelessDeviceDetails = details;
        emit wirelessDeviceDetailsChanged();
    }
}

void NmQt::refreshEthernetDeviceDetails(const QString& interfaceName) {
    NetworkManager::Device::Ptr ethDev;
    if (!interfaceName.isEmpty()) {
        ethDev = NetworkManager::findNetworkInterface(interfaceName);
        if (!ethDev)
            ethDev = NetworkManager::findDeviceByIpFace(interfaceName);
    } else {
        for (const auto& dev : NetworkManager::networkInterfaces()) {
            if (dev && dev->type() == NetworkManager::Device::Ethernet &&
                dev->state() == NetworkManager::Device::State::Activated) {
                ethDev = dev;
                break;
            }
        }
    }

    if (!ethDev) {
        m_ethernetDeviceDetails = {};
        emit ethernetDeviceDetailsChanged();
        return;
    }

    QVariantMap details;
    details[QStringLiteral("ipAddress")] = {};
    details[QStringLiteral("gateway")] = {};
    details[QStringLiteral("dns")] = QVariantList();
    details[QStringLiteral("subnet")] = {};
    const auto wiredDev = ethDev.dynamicCast<NetworkManager::WiredDevice>();
    details[QStringLiteral("macAddress")] = wiredDev ? wiredDev->hardwareAddress() : QString();

    const auto activeConns = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activeConns) {
        auto ac = NetworkManager::findActiveConnection(path);
        if (!ac || !ac->devices().contains(ethDev->uni()))
            continue;

        auto ipv4Config = ac->ipV4Config();
        if (ipv4Config.isValid()) {
            if (!ipv4Config.addresses().isEmpty()) {
                const auto addr = ipv4Config.addresses().first();
                details[QStringLiteral("ipAddress")] = addr.ip().toString();
                details[QStringLiteral("subnet")] = addr.netmask().toString();
            }
            if (!ipv4Config.gateway().isEmpty())
                details[QStringLiteral("gateway")] = ipv4Config.gateway();

            QVariantList dnsList;
            for (const auto& ns : ipv4Config.nameservers())
                dnsList.append(ns.toString());
            details[QStringLiteral("dns")] = dnsList;
        }
        break;
    }

    if (m_ethernetDeviceDetails != details) {
        m_ethernetDeviceDetails = details;
        emit ethernetDeviceDetailsChanged();
    }
}

QVariantMap NmQt::buildApMap(
    const QString& ssid, const QString& bssid, int strength, int frequency, bool active, const QString& security) {
    QVariantMap map;
    map[QStringLiteral("ssid")] = ssid;
    map[QStringLiteral("bssid")] = bssid;
    map[QStringLiteral("strength")] = strength;
    map[QStringLiteral("frequency")] = frequency;
    map[QStringLiteral("active")] = active;
    map[QStringLiteral("security")] = security;
    map[QStringLiteral("isSecure")] = !security.isEmpty();
    return map;
}

void NmQt::invokeCallback(
    QJSValue callback, bool success, const QString& output, const QString& error, int exitCode, bool needsPassword) {
    if (!callback.isCallable())
        return;

    auto* engine = qjsEngine(this);
    if (!engine)
        return;

    auto result = engine->newObject();
    result.setProperty(QStringLiteral("success"), success);
    result.setProperty(QStringLiteral("output"), output);
    result.setProperty(QStringLiteral("error"), error);
    result.setProperty(QStringLiteral("exitCode"), exitCode);
    result.setProperty(QStringLiteral("needsPassword"), needsPassword);

    callback.call({ result });
}

} // namespace caelestia::services
