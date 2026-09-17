pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Services

// Icons pulled straight out of a window's own _NET_WM_ICON (XWayland) for apps
// that have no resolvable desktop entry or themed icon — Minecraft, most Steam
// games, launcher-spawned windows and so on.
//
// This lives in a singleton rather than on the Dock because the Dock is
// instantiated more than once (one per bar/screen) and the popouts are built
// separately again: a per-Dock map meant whichever instance synced last won,
// and an instance that never ran the extractor would clobber the populated map
// with an empty one. A singleton gives every Dock tile and every hover popup
// the same map and the same "already tried" bookkeeping.
Singleton {
    id: root

    // key -> extracted png path
    property var paths: ({})

    // key -> extraction already attempted (don't re-spawn the helper)
    property var tried: ({})

    // uuid -> the key its icon should be registered under, for the compositor
    // path below, which answers asynchronously and only knows the window id.
    property var _awaiting: ({})

    // Icons are tracked per window, not per class. Steam reports every Proton
    // title it cannot map to an appid as "steam_app_default", so a class-keyed
    // map served whichever of those games happened to be extracted first to all
    // the others. The pid is unique per running window and is what the plugin
    // matches on; the class is only a fallback for windows that have no pid.
    function keyFor(appClass: string, pid: int): string {
        return pid > 0 ? String(pid) : (appClass || "");
    }

    // Ask for the icon, at most once per window.
    //
    // Two sources, in order. First a direct XGetWindowProperty read of
    // _NET_WM_ICON — no helper process, and nothing to have installed — which
    // covers XWayland clients. A native Wayland window has no X window to read,
    // so fall back to asking KWin over plasma-window-management: it resolves
    // the icon from the app id, from xdg_toplevel_icon_v1, or from whatever the
    // client set, and hands it to taskbars. That second path is the only way to
    // draw a Wayland game, which reports its own exe name as the app id and so
    // matches no desktop entry either.
    function request(appClass: string, title: string, pid: int, address: string): void {
        const key = root.keyFor(appClass, pid ?? 0);
        if (!key || root.tried[key])
            return;

        const t = root.tried;
        t[key] = true;
        root.tried = t;

        const path = WindowIcon.extract(appClass || "", title || "", pid ?? 0);
        if (path) {
            root.register(key, path);
            return;
        }

        if (address) {
            const a = root._awaiting;
            a[String(address)] = key;
            root._awaiting = a;
            PlasmaWindowIcon.request(String(address));
        }
    }

    // Record a freshly extracted icon. Reassigning a copy is what notifies the
    // bindings that read paths[...] — mutating in place would not.
    function register(key: string, path: string): void {
        if (!path || path === "" || root.paths[key] === path)
            return;
        const m = root.paths;
        m[key] = path;
        root.paths = Object.assign({}, m);
    }

    // Resolve an icon for a dock entry, in the order the taskbar tile and the
    // hover popup must agree on: desktop entry icon, then extracted window
    // icon, then the window class as a themed-icon name.
    function sourceFor(entry: var, appClass: string, iconName: string, pid: int): string {
        if (entry && entry.icon)
            return Quickshell.iconPath(entry.icon, "application-x-executable");
        const wp = root.paths[root.keyFor(appClass, pid ?? 0)];
        if (wp)
            return "file://" + wp;
        return Quickshell.iconPath(iconName || "application-x-executable", "application-x-executable");
    }

    // extract() returns the path directly; the signal carries the same result
    // for any caller that did not go through request().
    Connections {
        target: WindowIcon

        function onExtracted(key: string, path: string): void {
            root.register(key, path);
        }
    }

    Connections {
        target: PlasmaWindowIcon

        // The uuid comes back normalised, which is also how it was stored.
        function onResolved(uuid: string, path: string): void {
            const key = root._awaiting[uuid];
            if (key)
                root.register(key, path);
        }
    }
}
