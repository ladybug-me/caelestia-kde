#include "windowscreencast.hpp"

#include <QtGui/qscreen_platform.h>

#include <QDebug>
#include <QGuiApplication>
#include <QScreen>

namespace caelestia::services {

WindowScreencastStream::WindowScreencastStream() = default;

WindowScreencastStream::~WindowScreencastStream() {
    if (isInitialized()) {
        close();
    }
}

void WindowScreencastStream::zkde_screencast_stream_unstable_v1_created(uint32_t node) {
    Q_EMIT created(node);
}

void WindowScreencastStream::zkde_screencast_stream_unstable_v1_closed() {
    Q_EMIT closed();
}

void WindowScreencastStream::zkde_screencast_stream_unstable_v1_failed(const QString& error) {
    Q_EMIT failed(error);
}

void WindowScreencastStream::zkde_screencast_stream_unstable_v1_serial(
    uint32_t object_serial_hi, uint32_t object_serial_low) {
    Q_EMIT objectSerialArrived(static_cast<quint64>(object_serial_hi) << 32 | object_serial_low);
}

WindowScreencastGlobal::WindowScreencastGlobal()
    : QWaylandClientExtensionTemplate<WindowScreencastGlobal>(6) {
    initialize();
    if (!isInitialized() || !isActive()) {
        qWarning() << "WindowScreencastGlobal: zkde_screencast_unstable_v1 is not available"
                   << "(isInitialized:" << isInitialized() << ", isActive:" << isActive() << ")."
                   << "The compositor may not support it (or not at version 6), or this app is"
                      " missing X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1 in its desktop file.";
    } else {
        qDebug() << "WindowScreencastGlobal: zkde_screencast_unstable_v1 bound successfully.";
    }
}

WindowScreencastGlobal* WindowScreencastGlobal::instance() {
    static auto* s_instance = new WindowScreencastGlobal();
    return s_instance;
}

WindowScreencastGlobal::~WindowScreencastGlobal() {
    if (isActive()) {
        destroy();
    }
}

std::unique_ptr<WindowScreencastStream> WindowScreencastGlobal::createWindowStream(const QString& uuid) {
    if (!isActive()) {
        qWarning() << "WindowScreencastGlobal: cannot request stream for" << uuid << "- extension is not active.";
        return nullptr;
    }

    qDebug() << "WindowScreencastGlobal: requesting window stream for uuid" << uuid;
    auto stream = std::make_unique<WindowScreencastStream>();
    stream->init(stream_window(uuid, pointer_hidden));
    return stream;
}

std::unique_ptr<WindowScreencastStream> WindowScreencastGlobal::createOutputStream(wl_output* output) {
    if (!isActive()) {
        qWarning() << "WindowScreencastGlobal: cannot request stream for output - extension is not active.";
        return nullptr;
    }

    if (!output) {
        qWarning() << "WindowScreencastGlobal: provided wl_output is null.";
        return nullptr;
    }

    qDebug() << "WindowScreencastGlobal: requesting output stream";
    auto stream = std::make_unique<WindowScreencastStream>();
    stream->init(stream_output(output, pointer_hidden));
    return stream;
}

WindowScreencastRequest::WindowScreencastRequest(QObject* parent)
    : QObject(parent) {}

WindowScreencastRequest::~WindowScreencastRequest() = default;

QString WindowScreencastRequest::uuid() const {
    return m_uuid;
}

void WindowScreencastRequest::setUuid(const QString& uuid) {
    if (m_uuid == uuid) {
        return;
    }

    setStream(nullptr);
    m_uuid = uuid;
    Q_EMIT uuidChanged();

    if (!m_uuid.isEmpty()) {
        qDebug() << "WindowScreencastRequest: uuid set to" << m_uuid;
        setStream(WindowScreencastGlobal::instance()->createWindowStream(m_uuid));
    }
}

quint32 WindowScreencastRequest::nodeId() const {
    return m_nodeId;
}

quint64 WindowScreencastRequest::objectSerial() const {
    return m_objectSerial;
}

void WindowScreencastRequest::setStream(std::unique_ptr<WindowScreencastStream> stream) {
    if (stream) {
        m_stream = std::move(stream);

        connect(m_stream.get(), &WindowScreencastStream::created, this, [this](quint32 nodeId) {
            qDebug() << "WindowScreencastRequest: created, nodeId =" << nodeId << "for uuid" << m_uuid;
            setNodeId(nodeId);
        });
        connect(m_stream.get(), &WindowScreencastStream::closed, this, [this]() {
            qDebug() << "WindowScreencastRequest: stream closed for uuid" << m_uuid;
            setNodeId(0);
            setObjectSerial(0);
        });
        connect(m_stream.get(), &WindowScreencastStream::failed, this, [this](const QString& error) {
            qWarning() << "WindowScreencastRequest: error creating screencast for uuid" << m_uuid << ":" << error;
        });
        connect(m_stream.get(), &WindowScreencastStream::objectSerialArrived, this, [this](quint64 serial) {
            qDebug() << "WindowScreencastRequest: objectSerial arrived =" << serial << "for uuid" << m_uuid;
            setObjectSerial(serial);
        });
    } else {
        m_stream.reset();
        setNodeId(0);
        setObjectSerial(0);
    }
}

void WindowScreencastRequest::setNodeId(quint32 nodeId) {
    if (nodeId != m_nodeId) {
        m_nodeId = nodeId;
        Q_EMIT nodeIdChanged();
    }
}

void WindowScreencastRequest::setObjectSerial(quint64 objectSerial) {
    if (objectSerial != m_objectSerial) {
        m_objectSerial = objectSerial;
        Q_EMIT objectSerialChanged();
    }
}

OutputScreencastRequest::OutputScreencastRequest(QObject* parent)
    : QObject(parent) {}

OutputScreencastRequest::~OutputScreencastRequest() = default;

QString OutputScreencastRequest::outputName() const {
    return m_outputName;
}

void OutputScreencastRequest::setOutputName(const QString& outputName) {
    if (m_outputName == outputName) {
        return;
    }

    setStream(nullptr);
    m_outputName = outputName;
    Q_EMIT outputNameChanged();

    if (!m_outputName.isEmpty()) {
        qDebug() << "OutputScreencastRequest: outputName set to" << m_outputName;

        QScreen* targetScreen = nullptr;
        for (QScreen* s : QGuiApplication::screens()) {
            if (s->name() == m_outputName) {
                targetScreen = s;
                break;
            }
        }
        if (!targetScreen && !QGuiApplication::screens().isEmpty()) {
            targetScreen = QGuiApplication::primaryScreen();
        }

        if (targetScreen) {
            auto* ws = targetScreen->nativeInterface<QNativeInterface::QWaylandScreen>();
            if (ws && ws->output()) {
                setStream(WindowScreencastGlobal::instance()->createOutputStream(ws->output()));
            } else {
                qWarning() << "OutputScreencastRequest: Failed to get wl_output for screen" << targetScreen->name();
            }
        }
    }
}

quint32 OutputScreencastRequest::nodeId() const {
    return m_nodeId;
}

quint64 OutputScreencastRequest::objectSerial() const {
    return m_objectSerial;
}

void OutputScreencastRequest::setStream(std::unique_ptr<WindowScreencastStream> stream) {
    if (stream) {
        m_stream = std::move(stream);

        connect(m_stream.get(), &WindowScreencastStream::created, this, [this](quint32 nodeId) {
            qDebug() << "OutputScreencastRequest: created, nodeId =" << nodeId << "for output" << m_outputName;
            setNodeId(nodeId);
        });
        connect(m_stream.get(), &WindowScreencastStream::closed, this, [this]() {
            qDebug() << "OutputScreencastRequest: stream closed for output" << m_outputName;
            setNodeId(0);
            setObjectSerial(0);
        });
        connect(m_stream.get(), &WindowScreencastStream::failed, this, [this](const QString& error) {
            qWarning() << "OutputScreencastRequest: error creating screencast for output" << m_outputName << ":"
                       << error;
        });
        connect(m_stream.get(), &WindowScreencastStream::objectSerialArrived, this, [this](quint64 serial) {
            qDebug() << "OutputScreencastRequest: objectSerial arrived =" << serial << "for output" << m_outputName;
            setObjectSerial(serial);
        });
    } else {
        m_stream.reset();
        setNodeId(0);
        setObjectSerial(0);
    }
}

void OutputScreencastRequest::setNodeId(quint32 nodeId) {
    if (nodeId != m_nodeId) {
        m_nodeId = nodeId;
        Q_EMIT nodeIdChanged();
    }
}

void OutputScreencastRequest::setObjectSerial(quint64 objectSerial) {
    if (objectSerial != m_objectSerial) {
        m_objectSerial = objectSerial;
        Q_EMIT objectSerialChanged();
    }
}

} // namespace caelestia::services
