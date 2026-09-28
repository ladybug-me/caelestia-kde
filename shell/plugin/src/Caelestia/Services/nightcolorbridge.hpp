#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>
#include <QtDBus/QDBusConnection>

namespace caelestia::services {

class NightColorBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(int currentTemperature READ currentTemperature NOTIFY currentTemperatureChanged)
    Q_PROPERTY(int dayTemperature READ dayTemperature WRITE setDayTemperature NOTIFY dayTemperatureChanged)
    Q_PROPERTY(int nightTemperature READ nightTemperature WRITE setNightTemperature NOTIFY nightTemperatureChanged)
    Q_PROPERTY(bool autoMode READ autoMode NOTIFY autoModeChanged)
    Q_PROPERTY(bool available READ available CONSTANT)
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit NightColorBridge(QObject* parent = nullptr);
    ~NightColorBridge() override;

    bool active() const;
    int currentTemperature() const;
    int dayTemperature() const;
    int nightTemperature() const;
    bool autoMode() const;
    bool available() const;

    Q_INVOKABLE void setDayTemperature(int temp);
    Q_INVOKABLE void setNightTemperature(int temp);
    Q_INVOKABLE void previewTemperature(int temp);
    Q_INVOKABLE void stopPreview();
    Q_INVOKABLE void toggleAutoMode();
    Q_INVOKABLE void toggleNightLight();

signals:
    void activeChanged();
    void currentTemperatureChanged();
    void dayTemperatureChanged();
    void nightTemperatureChanged();
    void autoModeChanged();

private slots:
    void onPropertiesChanged(
        const QString& interface, const QVariantMap& changedProps, const QStringList& invalidatedProps);

private:
    void fetchInitialState();
    void updateState(const QVariantMap& config);
    void writeConfig(const QStringList& args);

    bool m_active = false;
    int m_currentTemperature = 0;
    int m_dayTemperature = 6500;
    int m_nightTemperature = 4500;
    bool m_available = false;
    bool m_autoMode = false;
};

} // namespace caelestia::services
