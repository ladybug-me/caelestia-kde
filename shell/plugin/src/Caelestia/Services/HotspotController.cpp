// SPDX-License-Identifier: GPL-3.0-only
#include "HotspotController.hpp"

#include <NetworkManagerQt/ActiveConnection>
#include <NetworkManagerQt/Connection>
#include <NetworkManagerQt/Ipv4Setting>
#include <NetworkManagerQt/Manager>
#include <NetworkManagerQt/Settings>
#include <NetworkManagerQt/WirelessSecuritySetting>
#include <NetworkManagerQt/WirelessSetting>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJSEngine>
#include <QQmlEngine>

namespace caelestia::services {

namespace {

constexpr QLatin1String hotspotProfileId("caelestia-hotspot");

} // namespace

HotspotController::HotspotController(QObject* parent)
    : QObject(parent) {}

QString HotspotController::profileId() const {
    return hotspotProfileId;
}

bool HotspotController::supported() const {
    return !accessPointDevice().isNull();
}

bool HotspotController::enabled() const {
    return active().has_value();
}

QString HotspotController::ssid() const {
    const auto up = active();
    return up ? up->ssid : QString();
}

bool HotspotController::busy() const {
    return m_busy;
}

int HotspotController::minPasswordLength() const {
    return 8;
}

void HotspotController::refresh() {
    emit stateChanged();
}

NetworkManager::WirelessDevice::Ptr HotspotController::accessPointDevice() {
    for (const auto& dev : NetworkManager::networkInterfaces()) {
        const auto wd = dev.dynamicCast<NetworkManager::WirelessDevice>();
        if (wd && wd->wirelessCapabilities().testFlag(NetworkManager::WirelessDevice::ApCap))
            return wd;
    }
    return {};
}

std::optional<HotspotController::Active> HotspotController::active() {
    const auto device = accessPointDevice();
    if (!device)
        return std::nullopt;

    const QString deviceUni = device->uni();
    const auto activePaths = NetworkManager::activeConnectionsPaths();
    for (const auto& path : activePaths) {
        const auto ac = NetworkManager::findActiveConnection(path);
        if (!ac || !ac->devices().contains(deviceUni))
            continue;

        const auto conn = ac->connection();
        const auto connSettings = conn ? conn->settings() : NetworkManager::ConnectionSettings::Ptr();
        if (!connSettings)
            continue;

        const auto ws = connSettings->setting(NetworkManager::Setting::SettingType::Wireless)
                            .dynamicCast<NetworkManager::WirelessSetting>();
        if (ws && ws->mode() == NetworkManager::WirelessSetting::Ap)
            return Active{ path, QString::fromUtf8(ws->ssid()) };
    }
    return std::nullopt;
}

NMVariantMapMap HotspotController::buildSettings(const QString& ssid, const QString& password, const QString& uuid) {
    NetworkManager::ConnectionSettings settings(NetworkManager::ConnectionSettings::Wireless);
    settings.setId(hotspotProfileId);
    settings.setUuid(uuid);
    settings.setAutoconnect(false);

    const auto wireless =
        settings.setting(NetworkManager::Setting::SettingType::Wireless).dynamicCast<NetworkManager::WirelessSetting>();
    const auto ipv4 =
        settings.setting(NetworkManager::Setting::SettingType::Ipv4).dynamicCast<NetworkManager::Ipv4Setting>();

    wireless->setSsid(ssid.toUtf8());
    wireless->setMode(NetworkManager::WirelessSetting::Ap);
    wireless->setBand(NetworkManager::WirelessSetting::Bg);
    wireless->setInitialized(true);

    if (!password.isEmpty()) {
        const auto security = settings.setting(NetworkManager::Setting::SettingType::WirelessSecurity)
                                  .dynamicCast<NetworkManager::WirelessSecuritySetting>();
        security->setKeyMgmt(NetworkManager::WirelessSecuritySetting::WpaPsk);
        security->setPsk(password);
        security->setInitialized(true);
        wireless->setSecurity(security->name());
    }

    ipv4->setMethod(NetworkManager::Ipv4Setting::Shared);
    ipv4->setInitialized(true);

    return settings.toMap();
}

void HotspotController::setBusy(bool value) {
    if (m_busy == value)
        return;
    m_busy = value;
    emit busyChanged();
}

void HotspotController::finish(QJSValue callback, bool success, const QString& output, const QString& error) {
    setBusy(false);
    refresh();

    if (!callback.isCallable())
        return;

    auto* engine = qjsEngine(this);
    if (!engine)
        return;

    auto result = engine->newObject();
    result.setProperty(QStringLiteral("success"), success);
    result.setProperty(QStringLiteral("output"), output);
    result.setProperty(QStringLiteral("error"), error);
    result.setProperty(QStringLiteral("exitCode"), success ? 0 : -1);
    callback.call({ result });
}

void HotspotController::enable(const QString& ssid, const QString& password, QJSValue callback) {
    if (m_busy) {
        finish(callback, false, {}, QStringLiteral("A hotspot change is already in flight"));
        return;
    }

    const auto wifiDev = accessPointDevice();
    if (!wifiDev) {
        finish(callback, false, {}, QStringLiteral("No wireless device can run a hotspot"));
        return;
    }

    const QString name = ssid.trimmed();
    if (name.isEmpty()) {
        finish(callback, false, {}, QStringLiteral("The hotspot needs a name"));
        return;
    }
    if (!password.isEmpty() && password.size() < minPasswordLength()) {
        finish(callback, false, {}, QStringLiteral("A hotspot password is either empty or at least 8 characters"));
        return;
    }

    NetworkManager::Connection::Ptr existing;
    for (const auto& conn : NetworkManager::listConnections()) {
        if (conn && conn->settings() && conn->settings()->id() == hotspotProfileId) {
            existing = conn;
            break;
        }
    }

    const NMVariantMapMap settings = buildSettings(
        name, password, existing ? existing->uuid() : NetworkManager::ConnectionSettings::createNewUuid());

    setBusy(true);

    if (existing) {
        QDBusPendingReply<> reply = existing->update(settings);
        auto* watcher = new QDBusPendingCallWatcher(reply, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, wifiDev, existing, callback](QDBusPendingCallWatcher* w) {
                w->deleteLater();
                QDBusPendingReply<> r = *w;
                if (r.isError()) {
                    finish(callback, false, {}, r.error().message());
                    return;
                }

                QDBusPendingReply<QDBusObjectPath> activateReply =
                    NetworkManager::activateConnection(existing->path(), wifiDev->uni(), QString());
                auto* activateWatcher = new QDBusPendingCallWatcher(activateReply, this);
                connect(activateWatcher, &QDBusPendingCallWatcher::finished, this,
                    [this, callback](QDBusPendingCallWatcher* aw) {
                        aw->deleteLater();
                        QDBusPendingReply<QDBusObjectPath> ar = *aw;
                        if (ar.isError()) {
                            finish(callback, false, {}, ar.error().message());
                            return;
                        }
                        finish(callback, true, QStringLiteral("Hotspot started"), {});
                    });
            });
        return;
    }

    QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> reply =
        NetworkManager::addAndActivateConnection(settings, wifiDev->uni(), QString());
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> r = *w;
        if (r.isError()) {
            finish(callback, false, {}, r.error().message());
            return;
        }
        emit profileAdded();
        finish(callback, true, QStringLiteral("Hotspot started"), {});
    });
}

void HotspotController::disable(QJSValue callback) {
    if (m_busy) {
        finish(callback, false, {}, QStringLiteral("A hotspot change is already in flight"));
        return;
    }

    const auto up = active();
    if (!up) {
        finish(callback, true, QStringLiteral("Hotspot is already off"), {});
        return;
    }

    setBusy(true);

    QDBusPendingReply<> reply = NetworkManager::deactivateConnection(up->path);
    auto* watcher = new QDBusPendingCallWatcher(reply, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, callback](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        QDBusPendingReply<> r = *w;
        if (r.isError()) {
            finish(callback, false, {}, r.error().message());
            return;
        }
        finish(callback, true, QStringLiteral("Hotspot stopped"), {});
    });
}

} // namespace caelestia::services
