pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Services
import qs.utils

Singleton {
    id: root

    property var paths: ({})

    property var tried: ({})

    property var _awaiting: ({})

    function keyFor(appClass: string, pid: int): string {
        return pid > 0 ? String(pid) : (appClass || "");
    }

    function request(appClass: string, title: string, pid: int, address: string): void {
        const key = root.keyFor(appClass, pid ?? 0);
        if (!key)
            return;

        const asked = root.tried[key];
        // A key that has already resolved belongs to whichever window won it, and keyFor
        // says the class is only a fallback, so a second window sharing the key must not
        // overwrite that answer. Otherwise only the same window instance is skipped.
        if (asked !== undefined && (root.paths[key] || asked === address))
            return;

        const t = root.tried;
        t[key] = address;
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

    function finishWait(uuid: string): void {
        const key = root._awaiting[uuid];
        if (!uuid || !key)
            return;

        const a = Object.assign({}, root._awaiting);
        delete a[String(uuid)];
        root._awaiting = a;
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

    function sourceFor(entry: var, appClass: string, iconName: string, pid: int): string {
        if (entry && entry.icon)
            return Quickshell.iconPath(entry.icon, "application-x-executable");
        const wp = root.paths[root.keyFor(appClass, pid ?? 0)];
        if (wp)
            return "file://" + wp;
        return Quickshell.iconPath(iconName || "application-x-executable", "application-x-executable");
    }

    function sourceForClient(client: var): string {
        if (!client)
            return "";
        const wp = root.paths[root.keyFor(client.class ?? "", client.pid ?? 0)];
        if (wp)
            return "file://" + wp;
        return client.iconName ? Icons.getAppIcon(client.iconName, "application-x-executable")
                               : (client.class ? Icons.getAppIcon(client.class, "application-x-executable") : "");
    }

    // extract() returns the path directly; the signal carries the same result
    // for any caller that did not go through request().
    Connections {
        function onExtracted(key: string, path: string): void {
            root.register(key, path);
        }

        target: WindowIcon
    }

    Connections {
        function onResolved(uuid: string, path: string): void {
            const key = root._awaiting[uuid];
            root.finishWait(uuid);
            if (key)
                root.register(key, path);
        }

        function onFailed(uuid: string): void {
            root.finishWait(uuid);
        }

        target: PlasmaWindowIcon
    }
}
