#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>

namespace caelestia {

class DiscordIpc : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    explicit DiscordIpc(QObject* parent = nullptr);
    ~DiscordIpc() override;

    bool connected() const;

    Q_INVOKABLE void connectIpc(const QString& clientId);
    Q_INVOKABLE void disconnectIpc();
    Q_INVOKABLE void sendActivity(const QJsonObject& activity);
    Q_INVOKABLE void clearActivity();

signals:
    void connectedChanged();
    void errorOccurred(const QString& errorString);

private slots:
    void onSocketConnected();
    void onSocketDisconnected();
    void onReadyRead();
    void onError(QLocalSocket::LocalSocketError socketError);
    void checkReconnect();
    void tryNextPath();

private:
    void sendFrame(int opcode, const QJsonObject& payload);
    void processPayload(int opcode, const QJsonObject& payload);

    QLocalSocket* m_socket;
    QTimer* m_reconnectTimer;
    QTimer* m_connectTimeout;
    QString m_clientId;
    bool m_connected;
    QByteArray m_buffer;
    QStringList m_pendingPaths;
};

} // namespace caelestia
