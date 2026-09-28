#pragma once

#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qlocalsocket.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qsharedpointer.h>
#include <qvariant.h>

namespace caelestia::services {

class HyprlandState : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList windowList READ windowList NOTIFY windowListChanged)
    Q_PROPERTY(QVariantMap windowByAddress READ windowByAddress NOTIFY windowListChanged)
    Q_PROPERTY(QVariantList addresses READ addresses NOTIFY windowListChanged)

    Q_PROPERTY(QVariantList workspaces READ workspaces NOTIFY workspacesChanged)
    Q_PROPERTY(QVariantMap workspaceById READ workspaceById NOTIFY workspacesChanged)
    Q_PROPERTY(QVariantList workspaceIds READ workspaceIds NOTIFY workspacesChanged)

    Q_PROPERTY(QVariantMap activeWorkspace READ activeWorkspace NOTIFY activeWorkspaceChanged)
    Q_PROPERTY(QVariantMap activeWindow READ activeWindow NOTIFY activeWindowChanged)
    Q_PROPERTY(QVariantList monitors READ monitors NOTIFY monitorsChanged)
    Q_PROPERTY(QVariantMap layers READ layers NOTIFY layersChanged)

    /// True when the KDE (PlasmaWindows) bridge is serving the window data.
    /// workspaces, activeWorkspace, monitors and layers stay empty in that mode:
    /// there is no KDE source for them, so branch on this before reading them.
    Q_PROPERTY(bool kdeFallback READ kdeFallback CONSTANT)

public:
    explicit HyprlandState(QObject* parent = nullptr);

    [[nodiscard]] QVariantList windowList() const;
    [[nodiscard]] QVariantMap windowByAddress() const;
    [[nodiscard]] QVariantList addresses() const;

    [[nodiscard]] QVariantList workspaces() const;
    [[nodiscard]] QVariantMap workspaceById() const;
    [[nodiscard]] QVariantList workspaceIds() const;

    [[nodiscard]] QVariantMap activeWorkspace() const;
    [[nodiscard]] QVariantMap activeWindow() const;
    [[nodiscard]] QVariantList monitors() const;
    [[nodiscard]] QVariantMap layers() const;
    [[nodiscard]] bool kdeFallback() const;

    Q_INVOKABLE void updateAll();
    Q_INVOKABLE void updateWindowList();
    Q_INVOKABLE void updateWorkspaces();
    Q_INVOKABLE void updateMonitors();
    Q_INVOKABLE void updateLayers();
    Q_INVOKABLE void updateActiveWorkspace();

signals:
    void windowListChanged();
    void workspacesChanged();
    void activeWorkspaceChanged();
    void activeWindowChanged();
    void monitorsChanged();
    void layersChanged();

private:
    using SocketPtr = QSharedPointer<QLocalSocket>;

    QString m_requestSocket;
    QString m_eventSocket;
    QLocalSocket* m_socket;
    bool m_socketValid;

    // KDE (PlasmaWindows) bridge is serving the window data instead of Hyprland.
    bool m_kdeFallback = false;
    bool m_warnedNoRequestSocket = false;

    QVariantList m_windowList;
    QVariantMap m_windowByAddress;
    QVariantList m_addresses;

    QVariantList m_workspaces;
    QVariantMap m_workspaceById;
    QVariantList m_workspaceIds;

    QVariantMap m_activeWorkspace;
    QVariantMap m_activeWindow;
    QVariantList m_monitors;
    QVariantMap m_layers;

    SocketPtr m_clientsRefresh;
    SocketPtr m_workspacesRefresh;
    SocketPtr m_monitorsRefresh;
    SocketPtr m_layersRefresh;
    SocketPtr m_activeWorkspaceRefresh;

    void socketError(QLocalSocket::LocalSocketError error) const;
    void socketStateChanged(QLocalSocket::LocalSocketState state);
    void readEvent();
    void handleEvent(const QString& event);
    void onKWinWindowListChanged();
    void onKWinActiveWindowChanged();

    SocketPtr makeRequestJson(const QString& request, const std::function<void(bool, QJsonDocument)>& callback);
    SocketPtr makeRequest(const QString& request, const std::function<void(bool, QByteArray)>& callback);
};

} // namespace caelestia::services
