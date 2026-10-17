pragma Singleton

import QtQuick
import Quickshell
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

    // Track visualizer enabled status from configuration
    readonly property bool visualizerEnabled: Config.background.visualiser.enabled

    property bool ready: false

    // Geometry calculator for the audio visualizer (dual channel symmetric split)
    function calculateVisualizerGeometries(): var {
        if (!primaryScreen)
            return null;

        const centerGap = Math.round(root.screenWidth * (224 / 1920));
        const visW = Math.floor((root.usableWidth - centerGap) / 2);
        const visH = Math.round(root.usableHeight * 0.40);
        const rawY = Math.round(
            root.bottomExclusion <= Config.border.thickness
                ? root.screenHeight - visH - 8
                : root.screenHeight - root.bottomExclusion - visH - 8
        );
        // Ensure visualizer is strictly clamped near the bottom edge
        const minY = Math.round(root.screenHeight * 0.5);
        const maxY = Math.round(root.screenHeight - visH - 4);
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
            return root.visualizerEnabled;
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
            if (geom) {
                Quickshell.execDetached([
                    "bash", scriptPath, "visualizer", "enable",
                    geom.x1.toString(), geom.y1.toString(), geom.w1.toString(), geom.h1.toString(),
                    geom.x2.toString(), geom.y2.toString(), geom.w2.toString(), geom.h2.toString()
                ]);
            } else {
                Quickshell.execDetached(["bash", scriptPath, "visualizer", "enable"]);
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
            Quickshell.execDetached(["bash", scriptPath, "visualizer", "disable"]);
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
            Quickshell.execDetached([
                "bash", scriptPath, "visualizer", "geometry",
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
        if (visualizerEnabled)
            syncWidgetGeometry("visualizer");
    }

    // Debounce rapid exclusion or geometry updates
    function scheduleSync(): void {
        if (!ready)
            return;
        syncTimer.restart();
    }

    onLeftExclusionChanged: scheduleSync()
    onTopExclusionChanged: scheduleSync()
    onRightExclusionChanged: scheduleSync()
    onBottomExclusionChanged: scheduleSync()
    onUsableWidthChanged: scheduleSync()
    onUsableHeightChanged: scheduleSync()

    onVisualizerEnabledChanged: {
        if (!ready)
            return;
        if (visualizerEnabled)
            enableWidget("visualizer");
        else
            disableWidget("visualizer");
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            root.ready = true;
            if (root.visualizerEnabled)
                root.scheduleSync();
        });
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

    Timer {
        id: syncTimer

        interval: 150
        repeat: false
        onTriggered: root.syncAll()
    }
}
