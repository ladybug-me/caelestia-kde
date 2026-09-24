pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.utils

Scope {
    id: root

    readonly property bool hasPlayer: Players.list.some(p => p.isPlaying)
    readonly property bool isCharging: !UPower.onBattery
    readonly property bool enabled: {
        if (GlobalConfig.general.idle.inhibitWhenAudio && hasPlayer)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenCharging && isCharging)
            return false;
        return true;
    }

    /// Whether KDE's kscreenlocker will lock the session by itself when the machine
    /// wakes (kscreenlockerrc [Daemon] LockOnResume, on by default). When it does,
    /// the lockBeforeSleep lock below is skipped: locking the session twice around a
    /// suspend leaves the greeter that survives it rendering without its wallpaper,
    /// palette and avatar (issue #815).
    property bool kdeLocksOnResume: true

    function requestLock(): void {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function requestUnlock(): void {
        Quickshell.execDetached(["loginctl", "unlock-session"]);
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            root.requestLock();
        else if (action === "unlock")
            root.requestUnlock();
        else if (typeof action === "string")
            Kwin.dispatch(action);
        else if (!SessionManager.exec(action))
            Launch.exec(action);
    }

    Connections {
        function onAboutToSleep(): void {
            // ksmserver locks on resume by itself when LockOnResume is on; firing our
            // lock as well locks the session twice around the suspend, which is the
            // double-lock that breaks the greeter (issue #815).
            if (GlobalConfig.general.idle.lockBeforeSleep && !root.kdeLocksOnResume)
                root.requestLock();
        }

        target: SessionManager
    }

    Process {
        id: kdeLockConfig

        // Read once at startup: the setting lives in KDE's lock screen settings, and
        // absent or unreadable answers mean "on", the KDE default.
        command: ["bash", "-c", "kreadconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume --default true 2>/dev/null || printf 'true\\n'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.kdeLocksOnResume = text.trim() !== "false"
        }
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts.values

        IdleMonitor {
            required property var modelData

            enabled: {
                if (!root.enabled || !(modelData.enabled ?? !IdleActions.isSuspendIdleAction(modelData.idleAction)))
                    return false;
                if (modelData.inhibitWhenAudio && root.hasPlayer)
                    return false;
                if (modelData.inhibitWhenCharging && root.isCharging)
                    return false;
                return true;
            }
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
