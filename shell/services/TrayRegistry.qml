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
        const known = new Map(root.remembered.map(entry => [entry.id, entry]));
        for (const item of SystemTray.items.values) {
            if (item.status === Status.Passive)
                continue;
            const entry = known.get(item.id);
            known.set(item.id, {
                id: item.id,
                title: item.title || entry?.title || item.id,
                icon: item.icon || entry?.icon || "",
                running: true
            });
        }
        return root.applyOrder([...known.values()].map(entry => ({
                    id: entry.id,
                    title: entry.title || entry.id,
                    icon: entry.icon || "",
                    running: entry.running === true
                })), entry => entry.id);
    }

    // Passive items are hidden by the protocol and by upstream's bar; TrayItem's
    // trayIndex and the popout names in popouts/Content.qml both come from this
    // same filter, so it must match the one there exactly.
    readonly property var trayItems: root.applyOrder(SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id)), i => i.id)

    readonly property var trayIndexById: root.trayItems.reduce((acc, item, i) => {
        acc[item.id] = i;
        return acc;
    }, {})

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

    function stateOf(id: string): string {
        if (GlobalConfig.bar.tray.hiddenIcons.includes(id))
            return "hidden";
        if (GlobalConfig.bar.tray.alwaysVisible.includes(id))
            return "visible";
        return "collapsed";
    }

    function setState(id: string, state: string): void {
        GlobalConfig.bar.tray.alwaysVisible = GlobalConfig.bar.tray.alwaysVisible.filter(entry => entry !== id);
        GlobalConfig.bar.tray.hiddenIcons = GlobalConfig.bar.tray.hiddenIcons.filter(entry => entry !== id);
        if (state === "visible")
            GlobalConfig.bar.tray.alwaysVisible = [...GlobalConfig.bar.tray.alwaysVisible, id];
        else if (state === "hidden")
            GlobalConfig.bar.tray.hiddenIcons = [...GlobalConfig.bar.tray.hiddenIcons, id];
    }

    function forget(id: string): void {
        root.remembered = root.remembered.filter(entry => entry.id !== id);
        root.setState(id, "collapsed");
        saveTimer.restart();
    }

    function prune(list: var): var {
        const now = Date.now();
        return list.filter(entry => root.stateOf(entry.id) !== "collapsed" || now - (entry.lastSeen ?? 0) < root.unseenTtl);
    }

    function record(): void {
        if (!root.loaded)
            return;

        const now = Date.now();
        const known = new Map(root.remembered.map(entry => [entry.id, entry]));
        for (const item of SystemTray.items.values) {
            if (item.status === Status.Passive)
                continue;
            known.set(item.id, {
                id: item.id,
                title: item.title || item.id,
                icon: item.icon || "",
                lastSeen: now
            });
        }

        const next = root.prune([...known.values()]);
        if (JSON.stringify(next) === JSON.stringify(root.remembered))
            return;
        root.remembered = next;
        saveTimer.restart();
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
