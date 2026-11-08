#include "QuickShareCrypto.hpp"

#include <openssl/ec.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/kdf.h>
#include <openssl/obj_mac.h>
#include <openssl/rand.h>
#include <openssl/sha.h>

#include <QDebug>
#include <QList>
#include <cstring>
#include <string>

#include "QuickShareProto.hpp"
#include "device_to_device_messages.pb.h"
#include "securegcm.pb.h"
#include "securemessage.pb.h"
#include "ukey.pb.h"

using Qt::StringLiterals::operator""_s;

namespace caelestia::services {

/// The P-256 point of `key` as the GenericPublicKey the handshake carries, or an
/// empty array if OpenSSL cannot export it.
static QByteArray serializePublicKey(EVP_PKEY* key) {
    EC_KEY* ecKey = key ? EVP_PKEY_get1_EC_KEY(key) : nullptr;
    if (!ecKey)
        return {};

    const EC_GROUP* group = EC_KEY_get0_group(ecKey);
    const EC_POINT* point = EC_KEY_get0_public_key(ecKey);
    const size_t length = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, nullptr, 0, nullptr);
    QByteArray pointBytes(static_cast<qsizetype>(length), '\0');
    EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, reinterpret_cast<unsigned char*>(pointBytes.data()),
        length, nullptr);
    EC_KEY_free(ecKey);

    // A coordinate is big-endian two's complement, so one whose top bit is set
    // needs a leading zero byte to stay positive.
    const auto coordinate = [](const QByteArray& raw) {
        std::string encoded;
        if (static_cast<unsigned char>(raw.at(0)) >= 0x80)
            encoded += '\0';
        encoded.append(raw.constData(), raw.size());
        return encoded;
    };

    securemessage::EcP256PublicKey ecPublicKey;
    ecPublicKey.set_x(coordinate(pointBytes.mid(1, 32)));
    ecPublicKey.set_y(coordinate(pointBytes.mid(33, 32)));

    securemessage::GenericPublicKey genericPublicKey;
    genericPublicKey.set_type(securemessage::EC_P256);
    *genericPublicKey.mutable_ec_p256_public_key() = ecPublicKey;
    return serialize(genericPublicKey);
}

/// The uncompressed point the serialized GenericPublicKey `bytes` names, or an
/// empty array if they do not name a P-256 key. Sizes are checked here so a
/// malformed coordinate cannot turn into a truncated point.
static QByteArray peerPublicKey(const std::string& bytes) {
    securemessage::GenericPublicKey genericPublicKey;
    if (!genericPublicKey.ParseFromString(bytes) || genericPublicKey.type() != securemessage::EC_P256)
        return {};

    const auto coordinate = [](std::string raw) {
        if (raw.size() == 33 && raw[0] == '\0')
            raw.erase(raw.begin());
        if (raw.size() != 32)
            return QByteArray();
        return QByteArray(raw.data(), static_cast<qsizetype>(raw.size()));
    };

    const QByteArray x = coordinate(genericPublicKey.ec_p256_public_key().x());
    const QByteArray y = coordinate(genericPublicKey.ec_p256_public_key().y());
    if (x.isEmpty() || y.isEmpty())
        return {};

    QByteArray point;
    point.append(static_cast<char>(0x04)); // an uncompressed point: x then y
    point.append(x);
    point.append(y);
    return point;
}

static QByteArray hkdfInternal(
    const EVP_MD* md, const QByteArray& salt, const QByteArray& ikm, const QByteArray& info, size_t outLen) {
    EVP_PKEY_CTX* pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, nullptr);
    if (!pctx)
        return QByteArray();
    if (EVP_PKEY_derive_init(pctx) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return QByteArray();
    }
    if (EVP_PKEY_CTX_set_hkdf_md(pctx, md) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return QByteArray();
    }
    if (!salt.isEmpty()) {
        if (EVP_PKEY_CTX_set1_hkdf_salt(pctx, reinterpret_cast<const unsigned char*>(salt.constData()), salt.size()) <=
            0) {
            EVP_PKEY_CTX_free(pctx);
            return QByteArray();
        }
    }
    if (EVP_PKEY_CTX_set1_hkdf_key(pctx, reinterpret_cast<const unsigned char*>(ikm.constData()), ikm.size()) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return QByteArray();
    }
    if (!info.isEmpty()) {
        if (EVP_PKEY_CTX_add1_hkdf_info(pctx, reinterpret_cast<const unsigned char*>(info.constData()), info.size()) <=
            0) {
            EVP_PKEY_CTX_free(pctx);
            return QByteArray();
        }
    }
    QByteArray out;
    out.resize(outLen);
    size_t out_len = outLen;
    if (EVP_PKEY_derive(pctx, reinterpret_cast<unsigned char*>(out.data()), &out_len) <= 0) {
        EVP_PKEY_CTX_free(pctx);
        return QByteArray();
    }
    EVP_PKEY_CTX_free(pctx);
    return out;
}

static QByteArray hkdfSha256(const QByteArray& salt, const QByteArray& ikm, const QByteArray& info, size_t outLen) {
    return hkdfInternal(EVP_sha256(), salt, ikm, info, outLen);
}

QuickShareCrypto::QuickShareCrypto() {}

QuickShareCrypto::~QuickShareCrypto() {
    if (m_dhKey) {
        EVP_PKEY_free(m_dhKey);
    }
}

void QuickShareCrypto::generateDhKeypair() {
    if (m_dhKey) {
        EVP_PKEY_free(m_dhKey);
        m_dhKey = nullptr;
    }
    EVP_PKEY_CTX* pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, nullptr);
    EVP_PKEY_keygen_init(pctx);
    EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pctx, NID_X9_62_prime256v1);
    EVP_PKEY_keygen(pctx, &m_dhKey);
    EVP_PKEY_CTX_free(pctx);
}

bool QuickShareCrypto::deriveKeys(const QByteArray& peerPublicKeyBytes) {
    EVP_PKEY* peerKey = nullptr;
    EC_GROUP* group = EC_GROUP_new_by_curve_name(NID_X9_62_prime256v1);
    bool valid = false;
    if (group) {
        EC_POINT* point = EC_POINT_new(group);
        BN_CTX* bnContext = BN_CTX_new();
        if (point && bnContext &&
            EC_POINT_oct2point(group, point, reinterpret_cast<const unsigned char*>(peerPublicKeyBytes.constData()),
                peerPublicKeyBytes.size(), bnContext) == 1 &&
            EC_POINT_is_at_infinity(group, point) == 0 && EC_POINT_is_on_curve(group, point, bnContext) == 1) {
            EC_KEY* ecKey = EC_KEY_new();
            if (ecKey && EC_KEY_set_group(ecKey, group) == 1 && EC_KEY_set_public_key(ecKey, point) == 1 &&
                EC_KEY_check_key(ecKey) == 1) {
                peerKey = EVP_PKEY_new();
                EVP_PKEY_assign_EC_KEY(peerKey, ecKey);
                valid = true;
            } else if (ecKey) {
                EC_KEY_free(ecKey);
            }
        }
        BN_CTX_free(bnContext);
        EC_POINT_free(point);
        EC_GROUP_free(group);
    }

    if (!valid) {
        qWarning() << u"QuickShareCrypto: the peer key is not a valid P-256 point"_s;
        return false;
    }

    const QByteArray sharedSecret = extractSharedSecret(peerKey);
    EVP_PKEY_free(peerKey);
    if (sharedSecret.isEmpty()) {
        qWarning() << u"QuickShareCrypto: could not derive the shared secret"_s;
        return false;
    }

    QByteArray derivedSecret;
    derivedSecret.resize(32);
    unsigned int mdLen = 0;
    EVP_MD_CTX* mdctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr);
    EVP_DigestUpdate(mdctx, sharedSecret.constData(), sharedSecret.size());
    EVP_DigestFinal_ex(mdctx, reinterpret_cast<unsigned char*>(derivedSecret.data()), &mdLen);
    EVP_MD_CTX_free(mdctx);

    QByteArray ukeyInfo = m_clientInitMsgData + m_serverInitMsgData;

    QByteArray authString = hkdfSha256("UKEY2 v1 auth", derivedSecret, ukeyInfo, 32);
    QByteArray nextSecret = hkdfSha256("UKEY2 v1 next", derivedSecret, ukeyInfo, 32);

    m_authString = authString;

    QByteArray salt1 = QByteArray::fromHex("82AA55A0D397F88346CA1CEE8D3909B95F13FA7DEB1D4AB38376B8256DA85510");
    QByteArray d2dClient = hkdfSha256(salt1, nextSecret, QByteArray("client"), 32);
    QByteArray d2dServer = hkdfSha256(salt1, nextSecret, QByteArray("server"), 32);

    QByteArray salt2 = QByteArray::fromHex("BF9D2A53C63616D75DB0A7165B91C1EF73E537F2427405FA23610A4BE657642E");
    QByteArray clientKey = hkdfSha256(salt2, d2dClient, QByteArray("ENC:2"), 32);
    QByteArray clientHmacKey = hkdfSha256(salt2, d2dClient, QByteArray("SIG:1"), 32);
    QByteArray serverKey = hkdfSha256(salt2, d2dServer, QByteArray("ENC:2"), 32);
    QByteArray serverHmacKey = hkdfSha256(salt2, d2dServer, QByteArray("SIG:1"), 32);

    if (m_isServer) {
        m_encodeKey = serverKey;
        m_hmacEncodeKey = serverHmacKey;
        m_decodeKey = clientKey;
        m_hmacDecodeKey = clientHmacKey;
    } else {
        m_encodeKey = clientKey;
        m_hmacEncodeKey = clientHmacKey;
        m_decodeKey = serverKey;
        m_hmacDecodeKey = serverHmacKey;
    }

    return true;
}

QString QuickShareCrypto::pinCode() const {
    const int kHashModulo = 9973;
    const int kHashBaseMultiplier = 31;

    int hash = 0;
    int multiplier = 1;
    for (unsigned char byte : m_authString) {
        int signedByte = static_cast<int>(static_cast<signed char>(byte));
        hash = (hash + signedByte * multiplier) % kHashModulo;
        multiplier = (multiplier * kHashBaseMultiplier) % kHashModulo;
    }

    return QString(u"%1"_s).arg(abs(hash), 4, 10, QLatin1Char('0'));
}

QByteArray QuickShareCrypto::extractSharedSecret(EVP_PKEY* peerKey) {
    if (!m_dhKey || !peerKey)
        return QByteArray();
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new(m_dhKey, nullptr);
    if (!ctx)
        return QByteArray();
    QByteArray secret;
    size_t secretLen = 0;
    if (EVP_PKEY_derive_init(ctx) <= 0 || EVP_PKEY_derive_set_peer(ctx, peerKey) <= 0 ||
        EVP_PKEY_derive(ctx, nullptr, &secretLen) <= 0 || secretLen == 0) {
        EVP_PKEY_CTX_free(ctx);
        return QByteArray();
    }
    secret.resize(secretLen);
    if (EVP_PKEY_derive(ctx, (unsigned char*)secret.data(), &secretLen) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        return QByteArray();
    }
    EVP_PKEY_CTX_free(ctx);
    return secret;
}

void QuickShareCrypto::initClient() {
    m_isServer = false;
    m_handshakeComplete = false;
    generateDhKeypair();
}

void QuickShareCrypto::initServer() {
    m_isServer = true;
    m_handshakeComplete = false;
    generateDhKeypair();
}

QByteArray QuickShareCrypto::processClientInit(const QByteArray& data) {
    m_clientInitMsgData = data;
    securegcm::Ukey2Message msg;
    if (!msg.ParseFromArray(data.constData(), data.size()))
        return QByteArray();
    if (msg.message_type() != securegcm::Ukey2Message::CLIENT_INIT)
        return QByteArray();

    securegcm::Ukey2ClientInit clientInit;
    if (!clientInit.ParseFromString(msg.message_data()))
        return QByteArray();

    // The commitment is the client's promise about the CLIENT_FINISH it will send
    // later; keeping it lets processClientFinished refuse a swapped public key.
    m_clientCommitments.clear();
    for (const auto& commitment : clientInit.cipher_commitments()) {
        if (commitment.handshake_cipher() == securegcm::P256_SHA512)
            m_clientCommitments.append(
                QByteArray(commitment.commitment().data(), static_cast<qsizetype>(commitment.commitment().size())));
    }

    return generateServerInit();
}

QByteArray QuickShareCrypto::processServerInit(const QByteArray& data) {
    m_serverInitMsgData = data;
    securegcm::Ukey2Message msg;
    if (!msg.ParseFromArray(data.constData(), data.size()))
        return QByteArray();
    if (msg.message_type() != securegcm::Ukey2Message::SERVER_INIT)
        return QByteArray();

    securegcm::Ukey2ServerInit serverInit;
    if (!serverInit.ParseFromString(msg.message_data()))
        return QByteArray();

    const QByteArray peerKey = peerPublicKey(serverInit.public_key());
    if (peerKey.isEmpty() || !deriveKeys(peerKey))
        return QByteArray();

    m_handshakeComplete = true;
    return generateClientFinished();
}

bool QuickShareCrypto::processClientFinished(const QByteArray& data) {
    securegcm::Ukey2Message msg;
    if (!msg.ParseFromArray(data.constData(), data.size()))
        return false;
    if (msg.message_type() != securegcm::Ukey2Message::CLIENT_FINISH)
        return false;

    securegcm::Ukey2ClientFinished clientFinished;
    if (!clientFinished.ParseFromString(msg.message_data()))
        return false;

    // Verify the commitment made in CLIENT_INIT over these exact bytes before the
    // key they carry can become the session key.
    unsigned char digest[SHA512_DIGEST_LENGTH];
    SHA512(reinterpret_cast<const unsigned char*>(data.constData()), static_cast<size_t>(data.size()), digest);
    bool committed = false;
    for (const auto& commitment : m_clientCommitments) {
        if (commitment.size() == SHA512_DIGEST_LENGTH &&
            CRYPTO_memcmp(commitment.constData(), digest, SHA512_DIGEST_LENGTH) == 0) {
            committed = true;
            break;
        }
    }
    if (!committed) {
        qWarning() << u"QuickShareCrypto: CLIENT_FINISH does not match the CLIENT_INIT commitment"_s;
        return false;
    }

    const QByteArray peerKey = peerPublicKey(clientFinished.public_key());
    if (peerKey.isEmpty() || !deriveKeys(peerKey))
        return false;

    m_handshakeComplete = true;
    return true;
}

QByteArray QuickShareCrypto::generateClientInit() {
    securegcm::Ukey2ClientFinished clientFinished;
    const QByteArray publicKey = serializePublicKey(m_dhKey);
    clientFinished.set_public_key(publicKey.constData(), publicKey.size());

    securegcm::Ukey2Message finishFrame;
    finishFrame.set_message_type(securegcm::Ukey2Message::CLIENT_FINISH);
    finishFrame.set_message_data(clientFinished.SerializeAsString());
    m_clientFinishedMsgData = serialize(finishFrame);

    // The commitment is the hash of the frame carrying that public key.
    unsigned char hash[SHA512_DIGEST_LENGTH];
    SHA512(reinterpret_cast<const unsigned char*>(m_clientFinishedMsgData.constData()),
        static_cast<size_t>(m_clientFinishedMsgData.size()), hash);

    securegcm::Ukey2ClientInit clientInit;
    clientInit.set_version(1);
    QByteArray random(32, '\0');
    RAND_bytes(reinterpret_cast<unsigned char*>(random.data()), static_cast<int>(random.size()));
    clientInit.set_random(random.constData(), random.size());
    clientInit.set_next_protocol("AES_256_CBC-HMAC_SHA256");

    auto* commitment = clientInit.add_cipher_commitments();
    commitment->set_handshake_cipher(securegcm::P256_SHA512);
    commitment->set_commitment(reinterpret_cast<const char*>(hash), SHA512_DIGEST_LENGTH);

    securegcm::Ukey2Message msg;
    msg.set_message_type(securegcm::Ukey2Message::CLIENT_INIT);
    msg.set_message_data(clientInit.SerializeAsString());

    m_clientInitMsgData = serialize(msg);
    return m_clientInitMsgData;
}

QByteArray QuickShareCrypto::generateServerInit() {
    securegcm::Ukey2ServerInit serverInit;
    serverInit.set_version(1);
    QByteArray random(32, '\0');
    RAND_bytes(reinterpret_cast<unsigned char*>(random.data()), static_cast<int>(random.size()));
    serverInit.set_random(random.constData(), random.size());
    serverInit.set_handshake_cipher(securegcm::P256_SHA512);

    const QByteArray publicKey = serializePublicKey(m_dhKey);
    serverInit.set_public_key(publicKey.constData(), publicKey.size());

    securegcm::Ukey2Message msg;
    msg.set_message_type(securegcm::Ukey2Message::SERVER_INIT);
    msg.set_message_data(serverInit.SerializeAsString());

    m_serverInitMsgData = serialize(msg);
    return m_serverInitMsgData;
}

QByteArray QuickShareCrypto::generateClientFinished() {
    return m_clientFinishedMsgData;
}

QByteArray QuickShareCrypto::sealDeviceToDevice(int sequenceNumber, const QByteArray& plaintext) {
    securegcm::DeviceToDeviceMessage message;
    message.set_message(plaintext.constData(), plaintext.size());
    message.set_sequence_number(sequenceNumber);

    QByteArray body = serialize(message);
    if (body.isEmpty())
        return {};

    QByteArray iv(16, '\0');
    if (RAND_bytes(reinterpret_cast<unsigned char*>(iv.data()), static_cast<int>(iv.size())) != 1)
        return {};

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx)
        return {};
    QByteArray ciphertext(body.size() + EVP_CIPHER_block_size(EVP_aes_256_cbc()), '\0');
    int written = 0;
    int padding = 0;
    const bool encrypted =
        EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), nullptr,
            reinterpret_cast<const unsigned char*>(m_encodeKey.constData()),
            reinterpret_cast<const unsigned char*>(iv.constData())) == 1 &&
        EVP_EncryptUpdate(ctx, reinterpret_cast<unsigned char*>(ciphertext.data()), &written,
            reinterpret_cast<const unsigned char*>(body.constData()), static_cast<int>(body.size())) == 1 &&
        EVP_EncryptFinal_ex(ctx, reinterpret_cast<unsigned char*>(ciphertext.data()) + written, &padding) == 1;
    EVP_CIPHER_CTX_free(ctx);
    if (!encrypted)
        return {};
    ciphertext.resize(written + padding);

    securemessage::Header header;
    header.set_signature_scheme(securemessage::HMAC_SHA256);
    header.set_encryption_scheme(securemessage::AES_256_CBC);
    header.set_iv(iv.constData(), iv.size());

    securegcm::GcmMetadata metadata;
    metadata.set_type(securegcm::DEVICE_TO_DEVICE_MESSAGE);
    metadata.set_version(1);
    const QByteArray metadataBytes = serialize(metadata);
    if (metadataBytes.isEmpty())
        return {};
    header.set_public_metadata(metadataBytes.constData(), metadataBytes.size());

    securemessage::HeaderAndBody headerAndBody;
    *headerAndBody.mutable_header() = header;
    headerAndBody.set_body(ciphertext.constData(), ciphertext.size());

    const QByteArray headerAndBodyBytes = serialize(headerAndBody);
    if (headerAndBodyBytes.isEmpty())
        return {};

    unsigned char signature[EVP_MAX_MD_SIZE];
    unsigned int signatureLength = 0;
    if (!HMAC(EVP_sha256(), m_hmacEncodeKey.constData(), static_cast<int>(m_hmacEncodeKey.size()),
            reinterpret_cast<const unsigned char*>(headerAndBodyBytes.constData()),
            static_cast<size_t>(headerAndBodyBytes.size()), signature, &signatureLength))
        return {};

    securemessage::SecureMessage secureMessage;
    secureMessage.set_header_and_body(headerAndBodyBytes.constData(), headerAndBodyBytes.size());
    secureMessage.set_signature(signature, signatureLength);

    return serialize(secureMessage);
}

QByteArray QuickShareCrypto::openDeviceToDevice(const QByteArray& secureMessage) {
    securemessage::SecureMessage message;
    if (!message.ParseFromArray(secureMessage.constData(), static_cast<int>(secureMessage.size())))
        return {};

    const QByteArray headerAndBody(
        message.header_and_body().data(), static_cast<qsizetype>(message.header_and_body().size()));

    unsigned char signature[EVP_MAX_MD_SIZE];
    unsigned int signatureLength = 0;
    if (!HMAC(EVP_sha256(), m_hmacDecodeKey.constData(), static_cast<int>(m_hmacDecodeKey.size()),
            reinterpret_cast<const unsigned char*>(headerAndBody.constData()),
            static_cast<size_t>(headerAndBody.size()), signature, &signatureLength))
        return {};
    if (static_cast<int>(signatureLength) != message.signature().size() ||
        memcmp(signature, message.signature().data(), signatureLength) != 0) {
        qWarning() << u"QuickShareCrypto: HMAC verification failed"_s;
        return {};
    }

    securemessage::HeaderAndBody parsed;
    if (!parsed.ParseFromArray(headerAndBody.constData(), static_cast<int>(headerAndBody.size())))
        return {};

    const QByteArray iv(parsed.header().iv().data(), static_cast<qsizetype>(parsed.header().iv().size()));
    const QByteArray ciphertext(parsed.body().data(), static_cast<qsizetype>(parsed.body().size()));

    // The header is the peer's. AES-256-CBC reads exactly one block of IV, so a shorter
    // one - which protobuf happily carries - would have OpenSSL read past the end of this
    // allocation. Nothing here needs a second block either, so anything else is refused.
    const int ivLength = EVP_CIPHER_iv_length(EVP_aes_256_cbc());
    if (ivLength <= 0 || iv.size() != ivLength) {
        qWarning() << u"QuickShareCrypto: refusing a frame whose IV is not "_s << ivLength << u" bytes"_s;
        return {};
    }
    if (m_decodeKey.size() != EVP_CIPHER_key_length(EVP_aes_256_cbc())) {
        qWarning() << u"QuickShareCrypto: no session key to open the frame with"_s;
        return {};
    }
    // A ciphertext has to be a whole number of blocks, or the padding check below is being
    // asked about a body that cannot have been produced by this cipher.
    if (ciphertext.isEmpty() || ciphertext.size() % EVP_CIPHER_block_size(EVP_aes_256_cbc()) != 0) {
        qWarning() << u"QuickShareCrypto: refusing a frame that is not a whole number of blocks"_s;
        return {};
    }

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx)
        return {};
    QByteArray plaintext(ciphertext.size() + EVP_CIPHER_block_size(EVP_aes_256_cbc()), '\0');
    int written = 0;
    int padding = 0;
    const bool decrypted =
        EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), nullptr,
            reinterpret_cast<const unsigned char*>(m_decodeKey.constData()),
            reinterpret_cast<const unsigned char*>(iv.constData())) == 1 &&
        EVP_DecryptUpdate(ctx, reinterpret_cast<unsigned char*>(plaintext.data()), &written,
            reinterpret_cast<const unsigned char*>(ciphertext.constData()), static_cast<int>(ciphertext.size())) == 1 &&
        EVP_DecryptFinal_ex(ctx, reinterpret_cast<unsigned char*>(plaintext.data()) + written, &padding) == 1;
    EVP_CIPHER_CTX_free(ctx);
    if (!decrypted)
        return {};
    plaintext.resize(written + padding);

    securegcm::DeviceToDeviceMessage deviceToDevice;
    if (!deviceToDevice.ParseFromArray(plaintext.constData(), static_cast<int>(plaintext.size())))
        return {};

    // A frame may only be used once and only in order: the sender counts up, so
    // anything that does not advance the count is a replay. The first frame is
    // taken as the origin, since peers need not start the count at the same value.
    if (m_lastRecvSequence && deviceToDevice.sequence_number() <= *m_lastRecvSequence) {
        qWarning() << u"QuickShareCrypto: refusing a replayed or reordered frame"_s;
        return {};
    }
    m_lastRecvSequence = deviceToDevice.sequence_number();

    return QByteArray(deviceToDevice.message().data(), static_cast<qsizetype>(deviceToDevice.message().size()));
}

} // namespace caelestia::services
