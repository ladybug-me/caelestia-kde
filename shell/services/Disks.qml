pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// The disks the Storage page can mount, unmount and eject.
///
/// Deciding what is worth showing belongs to `scripts/disks.py`, which reads the same
/// `lsblk` data udisks does. Mounting goes through `udisksctl` rather than mounting
/// ourselves: it is the polkit-checked path, so the answer is a prompt or a refusal
/// instead of a half-mounted filesystem.
Singleton {
    id: root

    readonly property var disks: list.result?.disks ?? []
    readonly property bool loaded: list.loaded
    readonly property string lastError: root.actionError || list.error
    property bool working: false
    property string actionError: ""

    function refresh(): void {
        if (list.running)
            return;
        root.working = true;
        list.start();
    }

    function mount(device: string): void {
        root.act(["udisksctl", "mount", "-b", device]);
    }

    function unmount(device: string): void {
        root.act(["udisksctl", "unmount", "-b", device]);
    }

    /// Ejecting is per disk, not per filesystem: udisks refuses to power a disk off
    /// while anything on it is still mounted, which is the protection worth having.
    function eject(device: string): void {
        root.act(["udisksctl", "power-off", "-b", device]);
    }

    function act(command: list<string>): void {
        if (action.running)
            return;
        root.actionError = "";
        root.working = true;
        action.command = command;
        action.running = true;
    }

    Component.onCompleted: root.refresh()

    JsonScript {
        id: list

        script: "scripts/disks.py"

        onLoadedChanged: {
            if (list.loaded)
                root.working = false;
        }
    }

    Process {
        id: action

        stderr: StdioCollector {
            id: actionStderr
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.actionError = actionStderr.text.trim();
            root.refresh();
        }
    }
}
