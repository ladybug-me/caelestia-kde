// SPDX-License-Identifier: GPL-3.0-only
#include "brightnesswatcher.hpp"

#include <qloggingcategory.h>
#include <qpa/qplatformnativeinterface.h>

#include <QGuiApplication>

Q_LOGGING_CATEGORY(lcBrightnessWatcher, "caelestia.services.brightnesswatcher", QtInfoMsg)

namespace caelestia::services {

KdeOutputDevice::KdeOutputDevice(struct ::kde_output_device_v2* object)
    : QtWayland::kde_output_device_v2(object) {}

KdeOutputDevice::~KdeOutputDevice() {}

void KdeOutputDevice::kde_output_device_v2_name(const QString& name) {
    if (m_name != name) {
        m_name = name;
        emit nameChanged();
    }
}

void KdeOutputDevice::kde_output_device_v2_brightness(uint32_t brightness) {
    if (m_brightness != brightness) {
        m_brightness = brightness;
        emit brightnessChanged();
    }
}

void KdeOutputDevice::kde_output_device_v2_capabilities(uint32_t flags) {
    bool has = (flags & capability_brightness);
    if (m_hasBrightness != has) {
        m_hasBrightness = has;
    }
}

void KdeOutputDevice::kde_output_device_v2_removed() {
    emit removed();
}

KdeOutputDeviceRegistry::KdeOutputDeviceRegistry(QObject* parent)
    : QWaylandClientExtensionTemplate<KdeOutputDeviceRegistry>(23) {}

void KdeOutputDeviceRegistry::kde_output_device_registry_v2_output(struct ::kde_output_device_v2* output) {
    auto* dev = new KdeOutputDevice(output);
    emit deviceAdded(dev);
}

KdeOutputManagement::KdeOutputManagement(QObject* parent)
    : QWaylandClientExtensionTemplate<KdeOutputManagement>(21) {}

BrightnessWatcher::BrightnessWatcher(QObject* parent)
    : QObject(parent) {
    m_registry = new KdeOutputDeviceRegistry(this);
    connect(m_registry, &KdeOutputDeviceRegistry::deviceAdded, this, &BrightnessWatcher::onDeviceAdded);

    m_management = new KdeOutputManagement(this);

    // QtWayland requires us to explicitly check if the extension was successfully bound.
    // However, it binds asynchronously. If QGuiApplication is already running, it binds immediately.
}

qreal BrightnessWatcher::brightness(const QString& outputName) const {
    if (m_devices.contains(outputName)) {
        auto* dev = m_devices[outputName];
        if (dev->hasBrightness()) {
            return dev->brightness() / 10000.0;
        }
    }
    return -1.0;
}

void BrightnessWatcher::setBrightness(const QString& outputName, qreal value) {
    if (!m_management->isInitialized()) {
        qCWarning(lcBrightnessWatcher) << "Cannot set brightness: kde_output_management_v2 is not available.";
        return;
    }

    if (!m_devices.contains(outputName)) {
        qCWarning(lcBrightnessWatcher) << "Cannot set brightness: unknown output" << outputName;
        return;
    }

    auto* dev = m_devices[outputName];
    if (!dev->hasBrightness()) {
        qCWarning(lcBrightnessWatcher) << "Cannot set brightness: output" << outputName
                                       << "does not support brightness";
        return;
    }

    value = qBound(0.0, value, 1.0);
    uint32_t brightValue = qRound(value * 10000.0);

    auto* config = m_management->create_configuration();
    if (!config)
        return;

    QtWayland::kde_output_configuration_v2 cfg(config);
    cfg.set_brightness(dev->object(), brightValue);
    cfg.apply();
    cfg.destroy();
}

void BrightnessWatcher::onDeviceAdded(KdeOutputDevice* device) {
    connect(device, &KdeOutputDevice::nameChanged, this, [this, device]() {
        if (!device->name().isEmpty()) {
            m_devices[device->name()] = device;

            connect(device, &KdeOutputDevice::brightnessChanged, this, [this, device]() {
                emit brightnessChanged(device->name(), device->brightness() / 10000.0);
            });
        }
    });

    connect(device, &KdeOutputDevice::removed, this, [this, device]() {
        if (!device->name().isEmpty()) {
            m_devices.remove(device->name());
        }
        device->deleteLater();
    });
}

} // namespace caelestia::services
