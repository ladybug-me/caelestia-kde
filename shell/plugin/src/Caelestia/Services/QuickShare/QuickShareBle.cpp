#include "QuickShareBle.hpp"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>

using Qt::StringLiterals::operator""_s;

namespace caelestia::services {

namespace {

/// Pulls the first object path carrying `interface` out of an ObjectManager reply.
QString findAdapterPath(const QDBusMessage& reply, const QString& interface) {
    if (reply.arguments().isEmpty())
        return {};

    const QDBusArgument argument = reply.arguments().at(0).value<QDBusArgument>();
    QMap<QDBusObjectPath, QMap<QString, QVariantMap>> objects;
    argument >> objects;

    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        if (it.value().contains(interface))
            return it.key().path();
    }
    return {};
}

} // namespace

// --------------------------------------------------------------------------------
// QuickShareBleAdvertisementAdaptor
// --------------------------------------------------------------------------------

QuickShareBleAdvertisementAdaptor::QuickShareBleAdvertisementAdaptor(QObject* parent)
    : QDBusAbstractAdaptor(parent) {}

QString QuickShareBleAdvertisementAdaptor::type() const {
    return u"broadcast"_s;
}

QStringList QuickShareBleAdvertisementAdaptor::serviceUUIDs() const {
    return { u"0000fe2c-0000-1000-8000-00805f9b34fb"_s };
}

QVariantMap QuickShareBleAdvertisementAdaptor::serviceData() const {
    QVariantMap map;
    const char rawData[] = { (char)252, 18, (char)142, 1, 66, 0, 0, 0, 0, 0, 0, 0, 0, 0, (char)191, 45, 91, (char)160,
        (char)225, (char)216, 117, 36, (char)202, 0 };
    QByteArray data(rawData, 24);
    map.insert(u"0000fe2c-0000-1000-8000-00805f9b34fb"_s, QVariant::fromValue(data));
    return map;
}

void QuickShareBleAdvertisementAdaptor::Release() {
    qDebug() << u"QuickShareBleAdvertisement released by BlueZ"_s;
}

// --------------------------------------------------------------------------------
// QuickShareBleAdvertiser
// --------------------------------------------------------------------------------

QuickShareBleAdvertiser::QuickShareBleAdvertiser(QObject* parent)
    : QObject(parent)
    , m_objectPath(u"/org/caelestia/QuickShareBleAdvertisement"_s)
    , m_isAdvertising(false) {
    new QuickShareBleAdvertisementAdaptor(this);
    QDBusConnection::systemBus().registerObject(m_objectPath, this);
}

QuickShareBleAdvertiser::~QuickShareBleAdvertiser() {
    stopAdvertising();
    QDBusConnection::systemBus().unregisterObject(m_objectPath);
}

void QuickShareBleAdvertiser::startAdvertising() {
    if (m_isAdvertising)
        return;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        u"org.bluez"_s, u"/"_s, u"org.freedesktop.DBus.ObjectManager"_s, u"GetManagedObjects"_s);

    QDBusConnection::systemBus().callWithCallback(msg, this, SLOT(onGetManagedObjectsFinished(QDBusMessage)));
}

void QuickShareBleAdvertiser::stopAdvertising() {
    if (!m_isAdvertising || m_adapterPath.isEmpty())
        return;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        u"org.bluez"_s, m_adapterPath, u"org.bluez.LEAdvertisingManager1"_s, u"UnregisterAdvertisement"_s);
    msg << QVariant::fromValue(QDBusObjectPath(m_objectPath));
    QDBusConnection::systemBus().call(msg); // sync call is fine here for cleanup
    m_isAdvertising = false;
}

void QuickShareBleAdvertiser::onGetManagedObjectsFinished(const QDBusMessage& reply) {
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << u"Failed to get managed objects:"_s << reply.errorMessage();
        return;
    }

    m_adapterPath = findAdapterPath(reply, u"org.bluez.LEAdvertisingManager1"_s);

    if (m_adapterPath.isEmpty()) {
        qWarning() << u"No adapter with LEAdvertisingManager1 found."_s;
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        u"org.bluez"_s, m_adapterPath, u"org.bluez.LEAdvertisingManager1"_s, u"RegisterAdvertisement"_s);
    msg << QVariant::fromValue(QDBusObjectPath(m_objectPath));
    msg << QVariantMap(); // empty dict

    QDBusConnection::systemBus().callWithCallback(msg, this, SLOT(onRegisterAdvertisementFinished(QDBusMessage)));
}

void QuickShareBleAdvertiser::onRegisterAdvertisementFinished(const QDBusMessage& reply) {
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << u"Failed to register advertisement:"_s << reply.errorMessage();
    } else {
        qDebug() << u"Successfully registered BLE advertisement."_s;
        m_isAdvertising = true;
    }
}

// --------------------------------------------------------------------------------
// QuickShareBleScanner
// --------------------------------------------------------------------------------

QuickShareBleScanner::QuickShareBleScanner(QObject* parent)
    : QObject(parent)
    , m_isScanning(false) {
    QDBusConnection::systemBus().connect(u"org.bluez"_s, u"/"_s, u"org.freedesktop.DBus.ObjectManager"_s,
        u"InterfacesAdded"_s, this, SLOT(onInterfacesAdded(QDBusObjectPath, QMap<QString, QVariantMap>)));
}

QuickShareBleScanner::~QuickShareBleScanner() {
    stopScanning();
}

void QuickShareBleScanner::startScanning() {
    if (m_isScanning)
        return;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        u"org.bluez"_s, u"/"_s, u"org.freedesktop.DBus.ObjectManager"_s, u"GetManagedObjects"_s);

    QDBusConnection::systemBus().callWithCallback(msg, this, SLOT(onGetManagedObjectsFinished(QDBusMessage)));
}

void QuickShareBleScanner::stopScanning() {
    if (!m_isScanning || m_adapterPath.isEmpty())
        return;

    QDBusMessage msg =
        QDBusMessage::createMethodCall(u"org.bluez"_s, m_adapterPath, u"org.bluez.Adapter1"_s, u"StopDiscovery"_s);
    QDBusConnection::systemBus().call(msg);
    m_isScanning = false;
}

void QuickShareBleScanner::onGetManagedObjectsFinished(const QDBusMessage& reply) {
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << u"Failed to get managed objects for scanner:"_s << reply.errorMessage();
        return;
    }

    m_adapterPath = findAdapterPath(reply, u"org.bluez.Adapter1"_s);

    if (m_adapterPath.isEmpty()) {
        qWarning() << u"No adapter with org.bluez.Adapter1 found."_s;
        return;
    }

    QDBusMessage filterMsg =
        QDBusMessage::createMethodCall(u"org.bluez"_s, m_adapterPath, u"org.bluez.Adapter1"_s, u"SetDiscoveryFilter"_s);
    QVariantMap filter;
    filter.insert(u"UUIDs"_s, QStringList{ u"0000fe2c-0000-1000-8000-00805f9b34fb"_s });
    filterMsg << filter;
    QDBusConnection::systemBus().callWithCallback(filterMsg, this, SLOT(onSetDiscoveryFilterFinished(QDBusMessage)));
}

void QuickShareBleScanner::onSetDiscoveryFilterFinished(const QDBusMessage& reply) {
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << u"Failed to set discovery filter:"_s << reply.errorMessage();
    }

    QDBusMessage startMsg =
        QDBusMessage::createMethodCall(u"org.bluez"_s, m_adapterPath, u"org.bluez.Adapter1"_s, u"StartDiscovery"_s);
    QDBusConnection::systemBus().callWithCallback(startMsg, this, SLOT(onStartDiscoveryFinished(QDBusMessage)));
}

void QuickShareBleScanner::onStartDiscoveryFinished(const QDBusMessage& reply) {
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << u"Failed to start discovery:"_s << reply.errorMessage();
    } else {
        qDebug() << u"Started BLE discovery."_s;
        m_isScanning = true;
    }
}

void QuickShareBleScanner::onInterfacesAdded(
    const QDBusObjectPath& objectPath, const QMap<QString, QVariantMap>& interfacesAndProperties) {
    if (interfacesAndProperties.contains(u"org.bluez.Device1"_s)) {
        QVariantMap props = interfacesAndProperties.value(u"org.bluez.Device1"_s);
        checkDeviceProperties(props);

        QDBusConnection::systemBus().connect(u"org.bluez"_s, objectPath.path(), u"org.freedesktop.DBus.Properties"_s,
            u"PropertiesChanged"_s, this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }
}

void QuickShareBleScanner::onPropertiesChanged(
    const QString& interface, const QVariantMap& changedProperties, const QStringList& invalidatedProperties) {
    Q_UNUSED(invalidatedProperties);
    if (interface == u"org.bluez.Device1"_s) {
        checkDeviceProperties(changedProperties);
    }
}

void QuickShareBleScanner::checkDeviceProperties(const QVariantMap& props) {
    if (props.contains(u"ServiceData"_s)) {
        const QDBusArgument arg = props.value(u"ServiceData"_s).value<QDBusArgument>();
        QMap<QString, QVariant> serviceData;
        arg >> serviceData;

        // Sometimes QDBusArgument converts to QMap<QString, QByteArray> or QVariant
        if (serviceData.contains(u"0000fe2c-0000-1000-8000-00805f9b34fb"_s)) {
            QByteArray data;
            QVariant val = serviceData.value(u"0000fe2c-0000-1000-8000-00805f9b34fb"_s);
            if (val.userType() == QMetaType::QByteArray) {
                data = val.toByteArray();
            } else if (val.canConvert<QDBusArgument>()) {
                const QDBusArgument barg = val.value<QDBusArgument>();
                barg >> data;
            }

            if (!data.isEmpty()) {
                QDateTime now = QDateTime::currentDateTime();
                if (!m_lastEmit.isValid() || m_lastEmit.msecsTo(now) > 10000) {
                    m_lastEmit = now;
                    QString address = props.value(u"Address"_s).toString();
                    emit deviceFound(address, data);
                    qDebug() << u"QuickShareBleScanner found device:"_s << address;
                }
            }
        }
    }
}

} // namespace caelestia::services
