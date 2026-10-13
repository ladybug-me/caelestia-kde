#include "QuickShareEndpointInfo.hpp"

#include <QRandomGenerator>

namespace caelestia::services::endpointinfo {

namespace {

/// The device type these records advertise (a laptop), in the high bits of the
/// first byte, with the visibility bit below it.
constexpr char deviceType = 3 << 1;

/// The record's fixed part: the device type byte, a random id, then a name at the
/// length-prefixed tail.
constexpr int idSize = 16;
constexpr int nameLengthOffset = 1 + idSize;
constexpr int nameOffset = nameLengthOffset + 1;

constexpr int visibilityBit = 3;

QByteArray randomBytes(int count) {
    QByteArray bytes;
    bytes.reserve(count);
    for (int i = 0; i < count; i++)
        bytes.append(static_cast<char>(QRandomGenerator::global()->generate()));
    return bytes;
}

} // namespace

QByteArray encode(const QString& deviceName) {
    QByteArray record;
    record.append(deviceType);
    record.append(randomBytes(idSize));

    QByteArray name = deviceName.toUtf8();
    if (name.length() > 255)
        name.truncate(255);
    record.append(static_cast<char>(name.length()));
    record.append(name);
    return record;
}

QString deviceName(const QByteArray& record) {
    if (record.size() < nameOffset)
        return {};

    const int length = static_cast<unsigned char>(record.at(nameLengthOffset));
    if (length <= 0 || record.size() < nameOffset + length)
        return {};

    return QString::fromUtf8(record.constData() + nameOffset, length);
}

bool isVisible(const QByteArray& record) {
    if (record.isEmpty())
        return false;

    return ((static_cast<unsigned char>(record.at(0)) >> visibilityBit) & 0x01) == 0;
}

QList<QByteArray> txtRecord(const QString& deviceName) {
    return { QByteArrayLiteral("n=") + toBase64Url(encode(deviceName)).toUtf8() };
}

QString toBase64Url(const QByteArray& bytes) {
    return QString::fromLatin1(bytes.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

QByteArray fromBase64Url(const QByteArray& encoded) {
    QByteArray decoded =
        QByteArray::fromBase64(encoded, QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
    if (decoded.isEmpty())
        decoded = QByteArray::fromBase64(encoded, QByteArray::Base64UrlEncoding);
    if (decoded.isEmpty())
        decoded = QByteArray::fromBase64(encoded);
    return decoded;
}

} // namespace caelestia::services::endpointinfo
