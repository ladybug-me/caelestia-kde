// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>

namespace caelestia::services {

class WindowIcon : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit WindowIcon(QObject* parent = nullptr);

    Q_INVOKABLE QString extract(const QString& wmClass, const QString& title = QString(), qint64 pid = 0);

signals:
    /// @p key is the pid as a string when one was given, else the window class.
    void extracted(const QString& key, const QString& path);
};

} // namespace caelestia::services
