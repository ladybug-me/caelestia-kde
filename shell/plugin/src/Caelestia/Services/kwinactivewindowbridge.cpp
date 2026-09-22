#include "kwinactivewindowbridge.hpp"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QScreen>
#include <QTimer>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>

#include "kwinworkspacestate.hpp"
#include "plasmawindows.hpp"

namespace caelestia::services {

KWinActiveWindowBridge::KWinActiveWindowBridge(QObject* parent)
    : QObject(parent) {

    m_updateTimer.setSingleShot(true);
    m_updateTimer.setInterval(50);
    connect(&m_updateTimer, &QTimer::timeout, this, &KWinActiveWindowBridge::buildWindowList);

    auto* plasmaWindows = PlasmaWindows::instance();
    connect(plasmaWindows, &PlasmaWindows::windowAdded, this, &KWinActiveWindowBridge::onWindowAdded);
    connect(plasmaWindows, &PlasmaWindows::handleLost, this, &KWinActiveWindowBridge::onWindowLost);

    // Clear any stale highlight from a previous session or crash on startup
    clearHighlight();
}

KWinActiveWindowBridge::~KWinActiveWindowBridge() {
    clearHighlight();
}

QVariantMap KWinActiveWindowBridge::activeWindow() const {
    return m_activeWindow;
}

QString KWinActiveWindowBridge::activeOutputName() const {
    return m_activeOutputName;
}

QString KWinActiveWindowBridge::highlightedAddress() const {
    return m_highlightedAddress;
}

void KWinActiveWindowBridge::setActiveOutputName(const QString& outputName) {
    if (m_activeOutputName != outputName) {
        m_activeOutputName = outputName;
        emit activeOutputNameChanged();
    }
}

QVariantList KWinActiveWindowBridge::windowList() const {
    return m_windowList;
}

QVariantList KWinActiveWindowBridge::windowsForWorkspace(const QVariant& workspace, bool includeOnAllWorkspaces) const {
    const bool hasNumberTarget = workspace.type() == QVariant::Int && workspace.toInt() > 0;
    const bool hasStringTarget = workspace.type() == QVariant::String && !workspace.toString().isEmpty();

    QVariantList out;
    for (const QVariant& v : m_windowList) {
        const QVariantMap window = v.toMap();
        const QVariantMap ws = window.value(QStringLiteral("workspace")).toMap();
        if (ws.isEmpty()) { // No workspace info: can't rule it out.
            out.push_back(v);
            continue;
        }
        const QVariant id = ws.value(QStringLiteral("id"));
        const QString uuid = ws.value(QStringLiteral("uuid")).toString();
        const bool onAll = (id.type() == QVariant::Int && id.toInt() == -1) || uuid.isEmpty();
        if (onAll) {
            if (includeOnAllWorkspaces)
                out.push_back(v);
            continue;
        }
        if (!hasNumberTarget && !hasStringTarget) {
            out.push_back(v);
            continue;
        }
        if (hasNumberTarget && id.type() == QVariant::Int && id.toInt() == workspace.toInt()) {
            out.push_back(v);
            continue;
        }
        if (hasStringTarget && uuid == workspace.toString()) {
            out.push_back(v);
            continue;
        }
    }
    return out;
}

QString KWinActiveWindowBridge::pendingFocusAddress() const {
    return m_pendingFocusAddress;
}

QString KWinActiveWindowBridge::cursorOutputName() const {
    const auto message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.kde.KWin"), QStringLiteral("activeOutputName"));
    return QDBusConnection::sessionBus().call(message).arguments().value(0).toString();
}

void KWinActiveWindowBridge::onWindowAdded(const QString& uuid) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(uuid)) {
        connect(handle, &PlasmaWindowHandle::titleChanged, this, &KWinActiveWindowBridge::scheduleWindowListUpdate);
        connect(handle, &PlasmaWindowHandle::appIdChanged, this, &KWinActiveWindowBridge::scheduleWindowListUpdate);
        connect(handle, &PlasmaWindowHandle::geometryChanged, this, &KWinActiveWindowBridge::scheduleWindowListUpdate);
        connect(handle, &PlasmaWindowHandle::stateChanged, this, &KWinActiveWindowBridge::scheduleWindowListUpdate);
        connect(handle, &PlasmaWindowHandle::desktopsChanged, this, &KWinActiveWindowBridge::scheduleWindowListUpdate);
        scheduleWindowListUpdate();
    }
}

void KWinActiveWindowBridge::onWindowLost(const QString& uuid) {
    if (!m_highlightedAddress.isEmpty() && m_highlightedAddress == uuid) {
        clearHighlight();
    }
    scheduleWindowListUpdate();
}

void KWinActiveWindowBridge::scheduleWindowListUpdate() {
    if (!m_updateTimer.isActive()) {
        m_updateTimer.start();
    }
}

void KWinActiveWindowBridge::sendToOutput(const QString& address, const QString& outputName) {
    if (address.isEmpty() || outputName.isEmpty()) {
        return;
    }

    QScreen* target = nullptr;
    for (QScreen* screen : QGuiApplication::screens()) {
        if (screen->name() == outputName) {
            target = screen;
            break;
        }
    }
    if (!target) {
        return;
    }

    QVariantMap window;
    for (const QVariant& entry : m_windowList) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("address")).toString() == address) {
            window = map;
            break;
        }
    }
    if (window.isEmpty()) {
        return;
    }

    const QString currentName = window.value(QStringLiteral("output")).toString();
    QScreen* current = nullptr;
    for (QScreen* screen : QGuiApplication::screens()) {
        if (screen->name() == currentName) {
            current = screen;
            break;
        }
    }
    if (!current || current == target) {
        return;
    }

    // KWin's own "move the window one screen over" actions, driven through
    // kglobalaccel.
    //
    // There is no direct way to ask for this: plasma-window-management moves a
    // window between desktops but not between outputs, and no D-Bus interface
    // exposes it either. These actions do exactly the right thing, they are
    // part of KWin proper rather than anything this shell has to install, and
    // they need no privilege. The cost is that they act on the active window,
    // so the window has to be focused first -- which is what dragging a window
    // to another monitor implies anyway.
    const QPoint from = current->geometry().center();
    const QPoint to = target->geometry().center();
    QString action;
    if (qAbs(to.x() - from.x()) >= qAbs(to.y() - from.y())) {
        action = to.x() > from.x() ? QStringLiteral("Window One Screen to the Right")
                                   : QStringLiteral("Window One Screen to the Left");
    } else {
        action = to.y() > from.y() ? QStringLiteral("Window One Screen Down") : QStringLiteral("Window One Screen Up");
    }

    focusWindow(address);

    // Focus has to have landed before the action fires, or it moves whatever
    // was focused before.
    QTimer::singleShot(120, this, [action]() {
        QDBusMessage msg =
            QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"),
                QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
        msg << action;
        QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
    });
}

QString KWinActiveWindowBridge::getOutputNameForGeometry(int x, int y, int w, int h) const {
    const QRect windowRect(x, y, w, h);

    QScreen* bestScreen = nullptr;
    int maxIntersectArea = 0;

    for (QScreen* screen : QGuiApplication::screens()) {
        const QRect intersect = screen->geometry().intersected(windowRect);
        const int area = intersect.width() * intersect.height();
        if (area > maxIntersectArea) {
            maxIntersectArea = area;
            bestScreen = screen;
        }
    }

    if (!bestScreen) {
        // Nothing overlapped at all - a stale rect, off-screen window, or a
        // screen that just went away. Fall back to the nearest screen by centre
        // so a window is never reported without an output: every per-monitor
        // filter in the shell keys off this name and treats "" as "no screen".
        qreal bestDistance = -1;
        const QPoint windowCentre = windowRect.center();
        for (QScreen* screen : QGuiApplication::screens()) {
            const QPoint delta = screen->geometry().center() - windowCentre;
            const qreal distance =
                static_cast<qreal>(delta.x()) * delta.x() + static_cast<qreal>(delta.y()) * delta.y();
            if (bestDistance < 0 || distance < bestDistance) {
                bestDistance = distance;
                bestScreen = screen;
            }
        }
    }

    return bestScreen ? bestScreen->name() : QString();
}

QVariantMap KWinActiveWindowBridge::windowToVariant(PlasmaWindowHandle* w) const {
    QVariant desktopId = -1;
    QVariant desktopUuid = QString();
    if (!w->desktops().isEmpty()) {
        QString firstDesktop = w->desktops().first();
        bool ok;
        int parsed = firstDesktop.toInt(&ok);
        if (ok) {
            desktopId = parsed;
            desktopUuid = firstDesktop;
        } else {
            // Plasma 6 uses UUIDs for desktops. Pass the UUID string directly to QML.
            desktopUuid = firstDesktop;
            if (auto wsState = KWinWorkspaceState::instance()) {
                int idx = wsState->indexForId(firstDesktop);
                if (idx != -1)
                    desktopId = idx;
            }
        }
    }

    QVariantMap map = { { QStringLiteral("address"), w->uuid() }, { QStringLiteral("pid"), w->pid() },
        { QStringLiteral("title"), w->title() }, { QStringLiteral("class"), w->appId() },
        { QStringLiteral("x"), w->x() }, { QStringLiteral("y"), w->y() }, { QStringLiteral("width"), w->width() },
        { QStringLiteral("height"), w->height() }, { QStringLiteral("fullscreen"), w->isFullscreen() },
        { QStringLiteral("maximized"), w->isMaximized() }, { QStringLiteral("minimized"), w->isMinimized() },
        { QStringLiteral("focused"), w->isActive() },
        { QStringLiteral("floating"), !w->isFullscreen() && !w->isMaximized() }, // Fallback for floating state
        { QStringLiteral("output"), getOutputNameForGeometry(w->x(), w->y(), w->width(), w->height()) },
        { QStringLiteral("workspace"),
            QVariantMap{ { QStringLiteral("id"), desktopId }, { QStringLiteral("uuid"), desktopUuid } } } };
    return map;
}

void KWinActiveWindowBridge::buildWindowList() {
    m_windowList.clear();
    QVariantMap newActiveWindow;
    bool activeWindowFound = false;

    auto* plasmaWindows = PlasmaWindows::instance();
    // qDebug() << "KWinActiveWindowBridge::buildWindowList called, total UUIDs:" <<
    // plasmaWindows->windowUuids().size();
    for (const QString& uuid : plasmaWindows->windowUuids()) {
        if (auto* handle = plasmaWindows->handleFor(uuid)) {
            QVariantMap w = windowToVariant(handle);
            m_windowList.append(w);
            if (handle->isActive()) {
                newActiveWindow = w;
                activeWindowFound = true;
            }
        } else {
            // qDebug() << "KWinActiveWindowBridge: handleFor returned nullptr for uuid" << uuid;
        }
    }

    // qDebug() << "KWinActiveWindowBridge: Emitting windowListChanged with" << m_windowList.size() << "windows.";
    emit windowListChanged();

    if (activeWindowFound && m_activeWindow != newActiveWindow) {
        m_activeWindow = newActiveWindow;
        emit activeWindowChanged();

        // Keep activeOutputName in sync so Hypr.focusedMonitor resolves correctly
        // on multi-monitor setups. Without this it stays empty forever and the QML
        // fallback always picks monitor index 0.
        const QString newOutput = newActiveWindow.value(QStringLiteral("output")).toString();
        if (!newOutput.isEmpty())
            setActiveOutputName(newOutput);

        if (m_activeWindow.value(QStringLiteral("address")).toString() == m_pendingFocusAddress) {
            m_pendingFocusAddress.clear();
            emit pendingFocusAddressChanged();
        }
    } else if (!activeWindowFound && !m_activeWindow.isEmpty()) {
        m_activeWindow.clear();
        emit activeWindowChanged();
    }
}

void KWinActiveWindowBridge::focusWindow(const QString& address) {
    if (!m_highlightedAddress.isEmpty()) {
        clearHighlight();
    }
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        m_pendingFocusAddress = address;
        emit pendingFocusAddressChanged();

        // A minimized window ignores the active flag, so every restore path -
        // dock, overview, window switcher - has to clear that one first.
        handle->setState(QtWayland::org_kde_plasma_window_management::state_minimized, false);
        handle->setState(QtWayland::org_kde_plasma_window_management::state_active, true);
    }
}

void KWinActiveWindowBridge::closeWindow(const QString& address) {
    if (!m_highlightedAddress.isEmpty() && m_highlightedAddress == address) {
        clearHighlight();
    }
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        handle->close();
    }
}

void KWinActiveWindowBridge::minimizeWindow(const QString& address) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        handle->setState(QtWayland::org_kde_plasma_window_management::state_minimized, true);
    }
}

void KWinActiveWindowBridge::maximizeWindow(const QString& address, bool horz, bool vert) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        const auto max = QtWayland::org_kde_plasma_window_management::state_maximized;
        // The plasma-window-management protocol exposes only a combined maximized
        // state — there are no per-axis (horz/vert) flags in the state enum — so
        // any maximize request maps onto the combined flag. The only caller
        // (windowinfo/Buttons.qml) passes both axes equal, so this preserves the
        // maximize/restore behaviour.
        handle->setState(max, horz || vert);
    }
}

void KWinActiveWindowBridge::raiseWindow(const QString& address) {
    focusWindow(address);
}

void KWinActiveWindowBridge::setWindowProperty(const QString& address, const QString& property, bool enable) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        uint32_t state = 0;
        if (property == QStringLiteral("keep_above"))
            state = QtWayland::org_kde_plasma_window_management::state_keep_above;
        else if (property == QStringLiteral("keep_below"))
            state = QtWayland::org_kde_plasma_window_management::state_keep_below;
        else if (property == QStringLiteral("skip_taskbar"))
            state = QtWayland::org_kde_plasma_window_management::state_skiptaskbar;
        else if (property == QStringLiteral("demands_attention"))
            state = QtWayland::org_kde_plasma_window_management::state_demands_attention;

        if (state != 0) {
            handle->setState(state, enable);
        }
    }
}

void KWinActiveWindowBridge::setWindowDesktop(const QString& address, int desktopId) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        if (auto wsState = KWinWorkspaceState::instance()) {
            QString uuid = wsState->uuidForIndex(desktopId);
            if (!uuid.isEmpty()) {
                QStringList currentDesktops = handle->desktops();
                for (const QString& oldUuid : currentDesktops) {
                    if (oldUuid != uuid) {
                        handle->request_leave_virtual_desktop(oldUuid);
                    }
                }
                handle->request_enter_virtual_desktop(uuid);
            }
        }
    }
}

void KWinActiveWindowBridge::setFullscreen(const QString& address, bool fullscreen) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        handle->setState(QtWayland::org_kde_plasma_window_management::state_fullscreen, fullscreen);
    }
}

void KWinActiveWindowBridge::setMaximized(const QString& address, bool maximized) {
    if (auto* handle = PlasmaWindows::instance()->handleFor(address)) {
        handle->setState(QtWayland::org_kde_plasma_window_management::state_maximized, maximized);
    }
}

void KWinActiveWindowBridge::highlightWindow(const QString& address) {
    if (address == m_highlightedAddress && !address.isEmpty()) {
        return;
    }
    m_highlightedAddress = address;
    emit highlightedAddressChanged();

    auto msg =
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/HighlightWindow"),
            QStringLiteral("org.kde.KWin.HighlightWindow"), QStringLiteral("highlightWindows"));
    QStringList list;
    if (!address.isEmpty()) {
        list << address;
    }
    msg << list;
    QDBusConnection::sessionBus().send(msg);
}

void KWinActiveWindowBridge::clearHighlight() {
    if (!m_highlightedAddress.isEmpty()) {
        highlightWindow(QString());
    } else {
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
            QStringLiteral("/org/kde/KWin/HighlightWindow"), QStringLiteral("org.kde.KWin.HighlightWindow"),
            QStringLiteral("highlightWindows"));
        msg << QStringList();
        QDBusConnection::sessionBus().send(msg);
    }
}

void KWinActiveWindowBridge::refreshWindows() {
    scheduleWindowListUpdate();
}

} // namespace caelestia::services
