// SPDX-License-Identifier: GPL-3.0-only
#include "plasmawindowicon.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <QBuffer>
#include <QCryptographicHash>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QLoggingCategory>
#include <QSocketNotifier>
#include <QStandardPaths>

#include "plasmawindows.hpp"

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
        // The window closed before its icon arrived, so no answer is coming.
        emit failed(uuid);
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
        emit failed(key);
        return;
    }

    // The compositor writes the icon into the far end of a pipe from its own
    // thread, so this cannot be read inline — the write blocks until someone
    // drains it.
    int fds[2];
    if (::pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) {
        qCWarning(logPlasmaWindowIcon) << "could not create a pipe for" << key;
        emit failed(key);
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

            // handleLost() settles the ask when the window goes away, and its pipe still
            // drains afterwards. Dropping the second settle here is what makes the
            // header's "exactly once" true: without it a window that closed mid-read got
            // failed() and then resolved(), and the late resolved() registered an icon
            // for a window that was already gone.
            const bool stillWaiting = m_inFlight.remove(key);

            const QByteArray data = *payload;
            delete payload;
            if (stillWaiting) {
                deliver(key, data);
            }
            return;
        }
    });
}

void PlasmaWindowIcon::deliver(const QString& uuid, const QByteArray& payload) {
    if (payload.isEmpty()) {
        emit failed(uuid);
        return;
    }

    QIcon icon;
    QDataStream stream(payload);
    stream >> icon;
    if (stream.status() != QDataStream::Ok || icon.isNull()) {
        qCDebug(logPlasmaWindowIcon) << "no usable icon for" << uuid;
        emit failed(uuid);
        return;
    }

    const auto image = largestPixmap(icon);
    if (image.isNull()) {
        emit failed(uuid);
        return;
    }

    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "PNG")) {
        qCWarning(logPlasmaWindowIcon) << "could not encode icon for" << uuid;
        emit failed(uuid);
        return;
    }
    buffer.close();

    // Same content-addressed cache the X extractor writes to: naming files
    // after the icon's own bytes means two windows sharing an icon share the
    // file, and no window can ever pick up one belonging to something else.
    const auto cacheRoot =
        QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/caelestia/winicons");
    const auto digest = QString::fromLatin1(QCryptographicHash::hash(png, QCryptographicHash::Sha256).toHex().left(16));
    const auto path = cacheRoot + QStringLiteral("/") + digest + QStringLiteral(".png");

    if (!QFile::exists(path)) {
        QFile file(path);
        if (!QDir().mkpath(cacheRoot) || !file.open(QIODevice::WriteOnly) || file.write(png) != png.size()) {
            qCWarning(logPlasmaWindowIcon) << "could not write icon cache for" << uuid << "to" << path;
            emit failed(uuid);
            return;
        }
    }

    m_resolved.insert(uuid, path);
    emit resolved(uuid, path);
}

} // namespace caelestia::services
