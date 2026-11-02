pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// The programs that start at log-in, as the XDG autostart directories describe them.
///
/// Reading and editing desktop files belongs to `scripts/autostart.py`: a system entry is
/// switched off by a copy of its own in the user's directory, and getting that wrong loses
/// the user's edits. This keeps the list current and re-reads it after every change, because
/// the file is the truth, not what was just asked for.
Singleton {
    id: root

    property var entries: []

    function refresh(): void {
        listProcess.running = false;
        listProcess.running = true;
    }

    function run(args: list<string>): void {
        editProcess.command = ["python3", Quickshell.shellPath("scripts/autostart.py"), ...args];
        editProcess.running = true;
    }

    function setEnabled(id: string, on: bool): void {
        root.run(["--set", id, on ? "on" : "off"]);
    }

    function remove(id: string): void {
        root.run(["--remove", id]);
    }

    function add(desktopId: string): void {
        root.run(["--add", desktopId]);
    }

    Component.onCompleted: root.refresh()

    Process {
        id: listProcess

        command: ["python3", Quickshell.shellPath("scripts/autostart.py"), "--list"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(text);
                } catch (error) {
                    root.entries = [];
                }
            }
        }
    }

    Process {
        id: editProcess

        onExited: root.refresh()
    }
}
