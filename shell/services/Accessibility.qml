pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

/// The accessibility switches the shell can drive, and the one thing it cannot: the
/// system text size, which belongs to KDE.
///
/// Everything visual the shell draws comes from its own token fonts, so enlarging the
/// text in System Settings used to leave the shell untouched. `followSystemScale` keeps
/// the two together by reading KDE's font size and writing it as the shell's type scale.
/// The rest drives KWin itself: the magnifier, colour inversion and the colour-blindness
/// filters are KWin effects, so this only loads and unloads them and reports what KWin
/// says is loaded.
Singleton {
    id: root

    /// The point size the shell's type scale is drawn for, and the range it will follow.
    readonly property int basePointSize: 10
    readonly property real minScale: 0.5
    readonly property real maxScale: 2

    /// KDE's font size in points, or 0 when KDE carries no `font` key (its default).
    property int systemPointSize: 0
    property var loadedEffects: []
    property bool screenReaderInstalled: false

    readonly property bool followSystem: GlobalConfig.appearance.font.followSystemScale

    readonly property real systemScale: {
        const points = root.systemPointSize > 0 ? root.systemPointSize : root.basePointSize;
        const scale = points / root.basePointSize;
        return Math.max(root.minScale, Math.min(root.maxScale, Math.round(scale * 100) / 100));
    }

    function applySystemScale(): void {
        if (!root.followSystem)
            return;

        const fontNode = GlobalConfig.appearance.font;
        if (fontNode.isOverride("scale") && !fontNode.isOverride("followSystemScale"))
            return;

        const current = GlobalConfig.appearance.font.scale;
        if (Math.abs(current - root.systemScale) < 0.005)
            return;

        GlobalConfig.appearance.font.scale = root.systemScale;
        GlobalConfig.save();
    }

    function isEffectLoaded(name: string): bool {
        return root.loadedEffects.indexOf(name) >= 0;
    }

    /// Loads or unloads one of KWin's effects, then re-reads the list: what the page
    /// shows is what KWin reports, not what this side hoped the call did.
    function setEffect(name: string, on: bool): void {
        const method = on ? "loadEffect" : "unloadEffect";
        Quickshell.execDetached(["qdbus6", "org.kde.KWin", "/Effects", `org.kde.kwin.Effects.${method}`, name]);
        effectsReload.restart();
    }

    function startScreenReader(): void {
        if (root.screenReaderInstalled)
            Quickshell.execDetached(["orca"]);
    }

    Component.onCompleted: {
        effectsProcess.running = true;
        root.applySystemScale();
    }

    onFollowSystemChanged: root.applySystemScale()

    /// One query for the whole list. Asking per effect would mean matching a positional
    /// reply, which breaks the moment KWin answers in a different shape.
    Process {
        id: effectsProcess

        command: ["qdbus6", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects.loadedEffects"]

        stdout: StdioCollector {
            onStreamFinished: root.loadedEffects = text.trim().split(",").filter(name => name.length > 0)
        }
    }

    /// KWin applies the call asynchronously, so give it a moment before asking.
    Timer {
        id: effectsReload

        interval: 300
        onTriggered: effectsProcess.running = true
    }

    Process {
        id: orcaCheck

        command: ["bash", "-c", "command -v orca"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.screenReaderInstalled = text.trim().length > 0
        }
    }

    /// `~/.config/kdeglobals` is watched rather than polled: KDE writes the key when the
    /// user changes the font, which is the only moment the value can change.
    FileView {
        id: kdeGlobals

        path: `${Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config"}/kdeglobals`
        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        onLoaded: {
            // `font` is a KConfig entry shaped "Family,11,-1,5,...", where the point
            // size is the second field. No key means KDE is on its default.
            let points = 0;
            let inGeneral = false;
            for (const raw of text().split("\n")) {
                const line = raw.trim();
                if (line.startsWith("[")) {
                    inGeneral = line === "[General]";
                    continue;
                }
                if (!inGeneral || !line.startsWith("font="))
                    continue;

                const size = parseInt(line.substring(5).split(",")[1] ?? "", 10);
                points = isNaN(size) || size <= 0 ? 0 : size;
                break;
            }

            root.systemPointSize = points;
            root.applySystemScale();
        }
    }
}
