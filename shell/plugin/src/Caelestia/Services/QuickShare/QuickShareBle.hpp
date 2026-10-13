#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDateTime>
#include <QMap>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace caelestia::services {

/// The org.bluez.LEAdvertisement1 object BlueZ asks the shell to expose while it
/// advertises a Quick Share wakeup beacon.
class QuickShareBleAdvertisementAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.LEAdvertisement1")
    Q_PROPERTY(QString Type READ type)
    Q_PROPERTY(QStringList ServiceUUIDs READ serviceUUIDs)
    Q_PROPERTY(QVariantMap ServiceData READ serviceData)

public:
    explicit QuickShareBleAdvertisementAdaptor(QObject* parent);

    QString type() const;

    QStringList serviceUUIDs() const;

    QVariantMap serviceData() const;

public slots:
    void Release();
};

class QuickShareBleAdvertiser : public QObject {
    Q_OBJECT

public:
    explicit QuickShareBleAdvertiser(QObject* parent = nullptr);
    ~QuickShareBleAdvertiser() override;

    Q_INVOKABLE void startAdvertising();
    Q_INVOKABLE void stopAdvertising();

private slots:
    void onGetManagedObjectsFinished(const QDBusMessage& reply);
    void onRegisterAdvertisementFinished(const QDBusMessage& reply);

private:
    QString m_objectPath;
    bool m_isAdvertising;
    QString m_adapterPath;
};

class QuickShareBleScanner : public QObject {
    Q_OBJECT

public:
    explicit QuickShareBleScanner(QObject* parent = nullptr);
    ~QuickShareBleScanner() override;

    Q_INVOKABLE void startScanning();
    Q_INVOKABLE void stopScanning();

signals:
    void deviceFound(const QString& address, const QByteArray& data);

private slots:
    void onGetManagedObjectsFinished(const QDBusMessage& reply);
    void onSetDiscoveryFilterFinished(const QDBusMessage& reply);
    void onStartDiscoveryFinished(const QDBusMessage& reply);
    void onInterfacesAdded(
        const QDBusObjectPath& objectPath, const QMap<QString, QVariantMap>& interfacesAndProperties);
    void onPropertiesChanged(
        const QString& interface, const QVariantMap& changedProperties, const QStringList& invalidatedProperties);
    void checkDeviceProperties(const QVariantMap& deviceProperties);

private:
    QString m_adapterPath;
    bool m_isScanning;
    QDateTime m_lastEmit;
};

} // namespace caelestia::services
