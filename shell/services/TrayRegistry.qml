pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    readonly property real unseenTtl: 30 * 24 * 60 * 60 * 1000

    readonly property string path: `${Paths.state}/tray_icons.json`

    property var remembered: []
    property bool loaded: false

    readonly property var entries: {
        const known = new Map(root.remembered.map(entry => [entry.alias ?? entry.id, entry]));
        for (const item of SystemTray.items.values) {
            if (item.status === Status.Passive)
                continue;
            const alias = root.keyOfItem(item);
            const entry = known.get(alias);
            known.set(alias, {
                id: item.id,
                alias: alias,
                title: item.title || entry?.title || item.id,
                icon: item.icon || entry?.icon || "",
                running: true
            });
        }
        return root.applyOrder([...known.values()].map(entry => ({
                    id: entry.id,
                    alias: entry.alias ?? entry.id,
                    title: entry.title || entry.id,
                    icon: entry.icon || "",
                    running: entry.running === true
                })), entry => entry.alias);
    }

    // Passive items are hidden by the protocol and by upstream's bar; TrayItem's
    // trayIndex and the popout names in popouts/Content.qml both come from this
    // same filter, so it must match the one there exactly.
    readonly property var trayItems: root.applyOrder(SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(root.keyOfItem(i))), i => root.keyOfItem(i))

    readonly property var trayIndexById: root.trayItems.reduce((acc, item, i) => {
        acc[root.keyOfItem(item)] = i;
        return acc;
    }, {})

    function keyOfItem(item: var): string {
        return root.keyOfId(item.id, item.title, item.icon);
    }

    function keyOfId(id: string, title: string, icon: string): string {
        for (const entry of root.remembered) {
            if (entry.id === id)
                return entry.alias ?? id;
            if (entry.alias && id !== entry.id && entry.title && title && entry.title === title && entry.icon === icon)
                return entry.alias;
        }
        return id;
    }

    function applyOrder(list: var, key: var): var {
        const order = GlobalConfig.bar.tray.order;
        const pos = new Map();
        order.forEach((id, i) => pos.set(id, i));
        return list.map((entry, i) => ({
                entry,
                i
            })).sort((a, b) => {
            const ra = pos.has(key(a.entry)) ? pos.get(key(a.entry)) : order.length;
            const rb = pos.has(key(b.entry)) ? pos.get(key(b.entry)) : order.length;
            return ra !== rb ? ra - rb : a.i - b.i;
        }).map(e => e.entry);
    }

    function stateOf(key: string): string {
        if (GlobalConfig.bar.tray.hiddenIcons.includes(key))
            return "hidden";
        if (GlobalConfig.bar.tray.alwaysVisible.includes(key))
            return "visible";
        return "collapsed";
    }

    function setState(key: string, state: string): void {
        GlobalConfig.bar.tray.alwaysVisible = GlobalConfig.bar.tray.alwaysVisible.filter(entry => entry !== key);
        GlobalConfig.bar.tray.hiddenIcons = GlobalConfig.bar.tray.hiddenIcons.filter(entry => entry !== key);
        if (state === "visible")
            GlobalConfig.bar.tray.alwaysVisible = [...GlobalConfig.bar.tray.alwaysVisible, key];
        else if (state === "hidden")
            GlobalConfig.bar.tray.hiddenIcons = [...GlobalConfig.bar.tray.hiddenIcons, key];
    }

    function forget(alias: string): void {
        root.remembered = root.remembered.filter(entry => (entry.alias ?? entry.id) !== alias);
        root.setState(alias, "collapsed");
        saveTimer.restart();
    }

    function prune(list: var): var {
        const now = Date.now();
        return list.filter(entry => root.stateOf(entry.alias ?? entry.id) !== "collapsed" || now - (entry.lastSeen ?? 0) < root.unseenTtl);
    }

    function sameEntries(a: var, b: var): bool {
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++) {
            const x = a[i];
            const y = b[i];
            if (x.id !== y.id || (x.alias ?? x.id) !== (y.alias ?? y.id) || x.title !== y.title || x.icon !== y.icon)
                return false;
        }
        return true;
    }

    function record(): void {
        if (!root.loaded)
            return;

        const now = Date.now();
        const known = new Map(root.remembered.map(entry => [entry.alias ?? entry.id, entry]));
        for (const item of SystemTray.items.values) {
            if (item.status === Status.Passive)
                continue;
            const alias = root.keyOfItem(item);
            const existing = known.get(alias);
            known.set(alias, {
                id: item.id,
                alias: alias,
                title: item.title || existing?.title || item.id,
                icon: item.icon || existing?.icon || "",
                lastSeen: now
            });
        }

        const next = root.prune([...known.values()]);
        if (root.sameEntries(next, root.remembered)) {
            for (let i = 0; i < next.length; i++)
                root.remembered[i].lastSeen = next[i].lastSeen;
            saveTimer.restart();
            return;
        }
        root.remembered = next;
        saveTimer.restart();
    }

    function migrateConfig(): void {
        const tray = GlobalConfig.bar.tray;
        const byEntry = new Map();
        for (const entry of root.remembered)
            if (entry.alias)
                byEntry.set(entry.id, entry.alias);
        const rewrite = list => [...new Set(list.map(id => byEntry.get(id) ?? id))];
        tray.alwaysVisible = rewrite(tray.alwaysVisible);
        tray.hiddenIcons = rewrite(tray.hiddenIcons);
        tray.order = rewrite(tray.order);
        let changed = false;
        const next = root.remembered.map(entry => {
            if (entry.alias)
                return entry;
            changed = true;
            return {
                id: entry.id,
                alias: entry.id,
                title: entry.title ?? "",
                icon: entry.icon ?? "",
                lastSeen: entry.lastSeen ?? 0
            };
        });
        if (changed) {
            root.remembered = next;
            saveTimer.restart();
        }
    }

    Component.onCompleted: fileView.reload()

    Connections {
        function onValuesChanged(): void {
            root.record();
        }

        target: SystemTray.items
    }

    FileView {
        id: fileView

        path: root.path
        watchChanges: false
        printErrors: false

        onLoaded: {
            let parsed = [];
            try {
                const data = JSON.parse(fileView.text());
                if (Array.isArray(data))
                    parsed = data;
            } catch (e) {
                console.warn("[TrayRegistry] ignoring an unreadable tray icon file:", e);
            }
            root.remembered = root.prune(parsed);
            root.loaded = true;
            root.migrateConfig();
            root.record();
        }

        onLoadFailed: {
            root.remembered = [];
            root.loaded = true;
            root.record();
        }
    }

    Timer {
        id: saveTimer

        interval: 400
        repeat: false
        onTriggered: fileView.setText(JSON.stringify(root.remembered))
    }
}
