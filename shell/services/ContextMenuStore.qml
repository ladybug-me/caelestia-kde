pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string menuPath: Quickshell.env("HOME") + "/.config/quickshell/caelestia/context_menu.json"

    property var entries: []
    property var pendingEntries: []
    property bool loaded: false
    property bool loading: false
    property bool cacheValid: false
    property bool writeQueued: false
    property real loadStartedAt: 0
    property real saveStartedAt: 0

    signal openDesktopContextMenu(real x, real y, string screenName)

    function defaultEntries() {
        return [
            { id: "toggle_desktop_icons", label: qsTr("Desktop Icons"), icon: "desktop_windows", action: "ToggleDesktopIcons", enabled: true, type: "default" },
            { id: "next_wallpaper", label: qsTr("Next Wallpaper"), icon: "skip_next", action: "Wallpapers.next()", enabled: true, type: "default" },
            { id: "wallpaper_style", label: qsTr("Wallpaper & style"), icon: "wallpaper", action: "WindowFactory.create()", enabled: true, type: "default" },
            { id: "system_settings", label: qsTr("System Settings"), icon: "settings", command: "systemsettings", enabled: true, type: "default" },
            { id: "open_terminal", label: qsTr("Open Terminal"), icon: "terminal", command: "terminal", enabled: true, type: "default" },
            { id: "add_shortcut", label: qsTr("Add Shortcut..."), icon: "add", action: "OpenRightClickMenu", enabled: true, type: "default" }
        ];
    }

    function cloneEntries(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function ensureLoaded(forceDisk) {
        if (loading) return;
        if (forceDisk !== true && cacheValid) return;

        loading = true;
        loadStartedAt = Date.now();
        readProc.running = true;
    }

    function save(newEntries) {
        pendingEntries = cloneEntries(newEntries);
        entries = cloneEntries(newEntries);
        loaded = true;
        cacheValid = true;

        saveStartedAt = Date.now();
        saveDebounce.restart();
    }

    function startWrite(): void {
        if (writeProc.running) {
            writeQueued = true;
            return;
        }

        writeQueued = false;
        writeProc.jsonContent = JSON.stringify(pendingEntries);
        writeProc.running = true;
    }

    Process {
        id: readProc

        command: ["sh", "-c", "cat \"" + root.menuPath + "\" 2>/dev/null || echo '[]'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = [];
                try {
                    if (text.trim().length > 0) {
                        parsed = JSON.parse(text);
                    }
                } catch (e) {
                    // Otherwise a malformed file silently reverts to the defaults, and the
                    // user's own entries disappear with nothing in the journal.
                    console.warn("[ContextMenuStore] ignoring an unreadable menu file:", e);
                }

                if (!parsed || parsed.length === 0) {
                    parsed = root.defaultEntries();
                }

                root.entries = root.cloneEntries(parsed);
                root.loaded = true;
                root.cacheValid = true;
                root.loading = false;

                const loadMs = root.loadStartedAt > 0 ? (Date.now() - root.loadStartedAt) : 0;
                console.log("[perf][ContextMenuStore] load disk ms=" + loadMs + " entries=" + root.entries.length);
                root.loadStartedAt = 0;
            }
        }
    }

    Timer {
        id: saveDebounce

        interval: 180
        repeat: false
        onTriggered: root.startWrite()
    }

    Process {
        id: writeProc

        property string jsonContent: ""

        command: [
            "python3",
            "-c",
            "import sys, os; p=sys.argv[1]; d=os.path.dirname(p); os.makedirs(d, exist_ok=True) if d else None; open(p, 'w').write(sys.argv[2])",
            root.menuPath,
            jsonContent
        ]

        onRunningChanged: {
            if (running) {
                return;
            } else if (root.saveStartedAt > 0) {
                const saveMs = Date.now() - root.saveStartedAt;
                console.log("[perf][ContextMenuStore] save disk ms=" + saveMs + " entries=" + root.pendingEntries.length);
                root.saveStartedAt = 0;
            }

            if (root.writeQueued)
                saveDebounce.restart();
        }

        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    FileView {
        path: root.menuPath
        watchChanges: true
        printErrors: false

        onFileChanged: {
            if (writeProc.running) return;
            root.cacheValid = false;
            root.ensureLoaded(true);
        }
    }

    Component.onCompleted: ensureLoaded(true)
}
