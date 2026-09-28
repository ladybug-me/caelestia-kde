// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QtQml/qqml.h>

#include <QHash>
#include <QObject>
#include <QString>
#include <QtWaylandClient/QWaylandClientExtension>

#include "qwayland-kde-output-device-v2.h"
#include "qwayland-kde-output-management-v2.h"

namespace caelestia::services {

class KdeOutputDevice : public QObject, public QtWayland::kde_output_device_v2 {
    Q_OBJECT

public:
    explicit KdeOutputDevice(struct ::kde_output_device_v2* object);
    ~KdeOutputDevice() override;

    QString name() const { return m_name; }

    uint32_t brightness() const { return m_brightness; }

    bool hasBrightness() const { return m_hasBrightness; }

signals:
    void nameChanged();
    void brightnessChanged();
    void removed();

protected:
    void kde_output_device_v2_name(const QString& name) override;
    void kde_output_device_v2_brightness(uint32_t brightness) override;
    void kde_output_device_v2_capabilities(uint32_t flags) override;
    void kde_output_device_v2_removed() override;

private:
    QString m_name;
    uint32_t m_brightness = 0;
    bool m_hasBrightness = false;
};

class KdeOutputDeviceRegistry : public QWaylandClientExtensionTemplate<KdeOutputDeviceRegistry>,
                                public QtWayland::kde_output_device_registry_v2 {
    Q_OBJECT

public:
    explicit KdeOutputDeviceRegistry(QObject* parent = nullptr);

signals:
    void deviceAdded(KdeOutputDevice* device);

protected:
    void kde_output_device_registry_v2_output(struct ::kde_output_device_v2* output) override;
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
    Q_INVOKABLE void setBrightness(const QString& outputName, qreal value);

signals:
    void brightnessChanged(const QString& outputName, qreal value);

private slots:
    void onDeviceAdded(KdeOutputDevice* device);

private:
    KdeOutputDeviceRegistry* m_registry = nullptr;
    KdeOutputManagement* m_management = nullptr;
    QHash<QString, KdeOutputDevice*> m_devices;
};

} // namespace caelestia::services
