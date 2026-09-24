pragma ComponentBehavior: Bound

// Environment variables originally set via //@ pragma directives moved to
// the launcher scripts (08-build-shell.sh, 10-autostart.sh) for broader
// quickshell version compatibility. The crash-report URL is not pinned here:
// forks point QS_CRASHREPORT_URL at their own issue tracker from their
// launcher scripts, alongside CAELESTIA_REPO_OWNER (see README, "For forks").
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
import "modules/areapicker"
import "modules/polkit"
import "modules/screenshot/regionSelector"
import "modules/overview"
import "modules/whatsnew" as WhatsNew

ShellRoot {
    id: root

    property var regionSelector: RegionSelector {}

    // Force service initialization
    property var _arpcInit: null
    property var _gameModeInit: null
    property var _updateCheckerInit: null
    property var _autoSchemeInit: null

    settings.watchFiles: false

    Component.onCompleted: {
        deferredStartup.start();
    }

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    // UI translations. The catalogues live next to the shell (shell/translations,
    // installed as <shell>/translations/caelestia_<code>.qm), so resolving the
    // path relative to this file works both from the install tree and when
    // running the shell straight from a checkout.
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

    Fonts {}
    GSFLoader {}
    ServiceLoader {}

    Background {}
    BadAppleOverlay {}

    Drawers {}
    // AreaPicker {}
    // PolkitModule {}

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
            root._updateCheckerInit = UpdateChecker;
            root._autoSchemeInit = AutoScheme;
        }
    }

    Services.StartupTasks {}
    WhatsNew.WhatsNewWindow {}

    Process {
        id: bbdxCheckProcess

        running: false
        command: ["bash", "-c", `
            IS_ENABLED=$(kreadconfig6 --file kwinrc --group Plugins --key better_blur_dxEnabled)
            if [ "$IS_ENABLED" = "true" ]; then
                BLUR_MATCHING=$(kreadconfig6 --file kwinrc --group Effect-better-blur-dx --key BlurMatching)
                BLUR_NON_MATCHING=$(kreadconfig6 --file kwinrc --group Effect-better-blur-dx --key BlurNonMatching)
                WINDOW_CLASSES=$(kreadconfig6 --file kwinrc --group Effect-better-blur-dx --key WindowClasses)

                if [ -z "$BLUR_MATCHING" ]; then BLUR_MATCHING="true"; fi
                if [ -z "$BLUR_NON_MATCHING" ]; then BLUR_NON_MATCHING="false"; fi

                MODIFIED=false

                if [ "$BLUR_MATCHING" = "true" ] && [ "$BLUR_NON_MATCHING" = "false" ]; then
                    if echo "$WINDOW_CLASSES" | grep -q '\\bquickshell\\b'; then
                        # Remove quickshell without destroying the rest of the line if comma-separated
                        NEW_CLASSES=$(echo "$WINDOW_CLASSES" | sed -E 's/\\bquickshell\\b//g' | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
                        kwriteconfig6 --file kwinrc --group Effect-better-blur-dx --key WindowClasses "$NEW_CLASSES"
                        MODIFIED=true
                    fi
                elif [ "$BLUR_MATCHING" = "false" ] && [ "$BLUR_NON_MATCHING" = "true" ]; then
                    if ! echo "$WINDOW_CLASSES" | grep -q '\\bquickshell\\b'; then
                        if [ -z "$WINDOW_CLASSES" ]; then
                            NEW_CLASSES="quickshell"
                        elif echo "$WINDOW_CLASSES" | grep -q ','; then
                            NEW_CLASSES="$WINDOW_CLASSES,quickshell"
                        else
                            NEW_CLASSES="$WINDOW_CLASSES"$'\n'"quickshell"
                        fi
                        kwriteconfig6 --file kwinrc --group Effect-better-blur-dx --key WindowClasses "$NEW_CLASSES"
                        MODIFIED=true
                    fi
                fi

                if [ "$MODIFIED" = "true" ]; then
                    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
                    qdbus6 org.kde.KWin /Effects reconfigureEffect better_blur_dx 2>/dev/null || true
                fi

                echo "BBDX_ENABLED"
            fi
        `]

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
    IdleMonitors {}
    BluetoothReconnect {}
}
