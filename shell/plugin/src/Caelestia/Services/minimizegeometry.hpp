// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QQuickItem>
#include <QRect>

namespace caelestia::services {

class MinimizeGeometry : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit MinimizeGeometry(QObject* parent = nullptr);

    Q_INVOKABLE void setGeometry(QQuickItem* anchor, const QString& uuid, int x, int y, int width, int height);

    Q_INVOKABLE void clearGeometry(QQuickItem* anchor, const QString& uuid);

private:
    QHash<QString, QHash<quintptr, QRect>> m_published;
};

} // namespace caelestia::services
