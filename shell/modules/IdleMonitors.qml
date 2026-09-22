pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.requestLock();
        }

        target: SessionManager
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

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
