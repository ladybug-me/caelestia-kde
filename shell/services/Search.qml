pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Services

/// System-wide search through KRunner, for the launcher's search mode. The shell
/// has its own sources for apps, windows, emoji and clipboard; this is what
/// reaches the rest of the system (files, places, web shortcuts, definitions,
/// unit conversion, settings modules).
///
/// Results are re-published as each runner answers, so `results` keeps growing
/// until KRunner has nothing more to add.
Singleton {
    id: root

    readonly property var results: KRunnerBridge.results

    function search(text: string): void {
        KRunnerBridge.search(text);
    }

    function clear(): void {
        KRunnerBridge.clear();
    }

    function run(id: string, actionId: string): void {
        KRunnerBridge.run(id, actionId ?? "");
    }

    /// The runner manager lives in the shell process, so a config it reads on startup
    /// only takes effect here after it is told to re-read it.
    function reloadConfiguration(): void {
        KRunnerBridge.reloadConfiguration();
    }
}
