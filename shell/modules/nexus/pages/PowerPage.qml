pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property bool idleSuspendEnabledState: false
    property int idleSuspendMinutesState: 10
    property bool idleLockEnabledState: false
    property int idleLockMinutesState: 3

    /// logind's answer about hibernation, or an empty string when it could not be
    /// asked. Suspend-then-hibernate quietly downgrades to plain suspend without it,
    /// so the page says so next to the toggle that schedules it (issue #575).
    property string hibernateAnswer: ""
    /// logind's HibernateDelaySec, or -1 when it is not a fixed number.
    property int hibernateDelaySec: -1

    readonly property bool hibernateAvailable: hibernateAnswer === "yes" || hibernateAnswer === "challenge"

    // The suspend entry of the idle timeouts, or null when the user has not added one.
    // The list is a config node now, so entries are read and written in place instead of
    // being copied out and written back as a whole.
    function suspendTimeout(): var {
        return GlobalConfig.general.idle.timeouts.values.find(t => IdleActions.isSuspendIdleAction(t.idleAction)) ?? null;
    }

    // The props for a suspend entry, used when the user turns the suspend timeout on
    // without one in the config.
    function suspendProps(timeoutSeconds: int): var {
        return {
            "timeout": timeoutSeconds,
            "idleAction": ["suspendThenHibernate"],
            "enabled": true,
            "respectInhibitors": true
        };
    }

    function refreshIdleSuspendState(): void {
        const seconds = IdleActions.suspendSeconds;
        root.idleSuspendEnabledState = seconds > 0;
        root.idleSuspendMinutesState = seconds > 0 ? Math.round(seconds / 60) : 10;
    }

    function setSuspendTimeoutMinutes(minutes: int): void {
        const sanitizedMinutes = Math.max(1, Math.min(180, Math.round(minutes)));
        const timeoutSeconds = sanitizedMinutes * 60;
        const suspend = root.suspendTimeout();

        if (suspend)
            suspend.timeout = timeoutSeconds;
        else
            GlobalConfig.general.idle.timeouts.insert(root.suspendProps(timeoutSeconds));

        root.refreshIdleSuspendState();
    }

    function setSuspendTimeoutEnabled(enabled: bool): void {
        const suspend = root.suspendTimeout();

        if (suspend)
            suspend.enabled = enabled;
        else if (enabled)
            GlobalConfig.general.idle.timeouts.insert(root.suspendProps(root.idleSuspendMinutesState * 60));

        root.refreshIdleSuspendState();
    }

    // The lock entry of the idle timeouts, or null when the user has none. The default
    // config ships one at 180 seconds, which is the "locks every 3 minutes" timer from
    // issue #815: it fired without being visible anywhere in the UI.
    function lockTimeout(): var {
        return GlobalConfig.general.idle.timeouts.values.find(t => t.idleAction === "lock") ?? null;
    }

    // The props for a lock entry, used when the user turns the idle lock on without one.
    function lockProps(timeoutSeconds: int): var {
        return {
            "timeout": timeoutSeconds,
            "idleAction": "lock",
            "enabled": true,
            "respectInhibitors": true
        };
    }

    function refreshIdleLockState(): void {
        const lock = root.lockTimeout();
        root.idleLockEnabledState = !!lock && (lock.enabled ?? true);
        root.idleLockMinutesState = lock ? Math.max(1, Math.round(lock.timeout / 60)) : 3;
    }

    function setIdleLockMinutes(minutes: int): void {
        const sanitizedMinutes = Math.max(1, Math.min(180, Math.round(minutes)));
        const timeoutSeconds = sanitizedMinutes * 60;
        const lock = root.lockTimeout();

        if (lock)
            lock.timeout = timeoutSeconds;
        else
            GlobalConfig.general.idle.timeouts.insert(root.lockProps(timeoutSeconds));

        root.refreshIdleLockState();
    }

    function setIdleLockEnabled(enabled: bool): void {
        const lock = root.lockTimeout();

        if (lock)
            lock.enabled = enabled;
        else if (enabled)
            GlobalConfig.general.idle.timeouts.insert(root.lockProps(root.idleLockMinutesState * 60));

        root.refreshIdleLockState();
    }

    Component.onCompleted: {
        root.refreshIdleSuspendState();
        root.refreshIdleLockState();
    }

    title: qsTr("Power")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Idle & sleep")
        }

        ToggleRow {
            first: true
            text: qsTr("Idle suspend")
            subtext: qsTr("Suspend the system after inactivity, then hibernate when possible")
            checked: root.idleSuspendEnabledState
            onToggled: root.setSuspendTimeoutEnabled(checked)
        }

        StepperRow {
            enabled: root.idleSuspendEnabledState
            label: qsTr("Idle suspend timer")
            subtext: root.idleSuspendEnabledState
                     ? qsTr("Suspend after %1 minute(s) of inactivity").arg(root.idleSuspendMinutesState)
                     : qsTr("Enable idle suspend to apply a timer")
            value: root.idleSuspendMinutesState
            from: 1
            to: 180
            stepSize: 1
            onMoved: v => {
                if (root.idleSuspendEnabledState)
                    root.setSuspendTimeoutMinutes(v)
            }
        }

        InfoRow {
            // Hibernation needs a swap partition or file and a resume= kernel argument;
            // logind reports "no" without them and suspend-then-hibernate quietly runs
            // as plain suspend (issue #575). Shown where the schedule is turned on, so
            // the requirement is documented where the behaviour is chosen.
            visible: root.idleSuspendEnabledState && root.hibernateAnswer !== ""
            label: qsTr("Hibernation after suspend")
            icon: root.hibernateAvailable ? "bedtime" : "warning"
            iconColour: root.hibernateAvailable ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
            value: root.hibernateAvailable
                   ? (root.hibernateDelaySec > 0 ? qsTr("After %1s of sleep").arg(root.hibernateDelaySec) : qsTr("On systemd's suspend estimate"))
                   : qsTr("Not set up")
            subtext: root.hibernateAvailable
                     ? qsTr("logind hibernates the machine once the suspend delay has passed")
                     : qsTr("Needs a swap partition or file and a resume= kernel argument; without them, suspend falls back to plain suspend")
        }

        ToggleRow {
            text: qsTr("Idle lock")
            subtext: qsTr("Lock the session after inactivity, on top of KDE's own auto-lock")
            checked: root.idleLockEnabledState
            onToggled: root.setIdleLockEnabled(checked)
        }

        StepperRow {
            enabled: root.idleLockEnabledState
            label: qsTr("Idle lock timer")
            subtext: root.idleLockEnabledState
                     ? qsTr("Lock after %1 minute(s) of inactivity").arg(root.idleLockMinutesState)
                     : qsTr("Enable idle lock to apply a timer")
            value: root.idleLockMinutesState
            from: 1
            to: 180
            stepSize: 1
            onMoved: v => {
                if (root.idleLockEnabledState)
                    root.setIdleLockMinutes(v)
            }
        }

        ToggleRow {
            text: qsTr("Lock before sleep")
            subtext: qsTr("Lock the session before suspending, unless KDE already locks on resume")
            checked: Config.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            text: qsTr("Inhibit while audio")
            subtext: qsTr("Prevent idle actions while audio is playing")
            checked: Config.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Inhibit while charging")
            subtext: qsTr("Prevent idle actions while charging")
            checked: Config.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }

        SectionHeader {
            text: qsTr("Battery warnings")
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Critical battery level")
            subtext: qsTr("Percentage at which the critical warning fires")
            value: Config.general.battery.criticalLevel
            from: 1
            to: 50
            stepSize: 1
            onMoved: v => GlobalConfig.general.battery.criticalLevel = v
        }

        Process {
            id: hibernateProbe

            // Asked once at startup, like the other KDE settings this page reads around.
            // An empty answer means logind could not be asked and says nothing either way.
            command: ["bash", "-c", `
                CAN="$(qdbus6 --system org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.CanHibernate 2>/dev/null || true)"
                DELAY="$(qdbus6 --system org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.DBus.Properties.Get org.freedesktop.login1.Manager HibernateDelaySecUSec 2>/dev/null || true)"
                printf 'can=%s\\ndelay=%s\\n' "$CAN" "$DELAY"
            `]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    const can = /can=(.*)/.exec(text) ?? [];
                    const delay = /delay=(.*)/.exec(text) ?? [];
                    root.hibernateAnswer = (can[1] ?? "").trim();
                    const usec = Number(((delay[1] ?? "").match(/\d+/) ?? ["-1"])[0]);
                    const seconds = Math.round(usec / 1e6);
                    root.hibernateDelaySec = isFinite(seconds) && seconds > 0 ? seconds : -1;
                }
            }
        }
    }
}
