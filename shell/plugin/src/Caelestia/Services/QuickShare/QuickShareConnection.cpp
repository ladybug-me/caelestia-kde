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

/// The largest frame accepted from a peer. A length prefix is a uint32 the peer
/// chooses, so it is range-checked before it sizes anything: 4 + 0xFFFFFFFD wraps
/// to a tiny number when done in 32 bits, which let an unauthenticated peer make
/// the shell copy and re-copy its whole buffer.
constexpr uint32_t maxFrameSize = 8 * 1024 * 1024;

/// The most payload bytes one peer may make us hold across its buffers.
constexpr qint64 maxBufferedPayload = 64 * 1024 * 1024;

/// How many payloads a peer may have in flight at once.
constexpr int maxPayloadBuffers = 32;

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

/// Opens `fileName` in `directory` under a name nothing else is using. `NewOnly`
/// makes the name ours at the moment of opening, so two peers naming the same file
/// cannot both pick it and nothing already there is truncated.
bool openUniqueFile(QFile& file, const QString& directory, const QString& fileName, QString& path) {
    const QFileInfo info(fileName);
    const QString suffix = info.suffix();
    const QString tail = suffix.isEmpty() ? QString() : u'.' + suffix;

    for (int n = 0;; n++) {
        path = n == 0 ? directory + u'/' + fileName
                      : QString(u"%1/%2 (%3)%4"_s).arg(directory, info.completeBaseName()).arg(n).arg(tail);
        file.setFileName(path);
        if (file.open(QIODevice::WriteOnly | QIODevice::NewOnly))
            return true;
        // A name in use is the expected reason to try again. Anything else says this
        // directory will not take a new file, and another name cannot change that.
        if (!QFile::exists(path))
            return false;
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

QuickShareConnection::PayloadAssembler::Result QuickShareConnection::PayloadAssembler::append(
    qint64 payloadId, qint64 offset, const QByteArray& body, bool last, QByteArray& payload) {
    auto part = m_parts.find(payloadId);
    if (part == m_parts.end()) {
        if (offset != 0)
            return Result::Ignored; // a continuation of a payload this connection never saw start
        if (m_parts.size() >= maxPayloadBuffers)
            return Result::Refused;
        part = m_parts.insert(payloadId, QByteArray());
    } else if (offset != part->size()) {
        return Result::Ignored;
    }

    if (m_bufferedBytes + body.size() > maxBufferedPayload)
        return Result::Refused;

    part->append(body);
    m_bufferedBytes += body.size();

    if (!last)
        return Result::Pending;

    payload = *part;
    m_bufferedBytes -= part->size();
    m_parts.erase(part);
    return Result::Complete;
}

void QuickShareConnection::PayloadAssembler::clear() {
    m_parts.clear();
    m_bufferedBytes = 0;
}

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
    m_payloads.clear();

    // A file that never finished is not the user's file: close it and take the
    // partial copy away rather than leave it in their Downloads.
    if (m_incomingHandle.isOpen()) {
        m_incomingHandle.close();
        if (!m_incomingSavedPath.isEmpty())
            QFile::remove(m_incomingSavedPath);
        m_incomingSavedPath.clear();
    }

    emit transferFinished(success);
}

void QuickShareConnection::failTransfer(const QString& reason) {
    qWarning() << u"QuickShareConnection:"_s << reason;
    m_buffer.clear();
    finishTransfer(false);
    m_socket->disconnectFromHost();
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

    m_incomingAccepted = true;
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

    // Parse in one pass over the newly arrived bytes, then drop the consumed
    // prefix once: removing per frame is quadratic in the number of frames.
    qsizetype offset = 0;
    while (m_buffer.size() - offset >= 4) {
        uint32_t length;
        memcpy(&length, m_buffer.constData() + offset, 4);
        length = qFromBigEndian(length);

        if (length > maxFrameSize) {
            failTransfer(u"refusing a frame of %1 bytes"_s.arg(length));
            return;
        }

        const qsizetype frameSize = 4 + static_cast<qsizetype>(length);
        if (m_buffer.size() - offset < frameSize)
            break;

        const QByteArray frameData = m_buffer.mid(offset + 4, length);
        offset += frameSize;

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

    if (offset > 0)
        m_buffer.remove(0, offset);
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
        if (serverInit.isEmpty()) {
            failTransfer(u"the peer's Ukey2 CLIENT_INIT was refused"_s);
            break;
        }
        writeLengthPrefixed(m_socket, serverInit);
        break;
    }
    case securegcm::Ukey2Message::SERVER_INIT: {
        const QByteArray finished = m_crypto.processServerInit(data);
        if (finished.isEmpty() || !m_crypto.isHandshakeComplete()) {
            failTransfer(u"the peer's Ukey2 SERVER_INIT was refused"_s);
            break;
        }
        writeLengthPrefixed(m_socket, finished);
        sendConnectionResponse();
        setState(PostHandshake);
        break;
    }
    case securegcm::Ukey2Message::CLIENT_FINISH:
        if (!m_crypto.processClientFinished(data)) {
            failTransfer(u"the peer's Ukey2 CLIENT_FINISH was refused"_s);
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

    // The sender only starts after our ACCEPT, so a file that arrives before the
    // user answered is either a racing peer or one that skipped the request.
    if (!m_incomingAccepted) {
        qWarning() << u"QuickShareConnection: refusing a file chunk for an unaccepted transfer"_s;
        return;
    }

    if (!m_incomingHandle.isOpen()) {
        if (chunk.offset() != 0)
            return; // a continuation of a file this connection never started
        if (!openIncomingFile())
            return;
    }

    // A chunk carries the offset it continues from, so a gap or a repeat is refused
    // instead of being written over what is already there.
    if (chunk.offset() != m_incomingOffset) {
        failTransfer(u"a file chunk did not continue the file"_s);
        return;
    }

    // The request named a size, and the user accepted that size. A peer that keeps
    // sending past it is not the transfer they agreed to.
    if (m_incomingFileSize > 0 && m_incomingOffset + body.size() > m_incomingFileSize) {
        failTransfer(u"a file chunk arrived past the announced size"_s);
        return;
    }

    if (m_incomingHandle.write(body) != body.size()) {
        failTransfer(u"failed to write %1"_s.arg(m_incomingSavedPath));
        return;
    }

    m_incomingOffset += body.size();
    emit transferProgress(m_incomingOffset, m_incomingFileSize);

    if (last)
        finishIncomingFile();
}

bool QuickShareConnection::openIncomingFile() {
    const QString directory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (directory.isEmpty() || !QDir().mkpath(directory)) {
        failTransfer(u"no writable download directory"_s);
        return false;
    }

    if (!openUniqueFile(m_incomingHandle, directory, m_incomingFileName, m_incomingSavedPath)) {
        failTransfer(u"could not create a file for %1"_s.arg(m_incomingFileName));
        return false;
    }

    m_incomingOffset = 0;
    return true;
}

void QuickShareConnection::finishIncomingFile() {
    m_incomingHandle.close();
    m_incomingFilePath = m_incomingSavedPath;
    finishTransfer(true);
}

void QuickShareConnection::handleByteChunk(const PayloadTransferFrame& packet, const QByteArray& body) {
    const auto& chunk = packet.payload_chunk();
    const bool last = (chunk.flags() & PayloadTransferFrame::PayloadChunk::LAST_CHUNK) != 0;

    QByteArray payload;
    switch (m_payloads.append(packet.payload_header().id(), chunk.offset(), body, last, payload)) {
    case PayloadAssembler::Result::Refused:
        failTransfer(u"refusing to buffer more payload data than the connection allows"_s);
        return;
    case PayloadAssembler::Result::Complete: {
        sharing::nearby::Frame frame;
        if (frame.ParseFromArray(payload.constData(), static_cast<int>(payload.size())))
            handleSharingFrame(frame);
        return;
    }
    case PayloadAssembler::Result::Ignored:
    case PayloadAssembler::Result::Pending:
        return;
    }
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
    // Whatever was still running ended with the socket. finishTransfer reports at
    // most once and takes a partial download with it, so a transfer that already
    // completed is left alone.
    finishTransfer(false);
    emit closed();
}

void QuickShareConnection::onError(QAbstractSocket::SocketError socketError) {
    Q_UNUSED(socketError);
    qWarning() << u"QuickShareConnection error:"_s << m_socket->errorString();
    finishTransfer(false);
}

} // namespace caelestia::services
