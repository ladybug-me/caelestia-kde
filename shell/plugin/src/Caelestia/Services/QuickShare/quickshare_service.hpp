#pragma once

#include <qqmlintegration.h>

#include <QObject>
#include <QPointer>
#include <QTcpServer>
#include <QVariantList>
#include <QVariantMap>

#include "QuickShareBle.hpp"
#include "QuickShareConnection.hpp"
#include "QuickShareDiscovery.hpp"

namespace caelestia::services {

class QuickShareService : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    /// Whether Quick Share is on. Turning it on also makes this shell visible to
    /// nearby devices.
    Q_PROPERTY(bool isEnabled READ isEnabled WRITE setEnabled NOTIFY isEnabledChanged)
    /// Whether this shell advertises itself. Only meaningful while enabled: it can
    /// be turned off to stay reachable without being discoverable.
    Q_PROPERTY(bool isVisible READ isVisible WRITE setVisible NOTIFY isVisibleChanged)
    Q_PROPERTY(int listenPort READ listenPort CONSTANT)
    Q_PROPERTY(QVariantList nearbyDevices READ nearbyDevices NOTIFY nearbyDevicesChanged)
    Q_PROPERTY(QVariantList transferHistory READ transferHistory NOTIFY transferHistoryChanged)

public:
    explicit QuickShareService(QObject* parent = nullptr);
    ~QuickShareService() override;

    bool isEnabled() const;
    void setEnabled(bool enabled);

    bool isVisible() const;
    void setVisible(bool visible);

    int listenPort() const;

    QVariantList nearbyDevices() const;
    /// Each entry is { direction: "sent" | "received", fileName, filePath, deviceName, timestamp }.
    QVariantList transferHistory() const;

    Q_INVOKABLE void sendFile(const QString& deviceId, const QString& filePath);
    Q_INVOKABLE void acceptIncomingTransfer();
    Q_INVOKABLE void rejectIncomingTransfer();
    Q_INVOKABLE void clearHistory();
    /// Removes the entry naming this file and timestamp. Every transfer reorders the
    /// list, so a position is not a stable way to name one.
    Q_INVOKABLE void removeHistoryEntry(const QString& filePath, qint64 timestamp);

    Q_INVOKABLE void startBleWakeupBroadcast();
    Q_INVOKABLE void stopBleWakeupBroadcast();

signals:
    void isEnabledChanged();
    void isVisibleChanged();
    void nearbyDevicesChanged();
    void transferHistoryChanged();

    void errorOccurred(const QString& message);

    // UI notifications
    void incomingTransferRequested(const QString& deviceName, const QString& fileName, qint64 fileSize);
    void incomingTransferPinReady(const QString& pinCode);
    void outgoingTransferProgress(const QString& deviceId, qint64 bytesSent, qint64 bytesTotal);
    /// The transfer this shell started with `deviceId` ended.
    void outgoingTransferFinished(const QString& deviceId, bool success);
    /// The transfer a nearby device started with this shell ended.
    void incomingTransferFinished(bool success);

private slots:
    void onDeviceFound(const QuickShareDevice& device);
    void onDeviceLost(const QString& deviceId);
    void onNewConnection();
    void loadHistory();
    void saveHistory();

private:
    /// Files a finished transfer at the top of the history and persists it.
    void appendHistoryEntry(
        const QString& direction, const QString& fileName, const QString& filePath, const QString& deviceName);

    bool m_isEnabled = false;
    bool m_isVisible = false;

    QuickShareDiscovery* m_discovery;
    QuickShareBleAdvertiser* m_bleAdvertiser;
    QuickShareBleScanner* m_bleScanner;
    QTcpServer* m_server;

    QList<QuickShareDevice> m_devices;
    QVariantList m_transferHistory;

    /// The incoming request the shell can still answer. Every connection is owned by
    /// this object and tracked by the handlers that created it.
    QPointer<QuickShareConnection> m_pendingIncomingRequest;
};

} // namespace caelestia::services
