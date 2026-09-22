// SPDX-License-Identifier: GPL-3.0-only
#pragma once

// Asks KWin for a window's icon, for windows that cannot be served any other
// way.
//
// The existing extractor reads _NET_WM_ICON straight off the window, which only
// exists for XWayland clients. A native Wayland window with no resolvable
// desktop entry — a game launched through Proton's Wayland path reports its own
// exe name as the app id and matches nothing — has no X window to read and no
// themed icon to look up, so the dock falls back to a generic placeholder.
//
// KWin does know the icon: it resolves it from the app id, from
// xdg_toplevel_icon_v1, or from whatever the client set, and hands it to
// taskbars over plasma-window-management. That is how Plasma's own Task Manager
// draws icons on Wayland (libtaskmanager, waylandtasksmodel.cpp).

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

    /**
     * Ask for the icon of the window with KWin's internal id @p uuid — the same
     * value the KWin bridge reports as a window's address.
     *
     * The compositor answers on a pipe, so this returns immediately and
     * resolved() carries the result. Repeat calls while one is in flight are
     * dropped. Every ask that is not dropped settles exactly once, through
     * resolved() or failed().
     */
    Q_INVOKABLE void request(const QString& uuid);

signals:
    /// @p path is a PNG in the same cache the X extractor writes to.
    void resolved(const QString& uuid, const QString& path);

    /// The ask produced no icon: the window is gone, it had none to give, its
    /// payload did not decode, or the icon could not be written to the cache.
    /// Carries the @p uuid the request was made with, so a caller that asked
    /// can stop waiting on an answer that will not come.
    void failed(const QString& uuid);

private:
    void deliver(const QString& uuid, const QByteArray& payload);

    QSet<QString> m_inFlight;
    // uuid -> path, so a second ask for a window we already have costs nothing.
    QHash<QString, QString> m_resolved;
};

} // namespace caelestia::services
