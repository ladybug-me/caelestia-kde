#pragma once

#include <openssl/evp.h>

#include <QByteArray>
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
    void deriveKeys(const QByteArray& peerPublicKeyBytes);
    QByteArray extractSharedSecret(EVP_PKEY* peerKey);

    bool m_handshakeComplete = false;
    bool m_isServer = false;

    EVP_PKEY* m_dhKey = nullptr;

    QByteArray m_clientInitMsgData;
    QByteArray m_serverInitMsgData;
    QByteArray m_clientFinishedMsgData;

    QByteArray m_encodeKey;
    QByteArray m_decodeKey;
    QByteArray m_hmacEncodeKey;
    QByteArray m_hmacDecodeKey;
    QByteArray m_authString;
};

} // namespace caelestia::services
