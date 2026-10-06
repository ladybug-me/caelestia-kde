// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <qqmlintegration.h>

#include <NetworkManagerQt/ConnectionSettings>
#include <NetworkManagerQt/WirelessDevice>
#include <QJSValue>
#include <QObject>
#include <QString>
#include <optional>

namespace caelestia::services {

class HotspotController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("HotspotController is created by NmQt")

    Q_PROPERTY(QString profileId READ profileId CONSTANT)
    Q_PROPERTY(bool supported READ supported NOTIFY stateChanged)
    Q_PROPERTY(bool enabled READ enabled NOTIFY stateChanged)
    Q_PROPERTY(QString ssid READ ssid NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int minPasswordLength READ minPasswordLength CONSTANT)

public:
    explicit HotspotController(QObject* parent = nullptr);

    QString profileId() const;
    bool supported() const;
    bool enabled() const;
    QString ssid() const;
    bool busy() const;
    int minPasswordLength() const;

    void refresh();

    Q_INVOKABLE void enable(const QString& ssid, const QString& password, QJSValue callback = {});
    Q_INVOKABLE void disable(QJSValue callback = {});

signals:
    void stateChanged();
    void busyChanged();
    void profileAdded();

private:
    struct Active {
        QString path;
        QString ssid;
    };

    static NetworkManager::WirelessDevice::Ptr accessPointDevice();
    static std::optional<Active> active();
    static NMVariantMapMap buildSettings(const QString& ssid, const QString& password, const QString& uuid);

    void setBusy(bool busy);
    void finish(QJSValue callback, bool success, const QString& output, const QString& error);

    bool m_busy = false;
};

} // namespace caelestia::services
