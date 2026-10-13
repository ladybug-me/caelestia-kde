#include "QuickShareConnection.hpp"

#include <openssl/rand.h>

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QMimeType>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QSysInfo>
#include <QtEndian>

#include "QuickShareEndpointInfo.hpp"
#include "QuickShareProto.hpp"
#include "device_to_device_messages.pb.h"
#include "offline_wire_formats.pb.h"
#include "securegcm.pb.h"
#include "securemessage.pb.h"
#include "ukey.pb.h"
#include "wire_format.pb.h"

using Qt::StringLiterals::operator""_s;

namespace caelestia::services {

namespace {

using location::nearby::connections::OfflineFrame;
using location::nearby::connections::PayloadTransferFrame;
using location::nearby::connections::V1Frame;

/// The payload chunk size this implementation writes.
constexpr qint64 chunkSize = 1024 * 1024;

/// How much of an outgoing file may sit in Qt's socket write buffer before the
/// send waits for the socket to drain.
constexpr qint64 sendBufferLimit = 4 * chunkSize;

/// The name to save a received file under. The peer chose it, so it can name a
/// path: keep only the last component and refuse anything that would still
/// traverse or name nothing at all.
QString safeIncomingFileName(const QString& proposed) {
    QString name = proposed;
    name.replace(u'\\', u'/');
    name = name.section(u'/', -1).trimmed();
    if (name.isEmpty() || name == u"."_s || name == u".."_s)
        return u"received-file"_s;
    return name;
}

/// A path in `directory` that does not overwrite what is already there.
QString uniqueFilePath(const QString& directory, const QString& fileName) {
    const QString direct = directory + u'/' + fileName;
    if (!QFile::exists(direct))
        return direct;

    const QFileInfo info(fileName);
    const QString suffix = info.suffix();
    const QString tail = suffix.isEmpty() ? QString() : u'.' + suffix;
    for (int n = 1;; n++) {
        const QString candidate = QString(u"%1/%2 (%3)%4"_s).arg(directory, info.completeBaseName()).arg(n).arg(tail);
        if (!QFile::exists(candidate))
            return candidate;
    }
}

void writeLengthPrefixed(QTcpSocket* socket, const QByteArray& data) {
    const uint32_t length = qToBigEndian(static_cast<uint32_t>(data.size()));
    socket->write(reinterpret_cast<const char*>(&length), 4);
    socket->write(data);
}

QString localDeviceName() {
    const QString hostname = QSysInfo::machineHostName();
    return hostname.isEmpty() ? u"CaelestiaClient"_s : hostname;
}

} // namespace

QuickShareConnection::QuickShareConnection(QTcpSocket* socket, QObject* parent)
    : QObject(parent)
    , m_socket(socket)
    , m_state(OfflineFrameExchange) {
    m_socket->setParent(this); // the accepted socket belongs to this connection
    m_crypto.initServer();
    connectSocket();
}

QuickShareConnection::QuickShareConnection(const QString& host, int port, QObject* parent)
    : QObject(parent)
    , m_socket(new QTcpSocket(this))
    , m_state(Connecting) {
    m_crypto.initClient();
    connectSocket();

    connect(m_socket, &QTcpSocket::connected, this, &QuickShareConnection::sendConnectionRequest);

    m_socket->connectToHost(host, static_cast<quint16>(port));
}

QuickShareConnection::~QuickShareConnection() {
    if (m_socket->isOpen()) {
        m_socket->close();
    }
}

void QuickShareConnection::connectSocket() {
    connect(m_socket, &QTcpSocket::readyRead, this, &QuickShareConnection::onReadyRead);
    connect(m_socket, &QTcpSocket::bytesWritten, this, &QuickShareConnection::pumpOutgoingFile);
    connect(m_socket, &QTcpSocket::disconnected, this, &QuickShareConnection::onDisconnected);
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    connect(m_socket, &QTcpSocket::errorOccurred, this, &QuickShareConnection::onError);
#else
    connect(m_socket, QOverload<QAbstractSocket::SocketError>::of(&QTcpSocket::error), this,
        &QuickShareConnection::onError);
#endif
}

void QuickShareConnection::setState(State state) {
    if (m_state == state)
        return;

    m_state = state;
    emit stateChanged(m_state);
}

void QuickShareConnection::finishTransfer(bool success) {
    if (m_finished)
        return;

    m_finished = true;
    m_outgoingFile.close();
    emit transferFinished(success);
}

void QuickShareConnection::sendConnectionRequest() {
    OfflineFrame frame;
    frame.set_version(OfflineFrame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(V1Frame::CONNECTION_REQUEST);
    auto* request = v1->mutable_connection_request();
    request->set_endpoint_id("ABCD");
    request->set_endpoint_name(localDeviceName().toStdString());
    const QByteArray info = endpointinfo::encode(localDeviceName());
    request->set_endpoint_info(info.constData(), info.size());

    setState(OfflineFrameExchange);
    sendPlaintextFrame(frame);
    setState(Ukey2Handshake);
    writeLengthPrefixed(m_socket, m_crypto.generateClientInit());
}

void QuickShareConnection::sendPlaintextFrame(const OfflineFrame& frame) {
    writeLengthPrefixed(m_socket, serialize(frame));
}

void QuickShareConnection::sendSecureFrame(const OfflineFrame& frame) {
    writeLengthPrefixed(m_socket, m_crypto.sealDeviceToDevice(m_sendSeq++, serialize(frame)));
}

void QuickShareConnection::sendConnectionResponse() {
    OfflineFrame frame;
    frame.set_version(OfflineFrame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(V1Frame::CONNECTION_RESPONSE);
    auto* response = v1->mutable_connection_response();
    response->set_response(location::nearby::connections::ConnectionResponseFrame::ACCEPT);
    response->mutable_os_info()->set_type(location::nearby::connections::OsInfo::LINUX);

    sendPlaintextFrame(frame);
}

void QuickShareConnection::sendFile(const QString& filePath) {
    if (m_state != ConnectionAccepted)
        return;

    QFileInfo fileInfo(filePath);
    if (!fileInfo.exists()) {
        qWarning() << u"QuickShareConnection: File to send does not exist:"_s << filePath;
        emit transferFinished(false);
        return;
    }

    setState(Transferring);

    sharing::nearby::Frame frame;
    frame.set_version(sharing::nearby::Frame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(sharing::nearby::V1Frame::INTRODUCTION);

    auto* intro = v1->mutable_introduction();
    auto* fileMeta = intro->add_file_metadata();
    fileMeta->set_name(fileInfo.fileName().toStdString());

    QMimeDatabase db;
    QMimeType mimeType = db.mimeTypeForFile(fileInfo);
    QString mimeString = mimeType.name();
    if (mimeString.isEmpty())
        mimeString = u"application/octet-stream"_s;

    fileMeta->set_mime_type(mimeString.toStdString());

    if (mimeString.startsWith(u"image/"_s)) {
        fileMeta->set_type(sharing::nearby::FileMetadata::IMAGE);
    } else if (mimeString.startsWith(u"video/"_s)) {
        fileMeta->set_type(sharing::nearby::FileMetadata::VIDEO);
    } else if (mimeString.startsWith(u"audio/"_s)) {
        fileMeta->set_type(sharing::nearby::FileMetadata::AUDIO);
    } else {
        fileMeta->set_type(sharing::nearby::FileMetadata::UNKNOWN);
    }

    fileMeta->set_size(fileInfo.size());

    qint64 filePayloadId = QRandomGenerator::global()->generate64();
    filePayloadId = qAbs(filePayloadId);
    fileMeta->set_payload_id(filePayloadId);
    fileMeta->set_id(filePayloadId);

    m_outgoingFilePayloadId = filePayloadId;
    m_outgoingFilePath = filePath;
    m_outgoingFileSize = fileInfo.size();

    sendEncryptedSharingFrame(frame);
}

void QuickShareConnection::sendEncryptedSharingFrame(sharing::nearby::V1Frame::FrameType type) {
    sharing::nearby::Frame frame;
    frame.set_version(sharing::nearby::Frame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(type);

    if (type == sharing::nearby::V1Frame::PAIRED_KEY_RESULT) {
        v1->mutable_paired_key_result()->set_status(sharing::nearby::PairedKeyResultFrame::UNABLE);
    } else if (type == sharing::nearby::V1Frame::PAIRED_KEY_ENCRYPTION) {
        QByteArray secretIdHash(6, 0);
        QByteArray signedData(72, 0);
        RAND_bytes(reinterpret_cast<unsigned char*>(secretIdHash.data()), 6);
        RAND_bytes(reinterpret_cast<unsigned char*>(signedData.data()), 72);
        v1->mutable_paired_key_encryption()->set_secret_id_hash(secretIdHash.constData(), 6);
        v1->mutable_paired_key_encryption()->set_signed_data(signedData.constData(), 72);
    } else if (type == sharing::nearby::V1Frame::RESPONSE) {
        v1->mutable_connection_response()->set_status(sharing::nearby::ConnectionResponseFrame::ACCEPT);
    }

    sendEncryptedSharingFrame(frame);
}

void QuickShareConnection::sendEncryptedSharingFrame(const sharing::nearby::Frame& frame) {
    const QByteArray frameData = serialize(frame);
    // A sharing frame travels as a BYTES payload: the frame itself, then an empty
    // last chunk that terminates it.
    const qint64 payloadId = qAbs(QRandomGenerator::global()->generate64());
    sendPayloadChunk(payloadId, PayloadTransferFrame::PayloadHeader::BYTES, frameData.size(), 0, false, frameData, {});
    sendPayloadChunk(
        payloadId, PayloadTransferFrame::PayloadHeader::BYTES, frameData.size(), frameData.size(), true, {}, {});
}

void QuickShareConnection::sendPayloadChunk(qint64 payloadId, PayloadTransferFrame::PayloadHeader::PayloadType type,
    qint64 totalSize, qint64 offset, bool lastChunk, const QByteArray& body, const QString& fileName) {
    PayloadTransferFrame packet;
    auto* header = packet.mutable_payload_header();
    header->set_id(payloadId);
    header->set_type(type);
    header->set_total_size(totalSize);
    header->set_is_sensitive(false);
    if (!fileName.isEmpty())
        header->set_file_name(fileName.toStdString());
    packet.set_packet_type(PayloadTransferFrame::DATA);
    auto* chunk = packet.mutable_payload_chunk();
    chunk->set_offset(offset);
    chunk->set_flags(lastChunk ? 1 : 0);
    chunk->set_body(body.constData(), body.size());

    OfflineFrame frame;
    frame.set_version(OfflineFrame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(V1Frame::PAYLOAD_TRANSFER);
    *v1->mutable_payload_transfer() = packet;

    sendSecureFrame(frame);
}

void QuickShareConnection::acceptTransfer() {
    if (m_state != ConnectionAccepted)
        return;

    sendEncryptedSharingFrame(sharing::nearby::V1Frame::RESPONSE);
    setState(Transferring);
}

void QuickShareConnection::rejectTransfer() {
    if (m_state != ConnectionAccepted)
        return;

    sharing::nearby::Frame frame;
    frame.set_version(sharing::nearby::Frame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(sharing::nearby::V1Frame::RESPONSE);
    v1->mutable_connection_response()->set_status(sharing::nearby::ConnectionResponseFrame::REJECT);
    sendEncryptedSharingFrame(frame);

    finishTransfer(false);
}

void QuickShareConnection::onReadyRead() {
    m_buffer.append(m_socket->readAll());

    while (m_buffer.size() >= 4) {
        uint32_t length;
        memcpy(&length, m_buffer.constData(), 4);
        length = qFromBigEndian(length);

        if (static_cast<uint32_t>(m_buffer.size()) < 4 + length) {
            break;
        }

        QByteArray frameData = m_buffer.mid(4, length);
        m_buffer.remove(0, 4 + length);

        switch (m_state) {
        case OfflineFrameExchange:
            handleOfflineFrame(frameData);
            break;
        case Ukey2Handshake:
            handleUkey2(frameData);
            break;
        case PostHandshake:
            handlePostHandshake(frameData);
            break;
        case PairedKeyExchange:
        case ConnectionAccepted:
        case Transferring:
            handleEncryptedFrame(frameData);
            break;
        default:
            break;
        }
    }
}

void QuickShareConnection::handleOfflineFrame(const QByteArray& data) {
    location::nearby::connections::OfflineFrame frame;
    if (!frame.ParseFromArray(data.constData(), static_cast<int>(data.size()))) {
        qWarning() << u"QuickShareConnection: Failed to parse initial OfflineFrame"_s;
        return;
    }

    if (frame.has_v1() && frame.v1().has_connection_request()) {
        const auto& req = frame.v1().connection_request();
        if (req.has_endpoint_info()) {
            const QByteArray info(req.endpoint_info().data(), static_cast<qsizetype>(req.endpoint_info().size()));
            if (endpointinfo::isVisible(info))
                m_deviceName = endpointinfo::deviceName(info);
        }
        if (m_deviceName.isEmpty() && req.has_endpoint_name())
            m_deviceName = QString::fromUtf8(req.endpoint_name().data(), req.endpoint_name().size());
    }

    setState(Ukey2Handshake);
}

void QuickShareConnection::handleUkey2(const QByteArray& data) {
    if (m_crypto.isHandshakeComplete()) {
        qWarning() << u"QuickShareConnection: Received Ukey2 message but handshake is already complete!"_s;
        return;
    }

    securegcm::Ukey2Message message;
    if (!message.ParseFromArray(data.constData(), static_cast<int>(data.size()))) {
        qWarning() << u"QuickShareConnection: Failed to parse Ukey2Message!"_s;
        return;
    }

    switch (message.message_type()) {
    case securegcm::Ukey2Message::CLIENT_INIT: {
        const QByteArray serverInit = m_crypto.processClientInit(data);
        if (serverInit.isEmpty())
            qWarning() << u"QuickShareConnection: m_crypto.processClientInit failed"_s;
        else
            writeLengthPrefixed(m_socket, serverInit);
        break;
    }
    case securegcm::Ukey2Message::SERVER_INIT:
        (void)m_crypto.processServerInit(data);
        writeLengthPrefixed(m_socket, m_crypto.generateClientFinished());
        sendConnectionResponse();
        setState(PostHandshake);
        break;
    case securegcm::Ukey2Message::CLIENT_FINISH:
        if (!m_crypto.processClientFinished(data)) {
            qWarning() << u"QuickShareConnection: m_crypto.processClientFinished failed!"_s;
            break;
        }
        setState(PostHandshake);
        emit pinCodeReady(m_crypto.pinCode());
        break;
    default:
        break;
    }
}

void QuickShareConnection::handlePostHandshake(const QByteArray& data) {
    location::nearby::connections::OfflineFrame frame;
    if (!frame.ParseFromArray(data.constData(), static_cast<int>(data.size()))) {
        qWarning() << u"QuickShareConnection: Failed to parse plaintext CONNECTION_RESPONSE"_s;
        return;
    }

    // The server (receiver) answers with its CONNECTION_RESPONSE here; the client
    // (sender) already sent its own right after CLIENT_FINISH.
    if (!m_crypto.isClient())
        sendConnectionResponse();

    sendEncryptedSharingFrame(sharing::nearby::V1Frame::PAIRED_KEY_ENCRYPTION);
    setState(PairedKeyExchange);
}

void QuickShareConnection::handleEncryptedFrame(const QByteArray& data) {
    const QByteArray plaintext = m_crypto.openDeviceToDevice(data);
    if (plaintext.isEmpty()) {
        qWarning() << u"QuickShareConnection: Failed to unwrap encrypted frame"_s;
        return;
    }

    OfflineFrame frame;
    if (!frame.ParseFromArray(plaintext.constData(), static_cast<int>(plaintext.size()))) {
        qWarning() << u"QuickShareConnection: Failed to parse OfflineFrame from decrypted data"_s;
        return;
    }

    if (!frame.has_v1())
        return;

    const auto& v1 = frame.v1();
    switch (v1.type()) {
    case V1Frame::PAYLOAD_TRANSFER:
        if (v1.has_payload_transfer())
            handlePayloadTransfer(v1.payload_transfer());
        break;
    case V1Frame::KEEP_ALIVE:
        break; // nothing to answer
    case V1Frame::DISCONNECTION:
        // The peer is closing the connection. A transfer that completed has already
        // reported itself, so this only ends transfers the peer gave up on.
        setState(Disconnected);
        finishTransfer(false);
        break;
    default:
        break;
    }
}

void QuickShareConnection::handlePayloadTransfer(const PayloadTransferFrame& packet) {
    const auto& chunk = packet.payload_chunk();
    const QByteArray body(chunk.body().data(), static_cast<qsizetype>(chunk.body().size()));

    if (packet.payload_header().type() == PayloadTransferFrame::PayloadHeader::FILE)
        handleFileChunk(packet, body);
    else
        handleByteChunk(packet, body);
}

void QuickShareConnection::handleFileChunk(const PayloadTransferFrame& packet, const QByteArray& body) {
    const auto& chunk = packet.payload_chunk();
    const bool last = (chunk.flags() & PayloadTransferFrame::PayloadChunk::LAST_CHUNK) != 0;

    if (!m_incomingFile.append(chunk.offset(), body, last))
        return;

    emit transferProgress(m_incomingFile.size(), m_incomingFileSize);

    if (last)
        saveIncomingFile();
}

void QuickShareConnection::saveIncomingFile() {
    const QString directory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    QDir().mkpath(directory);

    const QString savePath = directory.isEmpty() ? QString() : uniqueFilePath(directory, m_incomingFileName);
    QFile file(savePath);
    const bool saved = file.open(QIODevice::WriteOnly) && file.write(m_incomingFile.data()) == m_incomingFile.size();
    if (saved)
        file.close();
    else
        qWarning() << u"QuickShareConnection: Failed to save"_s << m_incomingFileName << u"to"_s << savePath;

    m_incomingFilePath = saved ? savePath : QString();
    m_incomingFile.clear();
    finishTransfer(saved);
}

void QuickShareConnection::handleByteChunk(const PayloadTransferFrame& packet, const QByteArray& body) {
    const qint64 payloadId = packet.payload_header().id();
    const auto& chunk = packet.payload_chunk();

    auto buffer = m_payloadBuffers.find(payloadId);
    if (buffer == m_payloadBuffers.end()) {
        if (chunk.offset() != 0)
            return; // a continuation of a payload this connection never saw start
        buffer = m_payloadBuffers.insert(payloadId, PayloadBuffer());
    }

    const bool last = (chunk.flags() & PayloadTransferFrame::PayloadChunk::LAST_CHUNK) != 0;
    if (!buffer->append(chunk.offset(), body, last) || !buffer->complete())
        return;

    sharing::nearby::Frame frame;
    if (frame.ParseFromArray(buffer->data().constData(), static_cast<int>(buffer->data().size())))
        handleSharingFrame(frame);
    m_payloadBuffers.erase(buffer);
}

void QuickShareConnection::handleSharingFrame(const sharing::nearby::Frame& frame) {
    switch (frame.v1().type()) {
    case sharing::nearby::V1Frame::PAIRED_KEY_ENCRYPTION:
        sendEncryptedSharingFrame(sharing::nearby::V1Frame::PAIRED_KEY_RESULT);
        break;
    case sharing::nearby::V1Frame::PAIRED_KEY_RESULT:
        setState(ConnectionAccepted);
        break;
    case sharing::nearby::V1Frame::INTRODUCTION: {
        const auto& introduction = frame.v1().introduction();
        if (introduction.file_metadata_size() == 0)
            break;

        const auto& metadata = introduction.file_metadata(0);
        m_incomingFileName = safeIncomingFileName(QString::fromStdString(metadata.name()));
        m_incomingFileSize = metadata.size();
        emit transferRequested(m_incomingFileName, m_incomingFileSize);
        break;
    }
    case sharing::nearby::V1Frame::RESPONSE: {
        if (frame.v1().connection_response().status() != sharing::nearby::ConnectionResponseFrame::ACCEPT) {
            finishTransfer(false);
            break;
        }
        if (!m_outgoingFilePath.isEmpty())
            sendFilePayload();
        break;
    }
    default:
        break;
    }
}

void QuickShareConnection::sendFilePayload() {
    if (m_outgoingFile.isOpen() || m_outgoingFileQueued || m_finished)
        return;

    m_outgoingFile.setFileName(m_outgoingFilePath);
    if (!m_outgoingFile.open(QIODevice::ReadOnly)) {
        qWarning() << u"QuickShareConnection: Failed to open file to send!"_s << m_outgoingFilePath;
        finishTransfer(false);
        return;
    }

    m_outgoingFileName = QFileInfo(m_outgoingFilePath).fileName();
    m_outgoingOffset = 0;
    pumpOutgoingFile();
}

void QuickShareConnection::pumpOutgoingFile() {
    if (m_outgoingFile.isOpen()) {
        while (!m_outgoingFile.atEnd() && m_socket->bytesToWrite() < sendBufferLimit) {
            const QByteArray chunk = m_outgoingFile.read(chunkSize);
            sendPayloadChunk(m_outgoingFilePayloadId, PayloadTransferFrame::PayloadHeader::FILE, m_outgoingFileSize,
                m_outgoingOffset, false, chunk, m_outgoingFileName);
            m_outgoingOffset += chunk.size();
            emit transferProgress(m_outgoingOffset, m_outgoingFileSize);
        }

        if (m_outgoingFile.atEnd()) {
            m_outgoingFile.close();
            // An empty last chunk terminates the file payload.
            sendPayloadChunk(m_outgoingFilePayloadId, PayloadTransferFrame::PayloadHeader::FILE, m_outgoingFileSize,
                m_outgoingFileSize, true, {}, m_outgoingFileName);
            sendDisconnection();
            m_outgoingFileQueued = true;
        }
    }

    // Report the transfer only once the socket has handed every byte to the peer:
    // the transfer is the file, the terminator and the disconnection after it.
    if (m_outgoingFileQueued && m_socket->bytesToWrite() == 0)
        finishTransfer(true);
}

void QuickShareConnection::sendDisconnection() {
    OfflineFrame frame;
    frame.set_version(OfflineFrame::V1);
    auto* v1 = frame.mutable_v1();
    v1->set_type(V1Frame::DISCONNECTION);
    v1->mutable_disconnection(); // an empty disconnection frame

    sendSecureFrame(frame);
}

void QuickShareConnection::onDisconnected() {
    setState(Disconnected);
    emit closed();
}

void QuickShareConnection::onError(QAbstractSocket::SocketError socketError) {
    Q_UNUSED(socketError);
    qWarning() << u"QuickShareConnection error:"_s << m_socket->errorString();
    finishTransfer(false);
}

} // namespace caelestia::services
