#include "quickshare_service.hpp"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QSysInfo>
#include <QTimer>

using Qt::StringLiterals::operator""_s;

namespace caelestia::services {

namespace {

/// The shell keeps its state under XDG_STATE_HOME (Paths.state in the QML), so the
/// transfer history belongs there rather than in Qt's per-application data directory.
QString historyFilePath() {
    const QString stateHome = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + u"/.local/state"_s);
    return stateHome + u"/caelestia/quickshare_history.json"_s;
}

/// The name to show for a peer that has not introduced itself yet.
QString deviceLabel(const QuickShareConnection* connection) {
    const QString name = connection->deviceName();
    return name.isEmpty() ? u"Nearby Device"_s : name;
}

/// How long a finished connection is kept alive, so that anything still in the
/// socket can reach the peer before it goes.
constexpr int connectionLingerMs = 2000;

/// The port the transfer listener binds. shell/scripts/quickshare-port is its one
/// definition: CMake bakes it in here, the shell passes it to the setup helper when it
/// opens the firewall, and the install step reads it to write that same rule. A
/// listener on a random port could only be opened while the shell runs, which needs
/// administrator rights on every start.
constexpr quint16 quicksharePort = CAELESTIA_QUICKSHARE_PORT;

/// Lets a connection go once it has reported its transfer.
void retire(QuickShareConnection* connection) {
    QTimer::singleShot(connectionLingerMs, connection, &QObject::deleteLater);
}

} // namespace

QuickShareService::QuickShareService(QObject* parent)
    : QObject(parent)
    , m_discovery(new QuickShareDiscovery(this))
    , m_bleAdvertiser(new QuickShareBleAdvertiser(this))
    , m_bleScanner(new QuickShareBleScanner(this))
    , m_server(new QTcpServer(this)) {

    connect(m_discovery, &QuickShareDiscovery::deviceFound, this, &QuickShareService::onDeviceFound);
    connect(m_discovery, &QuickShareDiscovery::deviceLost, this, &QuickShareService::onDeviceLost);

    connect(m_bleScanner, &QuickShareBleScanner::deviceFound, this, [this](const QString&, const QByteArray&) {
        m_discovery->triggerTemporaryAdvertising(QSysInfo::machineHostName(), m_server->serverPort());
    });

    connect(m_server, &QTcpServer::newConnection, this, &QuickShareService::onNewConnection);

    loadHistory();
}

QuickShareService::~QuickShareService() {
    saveHistory();
}

bool QuickShareService::isEnabled() const {
    return m_isEnabled;
}

void QuickShareService::setEnabled(bool enabled) {
    if (m_isEnabled == enabled)
        return;

    if (!enabled) {
        m_isEnabled = false;
        emit isEnabledChanged();
        m_discovery->stopDiscovery();
        m_bleScanner->stopScanning();
        m_server->close();
        setVisible(false);
        return;
    }

    if (!m_discovery->startDiscovery()) {
        // The condition only: where the user goes to fix it is the shell's to say, and
        // it has a row for exactly this.
        emit errorOccurred(u"The Avahi daemon is not running, so Quick Share cannot announce "
                           u"itself to nearby devices."_s);
        return;
    }

    if (!m_server->isListening() && !m_server->listen(QHostAddress::Any, quicksharePort)) {
        m_discovery->stopDiscovery();
        emit errorOccurred(
            u"Quick Share could not listen on port %1: %2"_s.arg(quicksharePort).arg(m_server->errorString()));
        return;
    }

    m_isEnabled = true;
    emit isEnabledChanged();

    m_bleScanner->startScanning();

    // Turning Quick Share on is also what puts this shell on the network for
    // nearby devices; hiding it again is setVisible(false).
    setVisible(true);
}

bool QuickShareService::isVisible() const {
    return m_isVisible;
}

int QuickShareService::listenPort() const {
    return quicksharePort;
}

void QuickShareService::setVisible(bool visible) {
    if (m_isVisible == visible)
        return;

    if (visible && m_isEnabled) {
        if (!m_discovery->advertise(QSysInfo::machineHostName(), m_server->serverPort())) {
            emit errorOccurred(u"Failed to advertise Quick Share. Avahi daemon might not be running."_s);
            return;
        }
        m_isVisible = true;
        emit isVisibleChanged();
    } else {
        m_isVisible = false;
        emit isVisibleChanged();
        m_discovery->stopAdvertising();
    }
}

QVariantList QuickShareService::nearbyDevices() const {
    QVariantList list;
    for (const auto& dev : m_devices) {
        QVariantMap map;
        map[u"id"_s] = dev.id;
        map[u"name"_s] = dev.name;
        map[u"address"_s] = dev.address;
        list.append(map);
    }
    return list;
}

QVariantList QuickShareService::transferHistory() const {
    return m_transferHistory;
}

void QuickShareService::sendFile(const QString& deviceId, const QString& filePath) {
    const auto device = std::find_if(m_devices.cbegin(), m_devices.cend(), [&](const QuickShareDevice& d) {
        return d.id == deviceId;
    });
    if (device == m_devices.cend())
        return;

    const QString deviceName = device->name;
    auto* connection = new QuickShareConnection(device->address, device->port, this);

    // The file itself goes out once the handshake finishes.
    connect(connection, &QuickShareConnection::stateChanged, this,
        [connection, filePath](QuickShareConnection::State state) {
            if (state == QuickShareConnection::ConnectionAccepted)
                connection->sendFile(filePath);
        });

    connect(connection, &QuickShareConnection::transferProgress, this, [this, deviceId](qint64 sent, qint64 total) {
        emit outgoingTransferProgress(deviceId, sent, total);
    });

    connect(connection, &QuickShareConnection::transferFinished, this,
        [this, connection, deviceId, deviceName, filePath](bool success) {
            if (success)
                appendHistoryEntry(u"sent"_s, QFileInfo(filePath).fileName(), filePath, deviceName);

            emit outgoingTransferFinished(deviceId, success);
            retire(connection);
        });
}

void QuickShareService::acceptIncomingTransfer() {
    if (m_pendingIncomingRequest)
        m_pendingIncomingRequest->acceptTransfer();
}

void QuickShareService::rejectIncomingTransfer() {
    QuickShareConnection* connection = m_pendingIncomingRequest.data();
    if (!connection)
        return;

    // Rejecting reports itself through transferFinished, which drops the request.
    connection->rejectTransfer();
    retire(connection);
}

void QuickShareService::clearHistory() {
    m_transferHistory.clear();
    emit transferHistoryChanged();
    saveHistory();
}

void QuickShareService::appendHistoryEntry(
    const QString& direction, const QString& fileName, const QString& filePath, const QString& deviceName) {
    QVariantMap entry;
    entry[u"direction"_s] = direction;
    entry[u"fileName"_s] = fileName;
    entry[u"filePath"_s] = filePath;
    entry[u"deviceName"_s] = deviceName;
    entry[u"timestamp"_s] = QDateTime::currentDateTime().toSecsSinceEpoch();

    m_transferHistory.prepend(entry);
    emit transferHistoryChanged();
    saveHistory();
}

void QuickShareService::removeHistoryEntry(const QString& filePath, qint64 timestamp) {
    const auto entry = std::find_if(m_transferHistory.begin(), m_transferHistory.end(), [&](const QVariant& value) {
        const QVariantMap map = value.toMap();
        return map.value(u"filePath"_s).toString() == filePath && map.value(u"timestamp"_s).toLongLong() == timestamp;
    });
    if (entry == m_transferHistory.end())
        return;

    m_transferHistory.erase(entry);
    emit transferHistoryChanged();
    saveHistory();
}

void QuickShareService::onDeviceFound(const QuickShareDevice& device) {
    if (device.name == QSysInfo::machineHostName())
        return;

    auto it = std::find_if(m_devices.begin(), m_devices.end(), [&](const QuickShareDevice& d) {
        return d.id == device.id;
    });
    if (it == m_devices.end()) {
        m_devices.append(device);
        emit nearbyDevicesChanged();
    }
}

void QuickShareService::onDeviceLost(const QString& deviceId) {
    auto it = std::find_if(m_devices.begin(), m_devices.end(), [&](const QuickShareDevice& d) {
        return d.id == deviceId;
    });
    if (it != m_devices.end()) {
        m_devices.erase(it);
        emit nearbyDevicesChanged();
    }
}

void QuickShareService::onNewConnection() {
    QTcpSocket* socket = m_server->nextPendingConnection();
    if (!socket)
        return;

    auto* connection = new QuickShareConnection(socket, this);

    connect(connection, &QuickShareConnection::transferRequested, this,
        [this, connection](const QString& fileName, qint64 fileSize) {
            // The newest request is the one acceptIncomingTransfer() answers.
            m_pendingIncomingRequest = connection;
            emit incomingTransferRequested(deviceLabel(connection), fileName, fileSize);
        });

    connect(connection, &QuickShareConnection::pinCodeReady, this, [this](const QString& pinCode) {
        emit incomingTransferPinReady(pinCode);
    });

    connect(connection, &QuickShareConnection::transferFinished, this, [this, connection](bool success) {
        if (m_pendingIncomingRequest == connection) {
            m_pendingIncomingRequest = nullptr;
            if (success)
                appendHistoryEntry(u"received"_s, connection->incomingFileName(), connection->incomingFilePath(),
                    deviceLabel(connection));
        }

        emit incomingTransferFinished(success);
        retire(connection);
    });

    // A peer that walks away mid-request: drop the request so the prompt and the
    // card stop offering to accept it.
    connect(connection, &QuickShareConnection::closed, this, [this, connection] {
        if (m_pendingIncomingRequest != connection)
            return;

        m_pendingIncomingRequest = nullptr;
        emit incomingTransferFinished(false);
    });
}

void QuickShareService::startBleWakeupBroadcast() {
    m_bleAdvertiser->startAdvertising();
}

void QuickShareService::stopBleWakeupBroadcast() {
    m_bleAdvertiser->stopAdvertising();
}

void QuickShareService::loadHistory() {
    QFile file(historyFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isArray())
        m_transferHistory = doc.array().toVariantList();
}

void QuickShareService::saveHistory() {
    const QString path = historyFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << u"QuickShareService: Failed to open"_s << path;
        return;
    }

    file.write(QJsonDocument(QJsonArray::fromVariantList(m_transferHistory)).toJson());
    if (!file.commit())
        qWarning() << u"QuickShareService: Failed to write"_s << path;
}

} // namespace caelestia::services
