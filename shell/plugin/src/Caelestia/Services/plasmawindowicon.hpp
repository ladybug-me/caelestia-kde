// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QSet>

namespace caelestia::services {

class PlasmaWindowIcon : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit PlasmaWindowIcon(QObject* parent = nullptr);

    Q_INVOKABLE void request(const QString& uuid);

signals:
    /// @p path is a PNG in the same cache the X extractor writes to.
    void resolved(const QString& uuid, const QString& path);

    void failed(const QString& uuid);

private:
    void deliver(const QString& uuid, const QByteArray& payload);

    QSet<QString> m_inFlight;
    QHash<QString, QString> m_resolved;
};

} // namespace caelestia::services
