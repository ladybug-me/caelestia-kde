#pragma once

// Requests a live PipeWire video stream for a single window, identified by the
// same UUID KWin exposes as window.internalId (see KWinActiveWindowBridge) and
// as the window's uuid in KWin's plasma-window-management protocol.
//
// This is the same KDE-native mechanism Plasma's own Task Manager tooltips use
// for taskbar window thumbnails (plasma-workspace/libtaskmanager Screencasting/
// ScreencastingRequest). It requires no xdg-desktop-portal permission prompt
// because zkde_screencast_unstable_v1 is a restricted/privileged Wayland
// protocol that KWin only exposes to clients it trusts (declared via the
// client's X-KDE-Wayland-Interfaces desktop file entry).
//
// Adapted from plasma-workspace/libtaskmanager (screencasting.h/.cpp,
// screencastingrequest.h/.cpp):
// SPDX-FileCopyrightText: 2020 Aleix Pol Gonzalez <aleixpol@kde.org>
// SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL

#include <QObject>
#include <QQmlEngine>
#include <QtWaylandClient/QWaylandClientExtension>
#include <memory>

#include "qwayland-zkde-screencast-unstable-v1.h"

namespace caelestia::services {

class WindowScreencastStream : public QObject, public QtWayland::zkde_screencast_stream_unstable_v1 {
    Q_OBJECT

public:
    WindowScreencastStream();
    ~WindowScreencastStream() override;

signals:
    void created(quint32 nodeId);
    void objectSerialArrived(quint64 objectSerial);
    void failed(const QString& error);
    void closed();

protected:
    void zkde_screencast_stream_unstable_v1_created(uint32_t node) override;
    void zkde_screencast_stream_unstable_v1_closed() override;
    void zkde_screencast_stream_unstable_v1_failed(const QString& error) override;
    void zkde_screencast_stream_unstable_v1_serial(uint32_t object_serial_hi, uint32_t object_serial_low) override;
};

class WindowScreencastGlobal : public QWaylandClientExtensionTemplate<WindowScreencastGlobal>,
                               public QtWayland::zkde_screencast_unstable_v1 {
    Q_OBJECT

public:
    static WindowScreencastGlobal* instance();

    WindowScreencastGlobal();
    ~WindowScreencastGlobal() override;

    std::unique_ptr<WindowScreencastStream> createWindowStream(const QString& uuid);
    std::unique_ptr<WindowScreencastStream> createOutputStream(wl_output* output);
};

class WindowScreencastRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString uuid READ uuid WRITE setUuid NOTIFY uuidChanged)
    Q_PROPERTY(quint32 nodeId READ nodeId NOTIFY nodeIdChanged)
    Q_PROPERTY(quint64 objectSerial READ objectSerial NOTIFY objectSerialChanged)
    QML_ELEMENT

public:
    explicit WindowScreencastRequest(QObject* parent = nullptr);
    ~WindowScreencastRequest() override;

    QString uuid() const;
    void setUuid(const QString& uuid);

    quint32 nodeId() const;
    quint64 objectSerial() const;

signals:
    void uuidChanged();
    void nodeIdChanged();
    void objectSerialChanged();

private:
    void setStream(std::unique_ptr<WindowScreencastStream> stream);
    void setNodeId(quint32 nodeId);
    void setObjectSerial(quint64 objectSerial);

    std::unique_ptr<WindowScreencastStream> m_stream;
    QString m_uuid;
    quint32 m_nodeId = 0;
    quint64 m_objectSerial = 0;
};

class OutputScreencastRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString outputName READ outputName WRITE setOutputName NOTIFY outputNameChanged)
    Q_PROPERTY(quint32 nodeId READ nodeId NOTIFY nodeIdChanged)
    Q_PROPERTY(quint64 objectSerial READ objectSerial NOTIFY objectSerialChanged)
    QML_ELEMENT

public:
    explicit OutputScreencastRequest(QObject* parent = nullptr);
    ~OutputScreencastRequest() override;

    QString outputName() const;
    void setOutputName(const QString& outputName);

    quint32 nodeId() const;
    quint64 objectSerial() const;

signals:
    void outputNameChanged();
    void nodeIdChanged();
    void objectSerialChanged();

private:
    void setStream(std::unique_ptr<WindowScreencastStream> stream);
    void setNodeId(quint32 nodeId);
    void setObjectSerial(quint64 objectSerial);

    std::unique_ptr<WindowScreencastStream> m_stream;
    QString m_outputName;
    quint32 m_nodeId = 0;
    quint64 m_objectSerial = 0;
};

} // namespace caelestia::services
