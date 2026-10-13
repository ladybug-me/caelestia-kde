// SPDX-License-Identifier: GPL-3.0-only
#include "brightnesswatcher.hpp"

#include <QtGui/qguiapplication_platform.h>
#include <qloggingcategory.h>
#include <qpa/qplatformnativeinterface.h>

#include <wayland-client.h>

#include <QGuiApplication>
#include <cstring>

Q_LOGGING_CATEGORY(lcBrightnessWatcher, "caelestia.services.brightnesswatcher", QtInfoMsg)

namespace caelestia::services {

KdeOutputDevice::KdeOutputDevice(struct ::kde_output_device_v2* object)
    : QtWayland::kde_output_device_v2(object) {}

KdeOutputDevice::KdeOutputDevice(struct ::wl_registry* registry, uint32_t name, int version)
    : QtWayland::kde_output_device_v2(registry, name, version) {}

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

void KdeOutputDevice::kde_output_device_v2_dimming(uint32_t multiplier) {
    if (m_dimming != multiplier) {
        m_dimming = multiplier;
        emit dimmingChanged();
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

void KdeOutputDevice::notifyRemoved() {
    emit removed();
}

KdeOutputDeviceRegistry::KdeOutputDeviceRegistry(QObject* parent)
    : QObject(parent) {
    auto* wayland = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
    struct ::wl_display* display = wayland ? wayland->display() : nullptr;
    if (!display) {
        qCWarning(lcBrightnessWatcher) << "Cannot discover outputs: no Wayland display";
        return;
    }

    m_registry = wl_display_get_registry(display);
    static const struct ::wl_registry_listener listener = {
        &KdeOutputDeviceRegistry::handleGlobal,
        &KdeOutputDeviceRegistry::handleGlobalRemove,
    };
    wl_registry_add_listener(m_registry, &listener, this);
}

KdeOutputDeviceRegistry::~KdeOutputDeviceRegistry() {
    for (auto* dev : m_globalDevices)
        delete dev;
    if (m_registry)
        wl_registry_destroy(m_registry);
}

void KdeOutputDeviceRegistry::handleGlobal(
    void* data, struct ::wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
    auto* self = static_cast<KdeOutputDeviceRegistry*>(data);

    if (std::strcmp(interface, "kde_output_device_v2") == 0) {
        const auto v =
            qMin<uint32_t>(version, static_cast<uint32_t>(QtWayland::kde_output_device_v2::interface()->version));
        auto* dev = new KdeOutputDevice(registry, name, static_cast<int>(v));
        self->m_globalDevices.insert(name, dev);
        emit self->deviceAdded(dev);
    } else if (std::strcmp(interface, "kde_output_device_registry_v2") == 0) {
        const auto v = qMin<uint32_t>(
            version, static_cast<uint32_t>(QtWayland::kde_output_device_registry_v2::interface()->version));
        self->QtWayland::kde_output_device_registry_v2::init(registry, name, static_cast<int>(v));
    }
}

void KdeOutputDeviceRegistry::handleGlobalRemove(void* data, struct ::wl_registry* registry, uint32_t name) {
    Q_UNUSED(registry);
    auto* self = static_cast<KdeOutputDeviceRegistry*>(data);
    if (auto* dev = self->m_globalDevices.take(name))
        dev->notifyRemoved();
}

void KdeOutputDeviceRegistry::kde_output_device_registry_v2_output(struct ::kde_output_device_v2* output) {
    emit deviceAdded(new KdeOutputDevice(output));
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
    auto* dev = m_devices.value(outputName);
    return dev && dev->hasBrightness() ? dev->brightness() / 10000.0 : -1.0;
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
    // Assert full dimming in the same configuration: asking for a brightness change is user
    // activity, and a multiplier KWin left behind would otherwise swallow it while everything
    // the shell can read still looks right (KDE bug 513809).
    cfg.set_dimming(dev->object(), 10000);
    cfg.apply();
    cfg.destroy();
}

qreal BrightnessWatcher::dimming(const QString& outputName) const {
    auto* dev = m_devices.value(outputName);
    return dev && dev->hasBrightness() ? dev->dimming() / 10000.0 : -1.0;
}

void BrightnessWatcher::onDeviceAdded(KdeOutputDevice* device) {
    connect(device, &KdeOutputDevice::nameChanged, this, [this, device]() {
        if (!device->name().isEmpty()) {
            m_devices[device->name()] = device;

            connect(device, &KdeOutputDevice::brightnessChanged, this, [this, device]() {
                emit brightnessChanged(device->name(), device->brightness() / 10000.0);
            });

            connect(device, &KdeOutputDevice::dimmingChanged, this, [this, device]() {
                emit dimmingChanged(device->name(), device->dimming() / 10000.0);
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
