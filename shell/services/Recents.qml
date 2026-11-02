pragma Singleton

import QtQuick
import Quickshell

/// The documents an application opened recently, for the dock's jump list.
///
/// Parsing `recently-used.xbel` belongs to `scripts/recents.py`. `load()` takes the
/// names the caller knows the application by, because a desktop entry id, an app class
/// and the name the file records are rarely spelled the same way.
Singleton {
    id: root

    readonly property var entries: read.result ?? []
    readonly property bool loaded: read.loaded
    readonly property string error: read.error

    function load(apps: list<string>): void {
        const args = ["--limit", "5"];
        for (const app of apps)
            args.push("--app", app);
        read.args = args;
        read.start();
    }

    JsonScript {
        id: read

        script: "scripts/recents.py"
    }
}
