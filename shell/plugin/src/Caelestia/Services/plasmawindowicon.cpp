// SPDX-License-Identifier: GPL-3.0-only
#include "plasmawindowicon.hpp"

#include "plasmawindows.hpp"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QLoggingCategory>
#include <QSocketNotifier>
#include <QStandardPaths>

#include <fcntl.h>
#include <unistd.h>

namespace caelestia::services {

namespace {

Q_LOGGING_CATEGORY(logPlasmaWindowIcon, "caelestia.services.plasmawindowicon");

/// Largest pixmap the icon can give us, so the dock has something to scale down
/// from rather than up.
QImage largestPixmap(const QIcon& icon) {
    const auto sizes = icon.availableSizes();

    //  Ref #759. Discard any icons that are not raw pixel data.
    // (the pipe is for raw pixel data, not theme lookups.)
    if (sizes.isEmpty() && !icon.name().isEmpty()) {
        return {};
    }

    QSize best;
    for (const auto& size : sizes) {
        if (static_cast<qint64>(size.width()) * size.height() > static_cast<qint64>(best.width()) * best.height()) {
            best = size;
        }
    }

    // An icon with no advertised sizes can still be scalable, so ask for
    // something reasonable rather than giving up.
    if (!best.isValid()) {
        best = QSize(256, 256);
    }
    return icon.pixmap(best).toImage();
}

} // namespace

PlasmaWindowIcon::PlasmaWindowIcon(QObject* parent)
    : QObject(parent) {
    connect(PlasmaWindows::instance(), &PlasmaWindows::handleLost, this, [this](const QString& uuid) {
        m_resolved.remove(uuid);
        m_inFlight.remove(uuid);
    });
}

void PlasmaWindowIcon::request(const QString& uuid) {
    if (uuid.isEmpty()) {
        return;
    }

    const auto key = PlasmaWindows::normaliseUuid(uuid);
    if (const auto it = m_resolved.constFind(key); it != m_resolved.constEnd()) {
        emit resolved(key, *it);
        return;
    }
    if (m_inFlight.contains(key)) {
        return;
    }

    auto* handle = PlasmaWindows::instance()->handleFor(key);
    if (!handle) {
        return;
    }

    // The compositor writes the icon into the far end of a pipe from its own
    // thread, so this cannot be read inline — the write blocks until someone
    // drains it.
    int fds[2];
    if (::pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) {
        qCWarning(logPlasmaWindowIcon) << "could not create a pipe for" << key;
        return;
    }

    handle->get_icon(fds[1]);
    // Ours to close: the request duplicates what it needs. Leaving it open
    // would mean never seeing EOF.
    ::close(fds[1]);

    m_inFlight.insert(key);

    const int readFd = fds[0];
    auto* payload = new QByteArray();
    auto* notifier = new QSocketNotifier(readFd, QSocketNotifier::Read, this);

    connect(notifier, &QSocketNotifier::activated, this, [this, notifier, readFd, payload, key]() {
        char chunk[4096];
        for (;;) {
            const auto got = ::read(readFd, chunk, sizeof(chunk));
            if (got > 0) {
                payload->append(chunk, static_cast<int>(got));
                continue;
            }
            if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                return; // more to come
            }

            // 0 is EOF, anything else is a broken pipe; either way we are done.
            notifier->setEnabled(false);
            notifier->deleteLater();
            ::close(readFd);
            m_inFlight.remove(key);

            const QByteArray data = *payload;
            delete payload;
            deliver(key, data);
            return;
        }
    });
}

void PlasmaWindowIcon::deliver(const QString& uuid, const QByteArray& payload) {
    if (payload.isEmpty()) {
        return;
    }

    QIcon icon;
    QDataStream stream(payload);
    stream >> icon;
    if (stream.status() != QDataStream::Ok || icon.isNull()) {
        qCDebug(logPlasmaWindowIcon) << "no usable icon for" << uuid;
        return;
    }

    const auto image = largestPixmap(icon);
    if (image.isNull()) {
        return;
    }

    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "PNG")) {
        qCWarning(logPlasmaWindowIcon) << "could not encode icon for" << uuid;
        return;
    }
    buffer.close();

    // Same content-addressed cache the X extractor writes to: naming files
    // after the icon's own bytes means two windows sharing an icon share the
    // file, and no window can ever pick up one belonging to something else.
    const auto cacheRoot =
        QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/caelestia/winicons");
    const auto digest =
        QString::fromLatin1(QCryptographicHash::hash(png, QCryptographicHash::Sha256).toHex().left(16));
    const auto path = cacheRoot + QStringLiteral("/") + digest + QStringLiteral(".png");

    if (!QFile::exists(path)) {
        QFile file(path);
        if (!QDir().mkpath(cacheRoot) || !file.open(QIODevice::WriteOnly) || file.write(png) != png.size()) {
            qCWarning(logPlasmaWindowIcon) << "could not write icon cache for" << uuid << "to" << path;
            return;
        }
    }

    m_resolved.insert(uuid, path);
    emit resolved(uuid, path);
}

} // namespace caelestia::services
