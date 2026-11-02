pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services

// Central manager for KDE Plasma desktop widgets (applets running on Plasma's desktop containment).
// Plasma desktop widgets run on the Wayland BACKGROUND layer, ignoring layer-shell exclusion zones,
// so their positions must be calculated dynamically based on Caelestia's shell exclusions (bar, sidebar, margins).
Singleton {
    id: root

    readonly property ShellScreen primaryScreen: Screens.screens[0] ?? Quickshell.screens[0]
    readonly property var primaryExclusions: Visibilities.exclusionsFor(primaryScreen)
    readonly property var primaryBar: Visibilities.bars.get(primaryScreen?.name)
    readonly property real barZone: primaryBar?.exclusiveZone ?? 40

    // Usable desktop bounds for the primary screen where Plasma desktop widgets reside
    readonly property real leftExclusion: primaryExclusions ? primaryExclusions.leftExclusion : (Config.bar.position === "left" ? barZone : Config.border.thickness)
    readonly property real topExclusion: primaryExclusions ? primaryExclusions.topExclusion : (Config.bar.position === "top" ? barZone : Config.border.thickness)
    readonly property real rightExclusion: primaryExclusions ? primaryExclusions.rightExclusion : (Config.bar.position === "right" ? barZone : Config.border.thickness)
    readonly property real bottomExclusion: primaryExclusions ? primaryExclusions.bottomExclusion : (Config.bar.position === "bottom" ? barZone : Config.border.thickness)

    readonly property real screenWidth: primaryScreen?.width ?? 1920
    readonly property real screenHeight: primaryScreen?.height ?? 1080

    readonly property real usableWidth: primaryExclusions ? primaryExclusions.usableWidth : Math.max(100, screenWidth - leftExclusion - rightExclusion)
    readonly property real usableHeight: primaryExclusions ? primaryExclusions.usableHeight : Math.max(100, screenHeight - topExclusion - bottomExclusion)
    readonly property rect usableArea: Qt.rect(leftExclusion, topExclusion, usableWidth, usableHeight)

    // Track visualizer enabled status and profile from configuration
    readonly property bool visualizerEnabled: Config.background.visualiser.enabled
    readonly property string visualizerProfile: Config.background.visualiser.profile
    readonly property bool visualizerAutoHide: Config.background.visualiser.autoHide
    readonly property bool visualizerHideOnAllMonitors: Config.background.visualiser.hideOnAllMonitors
    readonly property bool isPlayerPlaying: {
        if (Players.active?.isPlaying)
            return true;
        const list = Players.list;
        for (let i = 0; i < list.length; i++) {
            if (list[i]?.isPlaying)
                return true;
        }
        return false;
    }
    readonly property bool windowHidesVisualizer: (Kwin.windowList, Kwin.activeWsId, Kwin.activeByOutput, Kwin.windowHidesDesktopWidgets(root.primaryScreen ? root.primaryScreen.name : "", visualizerHideOnAllMonitors))
    readonly property bool gameModeSuppressesVisualizer: GameMode.enabled && GlobalConfig.utilities.gameMode.disableVisualizer
    readonly property bool visualizerBaseConditions: visualizerEnabled && root.hasVisualizer && !gameModeSuppressesVisualizer && (!visualizerAutoHide || !windowHidesVisualizer)
    readonly property bool visualizerEffectiveEnabled: visualizerBaseConditions && debouncedPlayerPlaying

    property bool debouncedPlayerPlaying: false
    property bool hasVisualizer: false
    property bool visualizerActive: false
    property bool ready: false

    // Geometry calculator for the audio visualizer (dual channel symmetric split)
    function calculateVisualizerGeometries(): var {
        if (!primaryScreen)
            return null;

        const isSingle = root.visualizerProfile === "single";
        const centerGap = Math.round(root.screenWidth * (224 / 1920));
        const visW = isSingle ? Math.round(root.usableWidth) : Math.floor((root.usableWidth - centerGap) / 2);
        const visH = Math.round(root.usableHeight * (416 / 1080));
        const rawY = Math.round(root.screenHeight - root.bottomExclusion - visH);
        // Ensure visualizer is strictly clamped near the bottom edge
        const minY = Math.round(root.screenHeight * 0.5);
        const maxY = Math.round(root.screenHeight - root.bottomExclusion - visH);
        const visY = Math.max(minY, Math.min(maxY, rawY));

        const visX1 = Math.round(root.leftExclusion <= Config.border.thickness ? 0 : root.leftExclusion);
        const visX2 = Math.round(
            root.rightExclusion <= Config.border.thickness
                ? root.screenWidth - visW
                : root.screenWidth - root.rightExclusion - visW
        );

        return {
            x1: visX1,
            y1: visY,
            w1: visW,
            h1: visH,
            x2: visX2,
            y2: visY,
            w2: visW,
            h2: visH
        };
    }

    // Calculate geometries for a given widget ID (extensible for future widgets)
    function calculateWidgetGeometries(widgetId: string): var {
        switch (widgetId) {
        case "visualizer":
            return calculateVisualizerGeometries();
        default:
            return null;
        }
    }

    // Check if a widget is currently active/enabled
    function isWidgetEnabled(widgetId: string): bool {
        switch (widgetId) {
        case "visualizer":
            return root.visualizerEffectiveEnabled;
        default:
            return false;
        }
    }

    // Enable a widget and place it at the computed geometry
    function enableWidget(widgetId: string): void {
        const geom = calculateWidgetGeometries(widgetId);
        const scriptPath = Quickshell.shellPath("scripts/export-plasma-config.sh");

        switch (widgetId) {
        case "visualizer":
            const prof = root.visualizerProfile || "double_reversed";
            if (prof !== "user" && geom) {
                Quickshell.execDetached([
                    "bash", scriptPath, "visualizer", "enable", prof,
                    geom.x1.toString(), geom.y1.toString(), geom.w1.toString(), geom.h1.toString(),
                    geom.x2.toString(), geom.y2.toString(), geom.w2.toString(), geom.h2.toString()
                ]);
            } else {
                Quickshell.execDetached(["bash", scriptPath, "visualizer", "enable", prof]);
            }
            break;
        default:
            console.warn("PlasmaWidgets: unknown widget id", widgetId);
            break;
        }
    }

    // Disable and remove a widget
    function disableWidget(widgetId: string): void {
        const scriptPath = Quickshell.shellPath("scripts/export-plasma-config.sh");

        switch (widgetId) {
        case "visualizer":
            const prof = root.visualizerProfile || "double_reversed";
            Quickshell.execDetached(["bash", scriptPath, "visualizer", "disable", prof]);
            break;
        default:
            console.warn("PlasmaWidgets: unknown widget id", widgetId);
            break;
        }
    }

    // Set widget enabled state
    function setWidgetEnabled(widgetId: string, enabled: bool): void {
        switch (widgetId) {
        case "visualizer":
            GlobalConfig.background.visualiser.enabled = enabled;
            break;
        default:
            break;
        }
    }

    // Set visualizer profile preset
    function setVisualizerProfile(profile: string): void {
        GlobalConfig.background.visualiser.profile = profile;
        if (root.visualizerEnabled)
            enableWidget("visualizer");
    }

    // Sync widget position live without re-saving appletsrc
    function syncWidgetGeometry(widgetId: string): void {
        if (!isWidgetEnabled(widgetId))
            return;

        const geom = calculateWidgetGeometries(widgetId);
        if (!geom)
            return;

        const scriptPath = Quickshell.shellPath("scripts/export-plasma-config.sh");

        switch (widgetId) {
        case "visualizer":
            const prof = root.visualizerProfile || "double_reversed";
            if (prof === "user")
                return;
            Quickshell.execDetached([
                "bash", scriptPath, "visualizer", "geometry", prof,
                geom.x1.toString(), geom.y1.toString(), geom.w1.toString(), geom.h1.toString(),
                geom.x2.toString(), geom.y2.toString(), geom.w2.toString(), geom.h2.toString()
            ]);
            break;
        default:
            break;
        }
    }

    // Sync all currently active widgets
    function syncAll(): void {
        if (visualizerEffectiveEnabled)
            syncWidgetGeometry("visualizer");
    }

    // Debounce rapid exclusion or geometry updates
    function scheduleSync(): void {
        if (!ready)
            return;
        syncTimer.restart();
    }

    function updateVisualizerState(): void {
        if (!ready)
            return;
        const target = visualizerEffectiveEnabled;
        if (visualizerActive === target)
            return;
        visualizerActive = target;
        if (target)
            enableWidget("visualizer");
        else
            disableWidget("visualizer");
    }

    // Snapshot live visualizer state at start of edit mode
    function snapshotVisualizerState(): void {
        const scriptPath = Quickshell.shellPath("scripts/export-plasma-config.sh");
        Quickshell.execDetached(["bash", scriptPath, "visualizer", "snapshot"]);
    }

    // Check if visualizer widgets changed in edit mode, save to user.conf and switch profile
    function checkVisualizerEditModeChange(): void {
        const scriptPath = Quickshell.shellPath("scripts/export-plasma-config.sh");
        checkEditModeProc.command = ["bash", scriptPath, "visualizer", "check-edit-mode"];
        checkEditModeProc.running = true;
    }

    onLeftExclusionChanged: scheduleSync()
    onTopExclusionChanged: scheduleSync()
    onRightExclusionChanged: scheduleSync()
    onBottomExclusionChanged: scheduleSync()
    onUsableWidthChanged: scheduleSync()
    onUsableHeightChanged: scheduleSync()

    onIsPlayerPlayingChanged: {
        if (isPlayerPlaying) {
            playerStopTimer.stop();
            debouncedPlayerPlaying = true;
        } else {
            if (!ready) {
                debouncedPlayerPlaying = false;
            } else {
                playerStopTimer.restart();
            }
        }
    }

    onVisualizerBaseConditionsChanged: {
        if (!visualizerBaseConditions) {
            playerStopTimer.stop();
            if (!isPlayerPlaying)
                debouncedPlayerPlaying = false;
        }
    }

    onVisualizerEffectiveEnabledChanged: {
        if (!ready)
            return;
        updateVisualizerState();
    }

    onVisualizerProfileChanged: {
        if (!ready)
            return;
        if (visualizerEffectiveEnabled)
            enableWidget("visualizer");
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            root.ready = true;
            root.debouncedPlayerPlaying = root.isPlayerPlaying;
            root.visualizerActive = root.visualizerEffectiveEnabled;
            if (!root.visualizerEffectiveEnabled && root.visualizerEnabled) {
                root.disableWidget("visualizer");
            } else if (root.visualizerEffectiveEnabled) {
                root.scheduleSync();
            }
        });
    }

    Timer {
        id: playerStopTimer

        interval: 1000
        repeat: false
        onTriggered: root.debouncedPlayerPlaying = false
    }

    Connections {
        function onExclusionBoundsChanged(screen: ShellScreen): void {
            if (screen === root.primaryScreen)
                root.scheduleSync();
        }

        target: Visibilities
    }

    Connections {
        function onPositionChanged(): void {
            root.scheduleSync();
        }

        target: Config.bar
    }

    Connections {
        function onThicknessChanged(): void {
            root.scheduleSync();
        }

        target: Config.border
    }

    Timer {
        id: syncTimer

        interval: 150
        repeat: false
        onTriggered: root.syncAll()
    }

    Process {
        id: checkEditModeProc

        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const lastLine = lines.length > 0 ? lines[lines.length - 1].trim() : "";
                if (lastLine === "STATUS_CHANGED") {
                    GlobalConfig.background.visualiser.profile = "user";
                    GlobalConfig.save();
                }
            }
        }
    }

    Connections {
        function onEditModeChanged(): void {
            if (ContextMenuStore.editMode)
                root.snapshotVisualizerState();
            else
                root.checkVisualizerEditModeChange();
        }

        target: ContextMenuStore
    }

    Process {
        id: plasmaVisualizerCheckProcess

        running: true
        command: ["sh", "-c", "test -d \"$HOME/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer\" || test -d \"/usr/share/plasma/plasmoids/luisbocanegra.audio.visualizer\" || (command -v kpackagetool6 >/dev/null 2>&1 && kpackagetool6 -t Plasma/Applet -s luisbocanegra.audio.visualizer >/dev/null 2>&1)"]

        onExited: code => {
            root.hasVisualizer = (code === 0);
        }
    }
}
