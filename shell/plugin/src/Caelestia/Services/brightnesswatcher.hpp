// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QtQml/qqml.h>

#include <QHash>
#include <QObject>
#include <QString>
#include <QtWaylandClient/QWaylandClientExtension>

#include "qwayland-kde-output-device-v2.h"
#include "qwayland-kde-output-management-v2.h"

struct wl_registry;

namespace caelestia::services {

class KdeOutputDevice : public QObject, public QtWayland::kde_output_device_v2 {
    Q_OBJECT

public:
    explicit KdeOutputDevice(struct ::kde_output_device_v2* object);
    KdeOutputDevice(struct ::wl_registry* registry, uint32_t name, int version);
    ~KdeOutputDevice() override;

    QString name() const { return m_name; }

    uint32_t brightness() const { return m_brightness; }

    uint32_t dimming() const { return m_dimming; }

    bool hasBrightness() const { return m_hasBrightness; }

    void notifyRemoved();

signals:
    void nameChanged();
    void brightnessChanged();
    void dimmingChanged();
    void removed();

protected:
    void kde_output_device_v2_name(const QString& name) override;
    void kde_output_device_v2_brightness(uint32_t brightness) override;
    void kde_output_device_v2_dimming(uint32_t multiplier) override;
    void kde_output_device_v2_capabilities(uint32_t flags) override;
    void kde_output_device_v2_removed() override;

private:
    QString m_name;
    uint32_t m_brightness = 0;
    uint32_t m_dimming = 10000;
    bool m_hasBrightness = false;
};

class KdeOutputDeviceRegistry : public QObject, public QtWayland::kde_output_device_registry_v2 {
    Q_OBJECT

public:
    explicit KdeOutputDeviceRegistry(QObject* parent = nullptr);
    ~KdeOutputDeviceRegistry() override;

signals:
    void deviceAdded(KdeOutputDevice* device);

protected:
    void kde_output_device_registry_v2_output(struct ::kde_output_device_v2* output) override;

private:
    static void handleGlobal(
        void* data, struct ::wl_registry* registry, uint32_t name, const char* interface, uint32_t version);
    static void handleGlobalRemove(void* data, struct ::wl_registry* registry, uint32_t name);

    struct ::wl_registry* m_registry = nullptr;
    QHash<uint32_t, KdeOutputDevice*> m_globalDevices;
};

class KdeOutputManagement : public QWaylandClientExtensionTemplate<KdeOutputManagement>,
                            public QtWayland::kde_output_management_v2 {
    Q_OBJECT

public:
    explicit KdeOutputManagement(QObject* parent = nullptr);
};

class BrightnessWatcher : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit BrightnessWatcher(QObject* parent = nullptr);

    Q_INVOKABLE qreal brightness(const QString& outputName) const;
    // Also asserts full dimming, in the same configuration: a brightness request is user
    // activity, and a multiplier KWin left behind must not swallow it (KDE bug 513809).
    Q_INVOKABLE void setBrightness(const QString& outputName, qreal value);
    Q_INVOKABLE qreal dimming(const QString& outputName) const;

signals:
    void brightnessChanged(const QString& outputName, qreal value);
    void dimmingChanged(const QString& outputName, qreal value);

private slots:
    void onDeviceAdded(KdeOutputDevice* device);

private:
    KdeOutputDeviceRegistry* m_registry = nullptr;
    KdeOutputManagement* m_management = nullptr;
    QHash<QString, KdeOutputDevice*> m_devices;
};

} // namespace caelestia::services
