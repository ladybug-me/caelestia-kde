#pragma once

#include <QFile>
#include <QMap>
#include <QObject>
#include <QTcpSocket>
#include <QTimer>

#include "QuickShareCrypto.hpp"
#ifndef Q_MOC_RUN
#include "offline_wire_formats.pb.h"
#include "wire_format.pb.h"
#endif

namespace caelestia::services {

class QuickShareConnection : public QObject {
    Q_OBJECT

public:
    enum State {
        Disconnected,
        Connecting,
        OfflineFrameExchange,
        Ukey2Handshake,
        PostHandshake,
        PairedKeyExchange,
        ConnectionAccepted,
        Transferring
    };

    explicit QuickShareConnection(QTcpSocket* socket, QObject* parent = nullptr);
    explicit QuickShareConnection(const QString& host, int port, QObject* parent = nullptr);
    ~QuickShareConnection() override;

    void sendFile(const QString& filePath);
    void acceptTransfer();
    void rejectTransfer();
    /// Lets a confirmed file go. The code the handshake derives is shown on both ends,
    /// and a user who has not compared them has not agreed that this peer is the device
    /// they picked, so nothing leaves until they say it matches.
    void confirmSend();
    /// Ends the connection without reporting it as a failure: the user changed their mind.
    void cancel();

    QString incomingFileName() const { return m_incomingFileName; }

    /// Where a received file was written. Empty until the last chunk arrives.
    QString incomingFilePath() const { return m_incomingFilePath; }

    QString deviceName() const { return m_deviceName; }

signals:
    void stateChanged(State newState);
    void transferRequested(const QString& fileName, qint64 fileSize);
    void pinCodeReady(const QString& pinCode);
    void transferProgress(qint64 bytesSent, qint64 bytesTotal);
    /// The transfer ended, successfully or not. Emitted once per connection.
    void transferFinished(bool success);
    /// The socket is gone. The service drops its handle on this.
    void closed();

private slots:
    void onReadyRead();
    void onDisconnected();
    void onError(QAbstractSocket::SocketError socketError);

private:
    /// The payloads a peer is sending, assembled from their chunks. It owns both the
    /// parts and the running total, so the budget can never drift from what is held.
    class PayloadAssembler {
    public:
        enum class Result {
            /// The chunk does not continue a payload; nothing was kept.
            Ignored,
            /// The chunk was kept and the payload is not whole yet.
            Pending,
            /// The last chunk landed. `payload` holds the whole thing and the
            /// assembler has already let it go.
            Complete,
            /// The chunk would take the assembler past its budget.
            Refused,
        };

        /// Takes one chunk. A chunk carries the offset it continues from, so a
        /// missing or reordered one is refused rather than appended.
        Result append(qint64 payloadId, qint64 offset, const QByteArray& body, bool last, QByteArray& payload);

        void clear();

    private:
        QMap<qint64, QByteArray> m_parts;
        qint64 m_bufferedBytes = 0;
    };

    void connectSocket();
    void setState(State state);
    /// Restarts the deadline for this connection: a peer has to keep making progress, or
    /// its socket is given back. There is no other bound on how long a silent host may
    /// hold one of the service's fixed number of slots.
    void restartIdleTimer();
    int idleTimeoutMs() const;
    void onIdleTimeout();
    /// Ends the transfer with a failure: pending bytes are dropped, a partial
    /// download is taken away, and the socket is closed. Every refusal goes through
    /// here so a failure cannot leave a peer writing into a connection nobody answers.
    void failTransfer(const QString& reason);
    /// Reports the end of the transfer once: a file save and the peer's later
    /// disconnection both end the same transfer.
    void finishTransfer(bool success);

    void handleOfflineFrame(const QByteArray& data);
    void handleUkey2(const QByteArray& data);
    void handlePostHandshake(const QByteArray& data);
    void handleEncryptedFrame(const QByteArray& data);
    void handleSharingFrame(const sharing::nearby::Frame& frame);
    void handlePayloadTransfer(const location::nearby::connections::PayloadTransferFrame& packet);
    void handleFileChunk(const location::nearby::connections::PayloadTransferFrame& packet, const QByteArray& body);
    void handleByteChunk(const location::nearby::connections::PayloadTransferFrame& packet, const QByteArray& body);
    /// Opens the destination for an accepted transfer. False (with the transfer
    /// already failed and reported) when no file could be created.
    bool openIncomingFile();
    void finishIncomingFile();

    void sendConnectionRequest();
    void sendConnectionResponse();
    void sendDisconnection();
    void sendFilePayload();
    /// Keeps the socket's write buffer fed while it drains, so sending a file
    /// neither blocks the shell nor holds the whole file in memory.
    void pumpOutgoingFile();
    void sendPayloadChunk(qint64 payloadId,
        location::nearby::connections::PayloadTransferFrame::PayloadHeader::PayloadType type, qint64 totalSize,
        qint64 offset, bool lastChunk, const QByteArray& body, const QString& fileName = {});
    void sendEncryptedSharingFrame(sharing::nearby::V1Frame::FrameType type);
    void sendEncryptedSharingFrame(const sharing::nearby::Frame& frame);
    /// Length-prefixes a frame sent before the handshake encrypts anything.
    void sendPlaintextFrame(const location::nearby::connections::OfflineFrame& frame);
    /// Seals a frame and length-prefixes the result.
    void sendSecureFrame(const location::nearby::connections::OfflineFrame& frame);

    QTcpSocket* m_socket;
    State m_state = Disconnected;
    bool m_finished = false;
    int m_sendSeq = 1;
    QuickShareCrypto m_crypto;
    QByteArray m_buffer;

    QString m_incomingFileName;
    QString m_incomingFilePath;
    qint64 m_incomingFileSize = 0;
    /// Whether the user has been shown a request on this connection. A second
    /// INTRODUCTION is refused: it is a second thing to agree to, and the prompt the
    /// user answered was about the first.
    bool m_incomingAnnounced = false;
    /// The name and size the user was actually shown, frozen when they accepted. Every
    /// byte and every name that follows is checked against these, never against a later
    /// frame the peer chose.
    QString m_acceptedFileName;
    qint64 m_acceptedFileSize = 0;
    /// A peer may only hand us a file after the user accepted the request; until
    /// then its chunks are refused rather than written out.
    bool m_incomingAccepted = false;
    /// Whether the user compared this connection's code with the peer's, which is what
    /// lets an outgoing file leave.
    bool m_sendConfirmed = false;
    /// Whether the peer has answered the request with an ACCEPT.
    bool m_peerAccepted = false;
    /// Ends a connection that stops making progress.
    QTimer* m_idleTimer = nullptr;
    /// The destination file, written as chunks arrive so a large transfer never
    /// sits in memory. Only open while a file is arriving.
    QFile m_incomingHandle;
    QString m_incomingSavedPath;
    qint64 m_incomingOffset = 0;
    QString m_deviceName;

    qint64 m_outgoingFilePayloadId = 0;
    QString m_outgoingFilePath;
    QString m_outgoingFileName;
    qint64 m_outgoingFileSize = 0;
    qint64 m_outgoingOffset = 0;
    QFile m_outgoingFile;
    /// The file and its trailer are on the wire; only the socket draining is left.
    bool m_outgoingFileQueued = false;

    PayloadAssembler m_payloads;
};

} // namespace caelestia::services
