pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Services.QuickShare

/// The system half of Quick Share. A transfer arrives on the fixed port
/// `QuickShareService.listenPort`, which has to be open, behind an mDNS advertisement
/// that has to be published, and the shell can grant neither by itself:
/// `scripts/quickshare_setup.sh` answers for both, as a report and as a privileged run.
/// This is where that conversation lives, so that the switch and the Settings row can
/// read an answer instead of assembling one.
Singleton {
    id: root

    enum State {
        /// Nothing has been asked this session.
        Unknown,
        /// Avahi is running and nothing is known to be blocking the port.
        Ready,
        /// Something is missing that a privileged run can put right.
        NeedsSetup,
        /// The report could not say: ufw cannot be read without root, or the helper did
        /// not answer at all.
        Unverified
    }

    /// The helper, as installed next to the shell.
    readonly property string script: Quickshell.shellPath("scripts/quickshare_setup.sh")

    property int state: QuickShareSetup.State.Unknown
    /// Whether a report or a privileged run is in flight.
    property bool busy: false
    /// The one line the flow has to say for itself: what a run is doing, what it said, or
    /// what the last report could not settle. Empty when it has nothing to add.
    property string message: ""
    /// Whether that run exited cleanly, which is what a report that cannot see the port
    /// has to be read against.
    property bool lastRunSucceeded: false

    readonly property bool ready: root.state === QuickShareSetup.State.Ready
    readonly property bool needsSetup: root.state === QuickShareSetup.State.NeedsSetup

    /// For the Settings row this flow belongs to, which is the only place it is shown.
    readonly property string status: {
        if (root.message !== "")
            return root.message;
        if (root.ready)
            return qsTr("Avahi and the transfer port are ready");
        if (root.state === QuickShareSetup.State.Unverified)
            return qsTr("The transfer port could not be confirmed");
        if (root.busy)
            return qsTr("Asking the system…");
        return qsTr("Starts the Avahi daemon and opens the transfer port in the firewall");
    }

    /// Emitted once a report has been read and `state` has settled with it, so that
    /// whoever asked can act on a final answer rather than a half-read one.
    signal reported()

    /// Asks the helper what the machine looks like. A report already in flight is left to
    /// finish: it is about to answer the same question.
    function check(): void {
        if (root.busy)
            return;

        root.state = QuickShareSetup.State.Unknown;
        root.busy = true;
        reportProc.running = true;
    }

    /// Runs the helper as root, which is the only thing that enables Avahi and opens the
    /// port, and asks again afterwards.
    function run(): void {
        if (root.busy)
            return;

        root.busy = true;
        root.message = qsTr("Waiting for administrator rights…");
        root.lastRunSucceeded = false;
        setupProc.running = true;
    }

    Process {
        id: reportProc

        command: ["bash", root.script, "--status", "--port", String(QuickShareService.listenPort)]
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("SETUP="))
                    return;

                switch (line.slice(6).trim()) {
                case "ok":
                    root.state = QuickShareSetup.State.Ready;
                    root.message = "";
                    break;
                case "needed":
                    root.state = QuickShareSetup.State.NeedsSetup;
                    break;
                default:
                    root.state = QuickShareSetup.State.Unverified;
                    break;
                }
            }
        }
        onExited: code => {
            root.busy = false;

            // A report that never arrived is not a firewall the helper could not read,
            // and the row should not describe it as one.
            if (code !== 0 || root.state === QuickShareSetup.State.Unknown) {
                root.state = QuickShareSetup.State.Unverified;
                if (root.message === "" && !root.lastRunSucceeded)
                    root.message = qsTr("Quick Share's system setup helper could not be run");
            }

            // A run that exited cleanly is the only thing that can vouch for a port the
            // report cannot see, so the row says it happened rather than staying silent.
            if (root.lastRunSucceeded) {
                root.lastRunSucceeded = false;
                if (root.state === QuickShareSetup.State.NeedsSetup)
                    root.message = qsTr("Setup ran, but the port is still blocked");
                else if (root.state !== QuickShareSetup.State.Ready)
                    root.message = qsTr("Setup ran; the port cannot be checked again without root");
            }

            root.reported();
        }
    }

    Process {
        id: setupProc

        command: ["pkexec", "bash", root.script, "--port", String(QuickShareService.listenPort)]
        stderr: SplitParser {
            onRead: line => {
                const said = line.trim();
                if (said !== "")
                    root.message = said;
            }
        }
        onExited: code => {
            root.busy = false;
            root.lastRunSucceeded = code === 0;

            if (code === 126 || code === 127)
                root.message = qsTr("Administrator rights were refused");
            else if (code !== 0 && root.message === "")
                root.message = qsTr("Setup failed (%1)").arg(code);

            root.check();
        }
    }
}
