pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property alias enabled: props.enabled

    readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    property bool restoreVideoWallpaper: false

    property bool autoEnabled: false

    readonly property var _windows: Kwin.windowList

    function _matchesRule(w): bool {
        const rules = GlobalConfig.utilities.gameMode.autoEnableRegexes || [];
        if (rules.length === 0 || !w)
            return false;
        const fields = [w.class || "", w.initialClass || "", w.title || ""];
        for (let i = 0; i < rules.length; i++) {
            const rule = String(rules[i] || "");
            if (rule === "")
                continue;
            for (let f = 0; f < fields.length; f++) {
                if (fields[f] === rule)
                    return true;
                try {
                    if (new RegExp(rule).test(fields[f]))
                        return true;
                } catch (e) {
                }
            }
        }
        return false;
    }

    on_WindowsChanged: {
        const wins = root._windows || [];
        let matched = false;
        for (let i = 0; i < wins.length; i++)
            if (root._matchesRule(wins[i])) { matched = true; break; }

        if (matched && !root.enabled) {
            root.autoEnabled = true;
            root.enabled = true;
        } else if (!matched && root.enabled && root.autoEnabled) {
            root.autoEnabled = false;
            root.enabled = false;
        }
    }

    function setDynamicConfs(): void {
        Kwin.extras.applyOptions({
            "animations:enabled": 0,
            "decoration:shadow:enabled": 0,
            "decoration:blur:enabled": 0,
            "general:gaps_in": 0,
            "general:gaps_out": 0,
            "general:border_size": 1,
            "decoration:rounding": 0,
            "general:allow_tearing": 1
        });
    }

    function applyKwin(enable: bool): void {
        const stateFile = `${Paths.cache}/gamemode-state`;
        if (enable) {
            Quickshell.execDetached(["sh", "-c",
                `p="${stateFile}"; ` +
                '[ -e "$p" ] || { ' +
                'prevBlur="$(kreadconfig6 --file kwinrc --group Plugins --key blurEnabled --default true)"; ' +
                'prevAnim="$(kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --default 1)"; ' +
                'mkdir -p "$(dirname "$p")"; printf "%s\\n%s\\n" "$prevBlur" "$prevAnim" > "$p"; }; ' +
                'kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false; ' +
                'kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify 0; ' +
                'qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1']);
        } else {
            Quickshell.execDetached(["sh", "-c",
                `p="${stateFile}"; ` +
                'blur="$(sed -n 1p "$p" 2>/dev/null)"; anim="$(sed -n 2p "$p" 2>/dev/null)"; ' +
                '[ -n "$blur" ] || blur=true; [ -n "$anim" ] || anim=1; ' +
                'kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled "$blur"; ' +
                'kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify "$anim"; ' +
                'rm -f "$p"; ' +
                'qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1']);
        }
    }

    onEnabledChanged: {
        if (!enabled)
            root.autoEnabled = false;

        if (enabled) {
            root.restoreVideoWallpaper = !GlobalConfig.background.videoWallpaperPaused;
            if (root.restoreVideoWallpaper)
                GlobalConfig.background.videoWallpaperPaused = true;

            if (root.onHyprland)
                setDynamicConfs();
            else
                applyKwin(true);

            if (GlobalConfig.utilities.toasts.gameModeChanged)
                Toaster.toast(qsTr("Game mode enabled"),
                    root.onHyprland ? qsTr("Disabled Hyprland animations, blur, gaps and shadows")
                                    : qsTr("Paused video wallpaper, disabled blur and animations"), "gamepad");
        } else {
            if (root.restoreVideoWallpaper) {
                GlobalConfig.background.videoWallpaperPaused = false;
                root.restoreVideoWallpaper = false;
            }

            if (root.onHyprland)
                Kwin.extras.message("reload");
            else
                applyKwin(false);

            if (GlobalConfig.utilities.toasts.gameModeChanged)
                Toaster.toast(qsTr("Game mode disabled"),
                    root.onHyprland ? qsTr("Hyprland settings restored") : qsTr("Desktop effects restored"), "gamepad");
        }
    }

    PersistentProperties {
        id: props

        property bool enabled: false

        reloadableId: "gameMode"
    }


    FileView {
        path: `${Paths.cache}/gamemode-state`
        printErrors: false
        onLoaded: {
            if (props.enabled)
                return;
            if (root.onHyprland) {
                Quickshell.execDetached(["rm", "-f", `${Paths.cache}/gamemode-state`]);
            } else {
                root.applyKwin(false);
            }
        }
    }

    Connections {
        function onConfigReloaded(): void {
            if (props.enabled)
                root.setDynamicConfs();
        }

        target: Kwin
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "gameMode"
    }
}
