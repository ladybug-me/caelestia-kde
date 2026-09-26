#pragma once

#include <qprocess.h>
#include <qqmlintegration.h>

#include "tickingservice.hpp"

namespace caelestia::services {

class Gpu : public TickingService {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    enum Type {
        Auto,    // user override is empty (config "") — defer to detected autoType
        None,    // no usable GPU
        Nvidia,  // queried via nvidia-smi, gated on the card's runtime power state
        Generic, // queried via /sys/class/drm/card*/device/gpu_busy_percent
    };
    Q_ENUM(Type)

private:
    Q_PROPERTY(Type type READ type NOTIFY typeChanged)
    Q_PROPERTY(Type userType READ userType NOTIFY userTypeChanged)
    Q_PROPERTY(Type autoType READ autoType NOTIFY autoTypeChanged)
    Q_PROPERTY(QString name READ name NOTIFY nameChanged)
    Q_PROPERTY(qreal percentage READ percentage NOTIFY percentageChanged)
    Q_PROPERTY(qreal temperature READ temperature NOTIFY temperatureChanged)

public:
    explicit Gpu(QObject* parent = nullptr);

    [[nodiscard]] Type type() const;
    [[nodiscard]] Type userType() const;
    [[nodiscard]] Type autoType() const;
    [[nodiscard]] QString name() const;
    [[nodiscard]] qreal percentage() const;
    [[nodiscard]] qreal temperature() const;

signals:
    void typeChanged();
    void userTypeChanged();
    void autoTypeChanged();
    void nameChanged();
    void percentageChanged();
    void temperatureChanged();

protected:
    void tick() override;

private:
    void detectGpu();
    void finishLspciProbe(const QByteArray& out);
    void probeNvidiaCapability();
    void tryNameSource(int index);
    void finishNameSource(int index, QString name);
    void readGenericUsage();
    void startNvidiaUsage();
    void readGpuTemperature();
    void resetReadings();

    // Runs a one-shot process, delivering its stdout to callback exactly once
    // (empty output if it crashes or never starts), then tears the process down.
    void runProcess(const QString& program, const QStringList& args, std::function<void(const QByteArray&)> callback);

    void setUserType(Type value);
    void setAutoType(Type value);
    void setName(QString value);

    [[nodiscard]] static Type parseType(const QString& s);

    Type m_userType = Auto;
    Type m_autoType = None;
    QString m_name;
    qreal m_percentage = 0.0;
    qreal m_temperature = 0.0;

    // /sys/class/drm card busy files, enumerated once at construction (the card
    // set is static at runtime) and reused by detection and the tick path.
    QStringList m_busyFiles;

    // sysfs path of the NVIDIA PCI device, resolved from lspci output during
    // detection. Its runtime power state decides whether a tick may spawn
    // nvidia-smi: reading the state never wakes the card, spawning the tool
    // does. Empty when unknown, which keeps the old always-query behaviour.
    QString m_nvidiaPciPath;

    // Consecutive nvidia-smi queries that returned nothing. Two in a row
    // demote an auto-detected Nvidia back to the generic readers, matching
    // what the old detection chain concluded when the probe failed.
    int m_nvidiaFailures = 0;

    bool m_detecting = false;
    bool m_nvidiaQuerying = false;
};

} // namespace caelestia::services
