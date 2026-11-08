#pragma once

#include <openssl/evp.h>

#include <QByteArray>
#include <QList>
#include <QString>

namespace caelestia::services {

class QuickShareCrypto {
public:
    QuickShareCrypto();
    ~QuickShareCrypto();

    void initClient();
    void initServer();

    QByteArray processClientInit(const QByteArray& data);
    QByteArray processServerInit(const QByteArray& data);
    bool processClientFinished(const QByteArray& data);

    QByteArray generateClientInit();
    QByteArray generateServerInit();
    QByteArray generateClientFinished();

    /// Wraps plaintext in a DEVICE_TO_DEVICE_MESSAGE SecureMessage, ready to be
    /// length-prefixed onto the wire. Returns an empty array if OpenSSL fails.
    QByteArray sealDeviceToDevice(int sequenceNumber, const QByteArray& plaintext);
    /// Unwraps a SecureMessage from the peer. Returns an empty array if the
    /// signature does not verify or the body cannot be decrypted.
    QByteArray openDeviceToDevice(const QByteArray& secureMessage);

    bool isHandshakeComplete() const { return m_handshakeComplete; }

    bool isClient() const { return !m_isServer; }

    QString pinCode() const;

private:
    void generateDhKeypair();
    /// Derives the session keys from the peer's point. False when the point is not
    /// a valid P-256 point or the shared secret cannot be computed, in which case
    /// no key is installed and the handshake must fail.
    bool deriveKeys(const QByteArray& peerPublicKeyBytes);
    QByteArray extractSharedSecret(EVP_PKEY* peerKey);

    bool m_handshakeComplete = false;
    bool m_isServer = false;

    EVP_PKEY* m_dhKey = nullptr;

    QByteArray m_clientInitMsgData;
    QByteArray m_serverInitMsgData;
    QByteArray m_clientFinishedMsgData;

    /// The commitments a client offered in CLIENT_INIT, checked against the
    /// CLIENT_FINISH it later sends.
    QList<QByteArray> m_clientCommitments;

    /// The last sequence number seen from the peer. Device-to-device frames must
    /// increase, so a replayed or reordered frame is refused.
    int m_lastRecvSequence = 0;
    bool m_hasRecvSequence = false;

    QByteArray m_encodeKey;
    QByteArray m_decodeKey;
    QByteArray m_hmacEncodeKey;
    QByteArray m_hmacDecodeKey;
    QByteArray m_authString;
};

} // namespace caelestia::services
