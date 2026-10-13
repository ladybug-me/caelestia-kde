#include "workspace_tracker.hpp"
#include <QTimer>
#include <KPluginFactory>
#include <QStandardPaths>
#include <QDir>
#include <QDBusConnection>
#include <QDBusError>
#include <effect/effectwindow.h>
#include <QDebug>
#include <core/output.h>
#include <cstring>
#include <QStandardPaths>
#include <QDir>

namespace caelestia {

WorkspaceTrackerEffect::WorkspaceTrackerEffect()
    : m_socket(new QLocalSocket(this))
{
    connect(KWin::effects, &KWin::EffectsHandler::desktopChanging,
            this, &WorkspaceTrackerEffect::onDesktopChanging);
    connect(KWin::effects, &KWin::EffectsHandler::desktopChangingCancelled,
            this, &WorkspaceTrackerEffect::onDesktopChangingCancelled);
    connect(KWin::effects, &KWin::EffectsHandler::desktopChanged,
            this, &WorkspaceTrackerEffect::onDesktopChanged);

    connect(m_socket, &QLocalSocket::disconnected, this, [this]() {
        qDebug() << "WorkspaceTracker: Socket disconnected, retrying...";
        QTimer::singleShot(2000, this, &WorkspaceTrackerEffect::connectSocket);
    });

    connect(m_socket, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError err) {
        qDebug() << "WorkspaceTracker: Socket error:" << err << "- retrying in 2s";
        QTimer::singleShot(2000, this, &WorkspaceTrackerEffect::connectSocket);
    });

    connect(m_socket, &QLocalSocket::connected, this, [this]() {
        qDebug() << "WorkspaceTracker: Socket connected!";
        sendFullState();
    });

    connectSocket();

    // Registered on the service KWin already owns; any session client may call
    // it, and nothing extra has to be granted.
    if (!QDBusConnection::sessionBus().registerObject(
            QStringLiteral("/Caelestia/Workspaces"), this, QDBusConnection::ExportAllSlots)) {
        qWarning() << "WorkspaceTracker: could not register /Caelestia/Workspaces:"
                   << QDBusConnection::sessionBus().lastError().message();
    }
}

KWin::LogicalOutput* WorkspaceTrackerEffect::findOutput(const QString& name)
{
    const auto outputs = KWin::effects->screens();
    for (KWin::LogicalOutput* candidate : outputs) {
        if (candidate && candidate->name() == name) {
            return candidate;
        }
    }
    return nullptr;
}

void WorkspaceTrackerEffect::SendToOutput(const QString& uuid, const QString& output)
{
    KWin::LogicalOutput* target = findOutput(output);
    if (!target) {
        return;
    }

    const QUuid wanted(uuid);
    if (wanted.isNull()) {
        return;
    }

    const auto windows = KWin::effects->stackingOrder();
    for (KWin::EffectWindow* window : windows) {
        if (window && window->internalId() == wanted) {
            KWin::effects->windowToScreen(window, target);
            return;
        }
    }
}

void WorkspaceTrackerEffect::SetDesktop(const QString& output, int desktop)
{
    if (desktop < 1) {
        return;
    }

    KWin::LogicalOutput* target = findOutput(output);
    if (!target) {
        return;
    }

    const auto desktops = KWin::effects->desktops();
    for (KWin::VirtualDesktop* candidate : desktops) {
        if (candidate && static_cast<int>(candidate->x11DesktopNumber()) == desktop) {
            KWin::effects->setCurrentDesktop(candidate, target);
            return;
        }
    }
}

WorkspaceTrackerEffect::~WorkspaceTrackerEffect()
{
    if (m_socket->isOpen()) {
        m_socket->close();
    }
}

void WorkspaceTrackerEffect::connectSocket()
{
    if (m_socket->state() == QLocalSocket::UnconnectedState) {
        QString socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/caelestia-workspace-tracker");
        qDebug() << "WorkspaceTracker: Connecting to socket:" << socketPath;
        m_socket->connectToServer(socketPath);
    }
}

void WorkspaceTrackerEffect::sendPayload(int desktop, float x, float y, KWin::LogicalOutput* output)
{
    if (m_socket->state() != QLocalSocket::ConnectedState) {
        return;
    }

    DesktopReport payload;
    payload.desktop = desktop;
    payload.x = x;
    payload.y = y;

    const QByteArray name = output ? output->name().toUtf8() : QByteArray();
    const int copied = qMin(name.size(), static_cast<qsizetype>(sizeof(payload.output) - 1));
    std::memcpy(payload.output, name.constData(), copied);
    payload.output[copied] = '\0';

    m_socket->write(reinterpret_cast<const char*>(&payload), sizeof(payload));
}

void WorkspaceTrackerEffect::sendFullState()
{
    const auto outputs = KWin::effects->screens();
    for (KWin::LogicalOutput* output : outputs) {
        if (KWin::VirtualDesktop* desktop = KWin::effects->currentDesktop(output)) {
            sendPayload(static_cast<int>(desktop->x11DesktopNumber()), 0.0f, 0.0f, output);
        }
    }
}

void WorkspaceTrackerEffect::onDesktopChanging(
    KWin::VirtualDesktop* desktop, QPointF offset, KWin::EffectWindow* with, KWin::LogicalOutput* output)
{
    Q_UNUSED(with)
    m_lastChangingOutput = output;
    if (desktop && m_socket->state() == QLocalSocket::ConnectedState) {
        sendPayload(desktop->x11DesktopNumber(), static_cast<float>(offset.x()), static_cast<float>(offset.y()), output);
    }
}

void WorkspaceTrackerEffect::onDesktopChangingCancelled()
{
    sendPayload(0, 0.0f, 0.0f, m_lastChangingOutput);
    m_lastChangingOutput = nullptr;
}

void WorkspaceTrackerEffect::onDesktopChanged(
    KWin::VirtualDesktop* oldDesktop, KWin::VirtualDesktop* newDesktop, KWin::EffectWindow* with, KWin::LogicalOutput* output)
{
    Q_UNUSED(oldDesktop)
    Q_UNUSED(with)
    m_lastChangingOutput = nullptr;
    if (newDesktop && m_socket->state() == QLocalSocket::ConnectedState) {
        sendPayload(newDesktop->x11DesktopNumber(), 0.0f, 0.0f, output);
    }
}

}

KWIN_EFFECT_FACTORY(caelestia::WorkspaceTrackerEffect, "kwin_workspace_tracker.json")

#include "workspace_tracker.moc"
