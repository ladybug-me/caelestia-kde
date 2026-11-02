pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// The proxy KDE applications use, as `kioslaverc` holds it.
///
/// Reading and writing belongs to `scripts/proxy.py`: the file has other sections and
/// comments that a parser would throw away, and environment variables would only reach
/// programs started after the change.
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/proxy.py")
    readonly property var settings: read.result ?? ({})
    readonly property bool loaded: read.loaded
    /// One line for a page to show: what KDE applications will actually do.
    readonly property string summary: {
        if (root.mode === "manual")
            return root.settings.http || qsTr("Manual, no address set");
        if (root.mode === "pac")
            return root.settings.pac || qsTr("Automatic script");
        return root.mode === "none" ? qsTr("Off") : root.mode;
    }
    readonly property string mode: root.settings.mode ?? "none"
    readonly property string lastError: root.writeError || read.error
    property bool working: false
    property string writeError: ""

    function refresh(): void {
        if (read.running)
            return;
        read.start();
    }

    function setMode(mode: string): void {
        root.run(["--set-mode", mode]);
    }

    function set(key: string, value: string): void {
        root.run(["--set", key, value]);
    }

    /// One write at a time: each one is a read-modify-write of the whole file, so two at
    /// once would race and one of the two edits would be lost.
    function run(args: list<string>): void {
        if (editor.running)
            return;
        root.writeError = "";
        root.working = true;
        editor.command = ["python3", root.scriptPath, ...args];
        editor.running = true;
    }

    Component.onCompleted: root.refresh()

    JsonScript {
        id: read

        script: "scripts/proxy.py"
        args: ["--get"]
    }

    Process {
        id: editor

        stderr: StdioCollector {
            id: editorStderr
        }

        onExited: exitCode => {
            root.working = false;
            if (exitCode !== 0) {
                root.writeError = editorStderr.text.trim() || qsTr("The proxy settings could not be written.");
                return;
            }
            root.refresh();
        }
    }
}
