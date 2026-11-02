pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.utils

// Keep-awake outlives the shell. The intent is one value in the runtime directory, so a
// restarted or crashed shell picks it up again, while a reboot or a new login starts clean
// — an inhibitor that outlived a reboot would quietly stop the machine from sleeping.
// `PersistentProperties` cannot carry this: it is written when the shell reloads itself,
// not when the service is stopped.
Singleton {
    id: root

    // The flag and the time it was raised move together, so restoring the file cannot look
    // like a toggle, and no reader can catch half of a change. `setEnabled` is the only way
    // in: writing `enabled` directly would skip the file.
    property var state: ({ enabled: false, since: new Date() })

    readonly property bool enabled: root.state.enabled
    readonly property date enabledSince: root.state.since

    function setEnabled(value: bool): void {
        if (value === root.state.enabled)
            return;

        root.state = { enabled: value, since: value ? new Date() : root.state.since };
        stateFile.setText(root.serialize(root.state));
    }

    function serialize(state: var): string {
        return JSON.stringify({ enabled: state.enabled, since: state.since.toISOString() });
    }

    function restore(text: string): void {
        let stored = null;
        try {
            stored = JSON.parse(text);
        } catch (err) {
            Logger.log("[IdleInhibitor] keep-awake state is unreadable, starting with it off:", err);
        }

        const since = stored?.since ? new Date(stored.since) : new Date();
        root.state = {
            enabled: stored?.enabled === true,
            since: isNaN(since.getTime()) ? new Date() : since
        };
    }

    IdleInhibitor {
        enabled: root.enabled
        window: PanelWindow {
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            mask: Region {}
        }
    }

    FileView {
        id: stateFile

        path: Paths.runtimeTemp("keepawake.json")
        watchChanges: false
        printErrors: false

        onLoaded: root.restore(stateFile.text())
    }

    IpcHandler {
        function isEnabled(): bool {
            return root.enabled;
        }

        function toggle(): void {
            root.setEnabled(!root.enabled);
        }

        function enable(): void {
            root.setEnabled(true);
        }

        function disable(): void {
            root.setEnabled(false);
        }

        target: "idleInhibitor"
    }
}
