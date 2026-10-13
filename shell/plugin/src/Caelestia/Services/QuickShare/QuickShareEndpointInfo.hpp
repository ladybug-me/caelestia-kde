#pragma once

#include <QByteArray>
#include <QList>
#include <QString>

/// The record two Quick Share devices hand each other before they connect. A
/// connection request carries it as bytes and the mDNS advertisement carries it
/// base64url inside a TXT record, so both ends of both links read it through here
/// instead of at a hand-counted offset.
namespace caelestia::services::endpointinfo {

/// The record naming a device `deviceName`, as a connection request and the mDNS
/// TXT record both carry it.
QByteArray encode(const QString& deviceName);

/// The device name inside `record`, or an empty string if it names none.
QString deviceName(const QByteArray& record);

/// Whether `record` says the device is visible to nearby devices.
bool isVisible(const QByteArray& record);

/// The mDNS TXT record for a device naming itself `deviceName`.
QList<QByteArray> txtRecord(const QString& deviceName);

/// `bytes` as the unpadded base64url these records travel in.
QString toBase64Url(const QByteArray& bytes);

/// The bytes an unpadded base64url string names. Peers differ in how much padding
/// they send, so the variants are tried in turn.
QByteArray fromBase64Url(const QByteArray& encoded);

} // namespace caelestia::services::endpointinfo
