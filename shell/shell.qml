pragma ComponentBehavior: Bound

// Qt's own default render type is QtRendering, and the Rubik font draws nothing
// through it on Qt 6.11. Making native the process default keeps every text item
// drawing, including the bare Text items that no component pins a type on.
//@ pragma NativeTextRendering

// Environment variables originally set via //@ pragma directives moved to
// the launcher scripts (08-build-shell.sh, 10-autostart.sh) for broader
// quickshell version compatibility.
//@ pragma Env QS_CRASHREPORT_URL=https://github.com/ladybug-me/caelestia-kde/issues/new?template=crash.yml
// //@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
// //@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
// //@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
// //@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components.containers
import qs.services
import qs.services.api
import qs.utils
import "services" as Services
import "modules"
import "modules/drawers"
import "modules/background"
import "modules/screenshot/regionSelector"
import "modules/overview"
import "modules/whatsnew" as WhatsNew

ShellRoot {
    id: root

    property var regionSelector: RegionSelector {}

    property var _arpcInit: null
    property var _gameModeInit: null
    property var _streamMonitorInit: null
    property var _updateCheckerInit: null
    property var _autoSchemeInit: null
    property var _quickShareInit: null
    property var _calendarInit: null
    property var _focusInit: null
    property var _accessibilityInit: null

    settings.watchFiles: false

    Component.onCompleted: {
        deferredStartup.start();
    }

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    Binding {
        target: Translations
        property: "extraSearchPaths"
        value: [Qt.resolvedUrl("translations")]
    }

    Binding {
        target: Translations
        property: "language"
        value: GlobalConfig.general.language
    }

    GSFLoader {}
    ServiceLoader {}

    Background {}

    EditModeOverlay {}

    Drawers {}

    IpcHandler {
        function screenshot(): void {
            regionSelector.screenshot();
        }

        function search(): void {
            regionSelector.search();
        }

        function ocr(): void {
            regionSelector.ocr();
        }

        function record(): void {
            regionSelector.record();
        }

        function recordWithSound(): void {
            regionSelector.recordWithSound();
        }

        target: "region"
    }

    IpcHandler {
        function lock(): void {
            Quickshell.execDetached(["loginctl", "lock-session"]);
            Audio.playLock();
        }

        function unlock(): void {
            Quickshell.execDetached(["loginctl", "unlock-session"]);
        }

        target: "lock"
    }

    Shortcuts {}
    ScreenCorners {}

    Timer {
        id: deferredStartup

        interval: 250
        repeat: false

        onTriggered: {
            PluginLoader.loadPlugins();
            bbdxCheckProcess.running = true;
            root._arpcInit = DiscordRPC;
            root._gameModeInit = GameMode;
            root._streamMonitorInit = StreamMonitor;
            root._updateCheckerInit = UpdateChecker;
            root._autoSchemeInit = AutoScheme;
            root._quickShareInit = QuickShare;
            // These three do work on their own timers, so they cannot wait for a
            // surface to ask for them: the agenda fetches, focus flips DND on the
            // minute, and the shell text has to follow KDE's before anything is drawn.
            root._calendarInit = CalendarEvents;
            root._focusInit = Focus;
            root._accessibilityInit = Accessibility;
        }
    }

    Services.StartupTasks {}
    WhatsNew.WhatsNewWindow {}

    Process {
        id: bbdxCheckProcess

        running: false
        command: ["bash", Quickshell.shellDir + "/scripts/bbdx-window-classes.sh"]

        stdout: StdioCollector {
            id: bbdxStdout
        }

        onExited: {
            if (bbdxStdout.text.trim() === "BBDX_ENABLED") {
                GlobalConfig.appearance.blur = true;
            }
        }
    }

    BatteryMonitor {}
    BluetoothReconnect {}
}
