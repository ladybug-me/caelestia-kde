pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services.QuickShare
import qs.services

/// The shell-side part of Quick Share: the prompt for a transfer another device
/// started, and the switch the user turns the service on with. The service itself is a
/// QML singleton consumers use directly (QuickShareService), and the system it needs to
/// receive, which the shell cannot grant itself, is another (QuickShareSetup); this owns
/// what a user sees, because the prompt outlives a single drawer, and referencing it is
/// what brings the service up on launch (see shell.qml).
Singleton {
    id: root

    /// The live incoming-transfer prompt, while one is pending. Null otherwise.
    property NotifData prompt: null
    /// Whether `prompt` is still the notification Notifs is showing. The user can
    /// dismiss the prompt from the notification centre at any point, which drops it
    /// from Notifs.list, so the handle below is only safe to touch while this holds.
    readonly property bool promptLive: root.prompt !== null && Notifs.list.includes(root.prompt) && !root.prompt.closed
    property string promptDeviceName: ""
    property string promptFileName: ""
    property real promptFileSize: 0
    property string promptPin: ""
    /// The send waiting for the user to compare codes, while one is pending.
    property NotifData sendPrompt: null
    readonly property bool sendPromptLive: root.sendPrompt !== null && Notifs.list.includes(root.sendPrompt) && !root.sendPrompt.closed
    property string sendDeviceName: ""
    property string sendFileName: ""
    property string sendPin: ""
    /// Whether an incoming request is still waiting for an answer. It outlives the
    /// prompt: once the prompt is dismissed the notification loses the only Accept /
    /// Decline the user had, so this is what keeps the request answerable from the
    /// Quick Share card in the utilities drawer.
    property bool pendingIncoming: false

    /// What the switch and the card read. An enable reads as on from the click rather
    /// than from the service, because the system check a first enable sets off can put a
    /// password dialog in the way, and a switch is not where that is explained.
    readonly property bool enabled: QuickShareService.isEnabled || root.pendingEnable
    /// Whether an enable is waiting on the answer QuickShareSetup is collecting for it.
    property bool pendingEnable: false
    /// Whether this session has already been told what its setup needs, so a
    /// second enable neither repeats the prompt nor the warning.
    property bool raised: false

    /// Turns the service on or off, asking the system first: whether this machine can be
    /// reached is the thing a first enable has to settle, and QuickShareSetup is what
    /// answers it. Turning it on also makes this shell visible to nearby devices, which
    /// the service keeps in step.
    function setEnabled(on: bool): void {
        root.pendingEnable = on;

        if (!on) {
            QuickShareService.isEnabled = false;
            return;
        }

        if (QuickShareSetup.state === QuickShareSetup.State.Unknown)
            QuickShareSetup.check();
        else
            root.finishEnable();
    }

    /// Lets a pending enable through, which is what every answer from QuickShareSetup
    /// ends in: the system is either ready now, or was found to need something the user
    /// was just told about. A user who changed their mind by then is left alone.
    function finishEnable(): void {
        if (!root.pendingEnable)
            return;

        root.pendingEnable = false;
        QuickShareService.isEnabled = true;
    }

    function acceptIncomingTransfer(): void {
        root.pendingIncoming = false;
        QuickShareService.acceptIncomingTransfer();
    }

    function confirmOutgoingTransfer(): void {
        QuickShareService.confirmOutgoingTransfer();
        root.clearSendPrompt();
    }

    function cancelOutgoingTransfer(): void {
        QuickShareService.cancelOutgoingTransfer();
        root.clearSendPrompt();
    }

    function clearSendPrompt(): void {
        if (root.sendPromptLive)
            root.sendPrompt.close();
        root.sendPrompt = null;
        root.sendDeviceName = "";
        root.sendFileName = "";
        root.sendPin = "";
    }

    function sendPromptBody(): string {
        return qsTr("Sending %1 to %2.\nCheck that %3 shows the same code before sending: %4")
            .arg(root.sendFileName, root.sendDeviceName, root.sendDeviceName, root.sendPin);
    }

    function rejectIncomingTransfer(): void {
        root.pendingIncoming = false;
        QuickShareService.rejectIncomingTransfer();
    }

    function clearPrompt(): void {
        if (root.promptLive)
            root.prompt.close();
        root.prompt = null;
        root.promptDeviceName = "";
        root.promptFileName = "";
        root.promptFileSize = 0;
        root.promptPin = "";
    }

    function promptBody(): string {
        let body = qsTr("%1 wants to send you %2 (%3)").arg(root.promptDeviceName).arg(root.promptFileName).arg(Units.formatBytes(root.promptFileSize));
        // The code is the only thing that says the sender is the device that was picked.
        // It is worth nothing unless the person on this end is told to compare it.
        if (root.promptPin)
            body += qsTr("\nCheck that %1 shows this code before accepting: %2").arg(root.promptDeviceName, root.promptPin);
        return body;
    }

    Component.onCompleted: {
        // Autostarting is not a user asking for anything, so it does not go through the
        // gate: a password prompt at login is not one the shell should raise.
        if (GlobalConfig.services.quickShareAutoStart)
            QuickShareService.isEnabled = true;
    }

    Connections {
        // The gate. The first report of a session decides whether the enable can go
        // through, needs a privileged run first, or has to be let through with a warning;
        // every later report is the Settings row's business, not this one's.
        function onReported(): void {
            if (!root.pendingEnable)
                return;

            if (!root.raised) {
                if (QuickShareSetup.needsSetup) {
                    root.raised = true;
                    Toaster.toast(qsTr("Quick Share"),
                        qsTr("Quick Share needs administrator rights to start Avahi and open the transfer port."), "info", Toast.Info, 15000);
                    QuickShareSetup.run();
                    return; // the run reports again, and comes back through here
                }

                if (QuickShareSetup.state === QuickShareSetup.State.Unverified) {
                    root.raised = true;
                    Toaster.toast(qsTr("Quick Share"),
                        QuickShareSetup.message !== "" ? QuickShareSetup.message
                            : qsTr("Quick Share could not confirm the transfer port is reachable. Allow port %1 in Settings -> Services -> Quick Share.").arg(QuickShareService.listenPort),
                        "warning", Toast.Warning, 30000);
                }
            }

            root.finishEnable();
        }

        target: QuickShareSetup
    }

    Connections {
        function onIncomingTransferRequested(deviceName: string, fileName: string, fileSize: real): void {
            // The code is derived during the handshake, so it may already be here by the
            // time the request is; clearing the prompt must not take it with it.
            const code = root.promptPin;

            root.clearPrompt();
            root.promptPin = code;
            root.pendingIncoming = true;
            root.promptDeviceName = deviceName;
            root.promptFileName = fileName;
            root.promptFileSize = fileSize;
            root.prompt = Notifs.addShellNotification({
                summary: qsTr("Incoming file"),
                body: root.promptBody(),
                appName: qsTr("Quick Share"),
                materialIcon: "near_me",
                actions: [
                    { identifier: "decline", text: qsTr("Decline"), invoke: () => root.rejectIncomingTransfer() },
                    { identifier: "accept", text: qsTr("Accept"), invoke: () => root.acceptIncomingTransfer() }
                ]
            });
        }

        // The few seconds between the request and the PIN are what the prompt has
        // to cover, so the same prompt is rewritten rather than a second one made.
        function onIncomingTransferPinReady(pinCode: string): void {
            root.promptPin = pinCode;
            if (root.promptLive)
                root.prompt.body = root.promptBody();
        }

        // The peer agreed to take the file, but the code is the only thing that says the
        // peer is the device the user picked. A relayed handshake gives each end a
        // different code, so a user who compares them catches it here.
        function onOutgoingTransferPinReady(deviceId: string, deviceName: string, fileName: string, pinCode: string): void {
            root.clearSendPrompt();
            root.sendDeviceName = deviceName;
            root.sendFileName = fileName;
            root.sendPin = pinCode;
            root.sendPrompt = Notifs.addShellNotification({
                summary: qsTr("Confirm the code"),
                body: root.sendPromptBody(),
                appName: qsTr("Quick Share"),
                materialIcon: "near_me",
                actions: [
                    { identifier: "cancel", text: qsTr("Cancel"), invoke: () => root.cancelOutgoingTransfer() },
                    { identifier: "send", text: qsTr("Send"), invoke: () => root.confirmOutgoingTransfer() }
                ]
            });
        }

        function onOutgoingTransferFinished(deviceId: string, success: bool): void {
            // The prompt has nothing left to answer once the transfer it was for ended.
            root.clearSendPrompt();
        }

        function onIncomingTransferFinished(success: bool): void {
            // Ended either way: the request is no longer answerable.
            root.pendingIncoming = false;
            root.clearPrompt();
        }

        function onErrorOccurred(message: string): void {
            Toaster.toast(qsTr("Quick Share"), message, "error");
        }

        target: QuickShareService
    }
}
