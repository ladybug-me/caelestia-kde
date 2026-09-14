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

    // Hyprland is not always the compositor this runs under. Everything below
    // branches on that rather than assuming it.
    // Quickshell.env returns undefined for an unset variable, not "", so compare
    // truthiness — !== "" was true everywhere and sent KDE down the Hyprland path.
    readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    // Video wallpapers keep a decoder and a GPU upload running for as long as
    // they play, which is exactly what game mode is trying to free up.
    property bool restoreVideoWallpaper: false

    // ---- Auto-enable rules ----
    // The rules were editable in settings but nothing ever evaluated them, so
    // launching a listed game did nothing. Watch the open windows and match them.
    // Only a run that switched itself on switches itself back off, so a manual
    // toggle is never undone by a game closing.
    property bool autoEnabled: false

    readonly property var _windows: {
        if (Kwin.windowList.length > 0)
            return Kwin.windowList;
        return HyprlandData.windowList;
    }

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
                    return true;          // plain name, the common case
                try {
                    if (new RegExp(rule).test(fields[f]))
                        return true;
                } catch (e) {
                    // A rule like "Minecraft* 1.21.11" is a window title, not a
                    // valid regex — the exact match above already covers it.
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

    // KWin's equivalents of the Hyprland options above: window animations and the
    // blur effect. Both are read back before being changed so a user who already
    // had them off does not get them switched on when game mode ends.
    //
    // The read-back has to happen at most once per game mode session, not once
    // per call — otherwise a second run reads back game mode's *own*
    // already-applied values (blur off, animations off) and overwrites
    // gamemode-state with those, permanently losing the user's real settings.
    // A QML-side guard isn't enough: PersistentProperties does not survive a
    // real process restart or crash (only an in-process hot reload, and not
    // reliably even then — confirmed by testing), so a guard flag living in QML
    // state resets right along with everything else and misses exactly the case
    // that matters. gamemode-state's own existence on disk is the guard instead:
    // it is real, persists across anything, and is the one thing that has to
    // stay in sync with "is there a previous state saved right now" by
    // construction, since it *is* that state. The save step only runs if the
    // file doesn't already exist; the restore step deletes it once done, so the
    // next session starts clean.
    //
    // The general shape — toggle something, remember what it was before, put it
    // back later — recurs for any feature that temporarily overrides a KDE/
    // Hyprland setting. Guard the save step the same way: the presence of the
    // saved-state file itself, not an in-memory or PersistentProperties flag.
    //
    // AnimationDurationFactor lives in kdeglobals, a generic Qt/Plasma setting
    // rather than a KWin-specific one, and writing it with plain kwriteconfig6
    // only updates the file — nothing tells already-running apps (KWin's own
    // compositor included) to re-read it, so the config value changes but the
    // live animation speed doesn't, until something else touches the file and
    // happens to trigger a reload. Confirmed with dbus-monitor: changing it
    // through System Settings broadcasts org.kde.kconfig.notify's
    // ConfigChanged on /kdeglobals; kwriteconfig6's --notify flag emits the
    // identical signal, which is what actually makes it take effect live.
    // blurEnabled is a KWin effect setting in kwinrc, not a generic one, and
    // reconfigure() below already covers it — no separate live-apply gap there.
    //
    // The state file's path is built from Paths.cache rather than hardcoding
    // $HOME/.cache — that's the one place XDG_CACHE_HOME is already resolved
    // correctly (falls back to $HOME/.cache only if it's unset), so re-deriving
    // it in the shell script would just be a second, divergent copy of the same
    // fallback logic.
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
            // Pause a playing video wallpaper, remembering whether it was paused
            // already so ending game mode does not start one the user had stopped.
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

        // Plain state, not a binding. It used to read back from
        // Kwin.options["animations:enabled"], which off Hyprland evaluates
        // undefined === 0 — false — so game mode could never stay switched on
        // there. onConfigReloaded below re-applies the options on Hyprland, so
        // nothing needed the binding anyway.
        property bool enabled: false

        reloadableId: "gameMode"
    }

    // If `gamemode-state` exists, recover by **restoring**, not re-enabling.
    // KDE: call `applyKwin(false)` to restore settings and remove the stale file.
    // Don’t set `props.enabled = true`; it would re-enter game mode.
    // Hyprland: no recovery needed; just remove the stale file.

    FileView {
        path: `${Paths.cache}/gamemode-state`
        printErrors: false
        onLoaded: {
            if (props.enabled)
                return; // already active, nothing to recover
            if (root.onHyprland) {
                // Hyprland resets compositor state on shell exit; the file is
                // leftover bookkeeping. Remove it so the next session starts clean.
                Quickshell.execDetached(["rm", "-f", `${Paths.cache}/gamemode-state`]);
            } else {
                // KDE: restore blur/animations from the saved state and delete
                // the stale file. Do not re-enable game mode.
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
