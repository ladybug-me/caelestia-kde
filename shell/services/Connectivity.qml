pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/// Whether the network actually lets traffic through, and where to send someone who has
/// to sign in first.
///
/// NetworkManager already answers the first half: its own connectivity probe reports
/// `portal` when it lands on a login page, so the shell asks it rather than probing by
/// itself. The sign-in URL is the part NetworkManager does not hand out, so it is found
/// the way plasma-nm finds it — ask a known URL and read where the redirect went.
Singleton {
    id: root

    readonly property string checkUrl: "http://networkcheck.kde.org/"

    property string state: ""
    property string portalUrl: ""
    property bool working: false
    property string lastError: ""

    readonly property bool portal: root.state === "portal"

    function check(): void {
        if (checkProcess.running)
            return;
        checkProcess.running = true;
    }

    function signIn(): void {
        if (!root.portal || probeProcess.running)
            return;

        root.lastError = "";
        root.working = true;
        probeProcess.running = true;
    }

    Component.onCompleted: root.check()

    Connections {
        function onIsConnectedChanged(): void {
            root.check();
        }

        target: Nmcli
    }

    // NetworkManager re-checks on its own schedule, so this only has to notice that the
    // answer changed while the session sat on one network.
    Timer {
        interval: 120000
        running: true
        repeat: true
        onTriggered: root.check()
    }

    Process {
        id: checkProcess

        command: ["nmcli", "-t", "-f", "CONNECTIVITY", "general"]

        stdout: StdioCollector {
            onStreamFinished: root.state = text.trim()
        }
    }

    Process {
        id: probeProcess

        command: ["curl", "-sS", "-m", "6", "-o", "/dev/null", "-w", "%{url_effective}", root.checkUrl]

        stdout: StdioCollector {
            id: probeOutput
        }

        stderr: StdioCollector {
            id: probeError
        }

        onExited: exitCode => {
            root.working = false;
            if (exitCode !== 0) {
                root.lastError = probeError.text.trim();
                return;
            }

            // A portal intercepts the check and redirects to itself, so a URL that is
            // still the check URL means the network answered normally.
            const url = probeOutput.text.trim();
            root.portalUrl = url.startsWith(root.checkUrl) ? "" : url;
            if (root.portalUrl !== "")
                Quickshell.execDetached(["xdg-open", root.portalUrl]);
            else
                root.lastError = qsTr("No sign-in page answered.");
        }
    }
}
