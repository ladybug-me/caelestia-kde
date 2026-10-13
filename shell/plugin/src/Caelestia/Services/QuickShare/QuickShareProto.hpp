#pragma once

#include <google/protobuf/message_lite.h>

#include <QByteArray>

namespace caelestia::services {

/// The bytes `message` goes on the wire as, or an empty array if protobuf refuses
/// to write it. Every frame these devices exchange is built through here.
inline QByteArray serialize(const google::protobuf::MessageLite& message) {
    QByteArray bytes;
    bytes.resize(static_cast<qsizetype>(message.ByteSizeLong()));
    if (!message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size())))
        return {};
    return bytes;
}

} // namespace caelestia::services
