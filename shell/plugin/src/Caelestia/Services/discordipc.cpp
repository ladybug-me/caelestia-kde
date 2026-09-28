#include "discordipc.hpp"

#include <QCoreApplication>
#include <QDataStream>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QStandardPaths>

namespace caelestia {

enum class Opcode : int32_t {
    Handshake = 0,
    Frame = 1,
    Close = 2,
    Ping = 3,
    Pong = 4
};

DiscordIpc::DiscordIpc(QObject* parent)
    : QObject(parent)
    , m_socket(new QLocalSocket(this))
    , m_reconnectTimer(new QTimer(this))
    , m_connectTimeout(new QTimer(this))
    , m_connected(false) {
    connect(m_socket, &QLocalSocket::connected, this, &DiscordIpc::onSocketConnected);
    connect(m_socket, &QLocalSocket::disconnected, this, &DiscordIpc::onSocketDisconnected);
    connect(m_socket, &QLocalSocket::readyRead, this, &DiscordIpc::onReadyRead);
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    connect(m_socket, &QLocalSocket::errorOccurred, this, &DiscordIpc::onError);
#else
    connect(m_socket, QOverload<QLocalSocket::LocalSocketError>::of(&QLocalSocket::error), this, &DiscordIpc::onError);
#endif

    m_reconnectTimer->setInterval(5000);
    connect(m_reconnectTimer, &QTimer::timeout, this, &DiscordIpc::checkReconnect);

    m_connectTimeout->setSingleShot(true);
    m_connectTimeout->setInterval(1000);
    connect(m_connectTimeout, &QTimer::timeout, this, [this]() {
        if (m_socket->state() == QLocalSocket::ConnectingState) {
            m_socket->abort();
            tryNextPath();
        }
    });
}

DiscordIpc::~DiscordIpc() {
    disconnectIpc();
}

bool DiscordIpc::connected() const {
    return m_connected;
}

void DiscordIpc::connectIpc(const QString& clientId) {
    m_clientId = clientId;
    if (m_socket->state() != QLocalSocket::UnconnectedState) {
        m_socket->abort();
    }
    checkReconnect();
    m_reconnectTimer->start();
}

void DiscordIpc::disconnectIpc() {
    m_reconnectTimer->stop();
    m_connectTimeout->stop();
    m_pendingPaths.clear();
    m_clientId.clear();
    m_socket->abort();
    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
    }
}

void DiscordIpc::checkReconnect() {
    if (m_clientId.isEmpty())
        return;
    if (m_socket->state() == QLocalSocket::ConnectedState || m_socket->state() == QLocalSocket::ConnectingState)
        return;

    const QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);

    m_pendingPaths.clear();
    for (int slot = 0; slot <= 9; ++slot)
        m_pendingPaths << runtimeDir + QStringLiteral("/discord-ipc-") + QString::number(slot);

    static const QStringList flatpakIds = {
        QStringLiteral("com.discordapp.Discord"),
        QStringLiteral("dev.vencord.Vesktop"),
    };
    for (const auto& id : flatpakIds)
        for (int slot = 0; slot <= 9; ++slot)
            m_pendingPaths << runtimeDir + QStringLiteral("/app/") + id + QStringLiteral("/discord-ipc-") +
                                  QString::number(slot);

    tryNextPath();
}

void DiscordIpc::tryNextPath() {
    if (m_clientId.isEmpty()) {
        m_pendingPaths.clear();
        return;
    }

    while (!m_pendingPaths.isEmpty()) {
        const QString path = m_pendingPaths.takeFirst();
        if (QFile::exists(path)) {
            if (m_socket->state() != QLocalSocket::UnconnectedState)
                m_socket->abort();
            m_socket->connectToServer(path);
            m_connectTimeout->start();
            return;
        }
    }
}

void DiscordIpc::onSocketConnected() {
    m_connectTimeout->stop();
    m_pendingPaths.clear();

    QJsonObject payload;
    payload[QStringLiteral("v")] = 1;
    payload[QStringLiteral("client_id")] = m_clientId;
    sendFrame(static_cast<int>(Opcode::Handshake), payload);
}

void DiscordIpc::onSocketDisconnected() {
    m_buffer.clear();
    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
    }
}

void DiscordIpc::onError(QLocalSocket::LocalSocketError) {
    m_connectTimeout->stop();
    emit errorOccurred(m_socket->errorString());
    onSocketDisconnected();
    if (!m_pendingPaths.isEmpty())
        QMetaObject::invokeMethod(this, &DiscordIpc::tryNextPath, Qt::QueuedConnection);
}

void DiscordIpc::onReadyRead() {
    m_buffer.append(m_socket->readAll());

    while (m_buffer.size() >= 8) {
        QDataStream stream(m_buffer);
        stream.setByteOrder(QDataStream::LittleEndian);

        int32_t opcode;
        int32_t length;
        stream >> opcode >> length;

        if (length < 0 || length > 1024 * 1024) {
            qWarning() << "DiscordIPC: Malformed frame length received:" << length << "- aborting connection.";
            m_socket->abort();
            m_buffer.clear();
            return;
        }

        if (m_buffer.size() < 8 + length) {
            break;
        }

        QByteArray payloadData = m_buffer.mid(8, length);
        m_buffer.remove(0, 8 + length);

        QJsonDocument doc = QJsonDocument::fromJson(payloadData);
        if (doc.isObject()) {
            processPayload(opcode, doc.object());
        }
    }
}

void DiscordIpc::processPayload(int opcode, const QJsonObject& payload) {
    if (opcode == static_cast<int>(Opcode::Frame)) {
        if (payload.contains(QStringLiteral("cmd")) &&
            payload[QStringLiteral("cmd")].toString() == QStringLiteral("DISPATCH")) {
            if (payload.contains(QStringLiteral("evt")) &&
                payload[QStringLiteral("evt")].toString() == QStringLiteral("READY")) {
                m_connected = true;
                emit connectedChanged();
            }
        }
    } else if (opcode == static_cast<int>(Opcode::Close)) {
        m_socket->abort();
    }
}

void DiscordIpc::sendFrame(int opcode, const QJsonObject& payload) {
    if (m_socket->state() != QLocalSocket::ConnectedState)
        return;

    QJsonDocument doc(payload);
    QByteArray data = doc.toJson(QJsonDocument::Compact);

    QByteArray header;
    QDataStream stream(&header, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream << static_cast<int32_t>(opcode) << static_cast<int32_t>(data.size());

    m_socket->write(header);
    m_socket->write(data);
    m_socket->flush();
}

void DiscordIpc::sendActivity(const QJsonObject& activity) {
    if (!m_connected)
        return;

    QJsonObject args;
    args[QStringLiteral("pid")] = static_cast<int>(QCoreApplication::applicationPid());
    args[QStringLiteral("activity")] = activity;

    QJsonObject payload;
    payload[QStringLiteral("cmd")] = QStringLiteral("SET_ACTIVITY");
    payload[QStringLiteral("args")] = args;
    payload[QStringLiteral("nonce")] = QString::number(QDateTime::currentMSecsSinceEpoch());

    sendFrame(static_cast<int>(Opcode::Frame), payload);
}

void DiscordIpc::clearActivity() {
    if (!m_connected)
        return;

    QJsonObject args;
    args[QStringLiteral("pid")] = static_cast<int>(QCoreApplication::applicationPid());

    QJsonObject payload;
    payload[QStringLiteral("cmd")] = QStringLiteral("SET_ACTIVITY");
    payload[QStringLiteral("args")] = args;
    payload[QStringLiteral("nonce")] = QString::number(QDateTime::currentMSecsSinceEpoch());

    sendFrame(static_cast<int>(Opcode::Frame), payload);
}

} // namespace caelestia
