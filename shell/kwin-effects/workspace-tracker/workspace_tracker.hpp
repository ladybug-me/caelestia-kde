#pragma once

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <QDBusContext>
#include <QLocalSocket>
#include <QUuid>
#include <QPointer>
#include <QObject>
#include <QPointF>
#include <kwin/virtualdesktops.h>

namespace caelestia {

struct DesktopReport {
    static constexpr quint32 kMagic = 0x43414557;

    quint32 magic = kMagic;
    qint32 desktop = 0;
    float x = 0.0f;
    float y = 0.0f;
    char output[64] = {};
};

class WorkspaceTrackerEffect : public KWin::Effect, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.caelestia.Workspaces")
public:
    WorkspaceTrackerEffect();
    ~WorkspaceTrackerEffect() override;

public Q_SLOTS:
    void SetDesktop(const QString& output, int desktop);

    /**
     * Moves the window with EffectWindow::internalId() @p uuid to @p output.
     *
     * There is no unprivileged way to do this from outside: plasma-window-management
     * can move a window between desktops but not between screens, and the D-Bus
     * surface has nothing for it either. Inside the compositor it is one call.
     */
    void SendToOutput(const QString& uuid, const QString& output);

private Q_SLOTS:
    void onDesktopChanging(KWin::VirtualDesktop* desktop, QPointF offset, KWin::EffectWindow* with, KWin::LogicalOutput* output);
    void onDesktopChangingCancelled();
    void onDesktopChanged(KWin::VirtualDesktop* oldDesktop, KWin::VirtualDesktop* newDesktop, KWin::EffectWindow* with, KWin::LogicalOutput* output);
    void connectSocket();

private:
    void sendPayload(int desktop, float x, float y, KWin::LogicalOutput* output);
    void sendFullState();
    /// Whether the D-Bus caller is the Caelestia shell. Moving a window to another
    /// output, or switching desktops under the user, is the kind of misdirection a
    /// hostile application wants; the session bus offers every local process the same
    /// way in. The caller has to be a process of this user running a root-owned program
    /// named `quickshell` or `qs`, because a name on its own is the caller's to choose.
    bool callerIsShell();
    static KWin::LogicalOutput* findOutput(const QString& name);

    QLocalSocket* m_socket;
    QPointer<KWin::LogicalOutput> m_lastChangingOutput;
};

}
