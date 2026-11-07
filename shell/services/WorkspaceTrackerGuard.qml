pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

// The workspace-tracker effect is compiled against KWin's internals, so a KDE
// update can leave the installed binary unloadable and the shell silently
// without per-output desktops. The check reports that once per session.
Singleton {
    id: root

    readonly property string checkScript: Quickshell.shellPath("scripts/check-workspace-tracker.sh")

    // KWin loads its effects long before the shell starts, so the delay only
    // covers a login that brings both up at once.
    Timer {
        interval: 5000
        running: true

        onTriggered: check.running = true
    }

    Process {
        id: check

        // The script says why it gave up on stdout, so the message can name the
        // versions rather than only reporting that something is missing.
        readonly property string reason: String(out.text ?? "").trim()

        command: ["bash", root.checkScript]
        stdout: StdioCollector {
            id: out
        }

        onExited: code => {
            if (code !== 3)
                return;

            const detail = check.reason.length > 0 ? check.reason : qsTr("KWin never registered it");
            console.warn(`[WorkspaceTrackerGuard] workspace tracker not loaded: ${detail}`);
            // The title is one elided line and the body six at the toast's width, so
            // both stay short enough to be read whole.
            Toaster.toast(qsTr("Desktop tracking is off"), qsTr("KWin refused the workspace tracker (%1), so per-output desktops and swipes stopped working. Run caelestia update, then caelestia shell restart.").arg(detail), "extension_off", Toast.Warning);
        }
    }
}
