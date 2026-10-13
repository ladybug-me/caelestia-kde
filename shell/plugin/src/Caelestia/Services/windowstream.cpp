#include "windowstream.hpp"

#include <QDebug>
#include <QElapsedTimer>
#include <QHash>
#include <QList>
#include <QTimer>
#include <limits>

#include "windowscreencast.hpp"

namespace caelestia::services {

namespace {

constexpr int kMaxStreams = 16;

constexpr int kGraceMs = 4000;

struct Entry {
    WindowScreencastRequest* request = nullptr;
    int refCount = 0;
    qint64 releasedAt = 0;
};

QHash<QString, Entry>& streams() {
    static QHash<QString, Entry> s_streams;
    return s_streams;
}

QElapsedTimer& clock() {
    static QElapsedTimer s_clock = [] {
        QElapsedTimer t;
        t.start();
        return t;
    }();
    return s_clock;
}

void destroyEntry(const QString& uuid) {
    auto it = streams().find(uuid);
    if (it == streams().end()) {
        return;
    }
    delete it->request;
    streams().erase(it);
}

/// Drops idle streams whose grace period has expired.
void sweep() {
    const qint64 now = clock().elapsed();
    const auto keys = streams().keys();
    for (const QString& uuid : keys) {
        const Entry& entry = streams()[uuid];
        if (entry.refCount <= 0 && now - entry.releasedAt >= kGraceMs) {
            destroyEntry(uuid);
        }
    }
}

bool evictOldestIdle() {
    QString oldest;
    qint64 oldestAt = std::numeric_limits<qint64>::max();
    for (auto it = streams().constBegin(); it != streams().constEnd(); ++it) {
        if (it->refCount <= 0 && it->releasedAt < oldestAt) {
            oldest = it.key();
            oldestAt = it->releasedAt;
        }
    }
    if (oldest.isEmpty()) {
        return false;
    }
    destroyEntry(oldest);
    return true;
}

QTimer* sweeper() {
    static QTimer* s_sweeper = [] {
        auto* timer = new QTimer;
        timer->setInterval(kGraceMs);
        QObject::connect(timer, &QTimer::timeout, [] {
            sweep();
        });
        timer->start();
        return timer;
    }();
    return s_sweeper;
}

} // namespace

WindowStream::WindowStream(QObject* parent)
    : QObject(parent) {
    sweeper();
    clock();
}

WindowStream::~WindowStream() {
    release();
}

QString WindowStream::address() const {
    return m_address;
}

void WindowStream::setAddress(const QString& address) {
    if (m_address == address) {
        return;
    }
    m_address = address;
    Q_EMIT addressChanged();
    release();
    acquire();
}

bool WindowStream::active() const {
    return m_active;
}

void WindowStream::setActive(bool active) {
    if (m_active == active) {
        return;
    }
    m_active = active;
    Q_EMIT activeChanged();
    if (m_active) {
        acquire();
    } else {
        release();
    }
}

void WindowStream::acquire() {
    if (!m_active || m_address.isEmpty() || !m_held.isEmpty()) {
        return;
    }

    auto it = streams().find(m_address);
    if (it == streams().end()) {
        if (streams().size() >= kMaxStreams && !evictOldestIdle()) {
            qWarning() << "WindowStream: refusing" << m_address << "-" << kMaxStreams
                       << "streams are open and all of them are in use";
            return;
        }

        Entry entry;
        entry.request = new WindowScreencastRequest();
        entry.request->setUuid(m_address);
        it = streams().insert(m_address, entry);
    }

    it->refCount++;
    m_held = m_address;

    // Both signals land on streamChanged, so a consumer binds once and gets the
    // serial whenever it arrives -- which is asynchronous, and may already have
    // happened if this stream was shared or still in its grace period.
    connect(it->request, &WindowScreencastRequest::objectSerialChanged, this, &WindowStream::streamChanged);
    connect(it->request, &WindowScreencastRequest::nodeIdChanged, this, &WindowStream::streamChanged);
    Q_EMIT streamChanged();
}

void WindowStream::release() {
    if (m_held.isEmpty()) {
        return;
    }

    auto it = streams().find(m_held);
    if (it != streams().end()) {
        if (it->request) {
            disconnect(it->request, nullptr, this, nullptr);
        }
        if (--it->refCount <= 0) {
            it->refCount = 0;
            it->releasedAt = clock().elapsed();
        }
    }

    m_held.clear();
    Q_EMIT streamChanged();
}

quint32 WindowStream::nodeId() const {
    const auto it = streams().constFind(m_held);
    return it != streams().constEnd() && it->request ? it->request->nodeId() : 0;
}

quint64 WindowStream::objectSerial() const {
    const auto it = streams().constFind(m_held);
    return it != streams().constEnd() && it->request ? it->request->objectSerial() : 0;
}

bool WindowStream::available() const {
    return objectSerial() != 0 || nodeId() != 0;
}

} // namespace caelestia::services
