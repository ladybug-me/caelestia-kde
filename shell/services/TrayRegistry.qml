pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.services
import "trayicons.js" as TrayIcons

// Per-icon tray state, and the one place that decides which icons the bar draws and
// in what order. Settings live in config, keyed by the stable alias trayicons.js
// derives, so they outlive the notifier ids that change between launches.
Singleton {
    id: root

    // The three states an icon can be in; collapsed is the default.
    readonly property var states: [
        { value: "visible", label: qsTr("Always visible"), icon: "push_pin" },
        { value: "collapsed", label: qsTr("Collapse"), icon: "expand_more" },
        { value: "hidden", label: qsTr("Hidden"), icon: "visibility_off" }
    ]

    readonly property string popoutPrefix: "traymenu"

    // Pids of the running notifiers, so an alias can name the app rather than the
    // process that happens to host its icon.
    property var procNames: ({})
    property bool procRefreshPending: false

    // Every icon the tray settings know about, running or not, in bar order. Two
    // notifiers that fold onto one alias (one app, two instances) share a row: the
    // alias is what the settings apply to.
    readonly property var entries: {
        const rows = [];
        const known = new Set();
        for (const row of root.liveRows()) {
            if (known.has(row.key))
                continue;
            known.add(row.key);
            rows.push(row);
        }
        for (const key of root.configuredKeys) {
            if (known.has(key))
                continue;
            known.add(key);
            rows.push({
                key: key,
                id: "",
                title: TrayIcons.labelOf(key),
                icon: root.fallbackIcon(key),
                running: false
            });
        }
        return TrayIcons.ordered(rows, GlobalConfig.bar.tray.order);
    }

    // The icons the bar draws, in bar order. Hidden icons are in neither list, so the
    // bar and the tray popout cannot disagree about which icons exist.
    readonly property var trayItems: {
        const rows = SystemTray.items.values.filter(item => item.status !== Status.Passive && !root.isHidden(item)).map(item => ({
                    key: root.keyOfItem(item),
                    item: item
                }));
        return TrayIcons.ordered(rows, GlobalConfig.bar.tray.order).map(row => row.item);
    }

    readonly property int collapsedCount: root.trayItems.filter(item => root.isCollapsed(item)).length

    readonly property var configuredKeys: {
        const tray = GlobalConfig.bar.tray;
        return [...new Set(tray.order.concat(tray.alwaysVisible, tray.hiddenIcons))];
    }

    function liveRows(): var {
        return SystemTray.items.values.filter(item => item.status !== Status.Passive).map(item => ({
                    key: root.keyOfItem(item),
                    id: item.id,
                    title: root.displayName(item),
                    icon: item.icon,
                    running: true
                }));
    }

    function keyOfItem(item: var): string {
        return TrayIcons.keyOf(item.id, item.icon, root.procNames[TrayIcons.pidOf(item.id)] ?? "");
    }

    function displayName(item: var): string {
        if (item.title && item.title !== item.id && !/^\d+-\d+$/.test(item.title))
            return item.title;
        return TrayIcons.labelOf(root.keyOfItem(item)) || item.id;
    }

    function fallbackIcon(key: string): string {
        return Quickshell.iconPath(TrayIcons.iconNameOf(key), "") || Quickshell.iconPath("application-x-executable", "");
    }

    function stateOf(key: string): string {
        return TrayIcons.stateOf(key, GlobalConfig.bar.tray.hiddenIcons, GlobalConfig.bar.tray.alwaysVisible);
    }

    function metaOf(state: string): var {
        return root.states.find(entry => entry.value === state) ?? root.states[1];
    }

    function stateLabel(state: string): string {
        return root.metaOf(state).label;
    }

    function stateIcon(state: string): string {
        return root.metaOf(state).icon;
    }

    function stateOfItem(item: var): string {
        return root.stateOf(root.keyOfItem(item));
    }

    function isHidden(item: var): bool {
        return root.stateOfItem(item) === "hidden";
    }

    function isCollapsed(item: var): bool {
        return root.stateOfItem(item) === "collapsed";
    }

    function setState(key: string, state: string): void {
        const tray = GlobalConfig.bar.tray;
        const visible = tray.alwaysVisible.filter(entry => entry !== key);
        const hidden = tray.hiddenIcons.filter(entry => entry !== key);
        tray.alwaysVisible = state === "visible" ? [...visible, key] : visible;
        tray.hiddenIcons = state === "hidden" ? [...hidden, key] : hidden;
    }

    function forget(key: string): void {
        const tray = GlobalConfig.bar.tray;
        tray.alwaysVisible = tray.alwaysVisible.filter(entry => entry !== key);
        tray.hiddenIcons = tray.hiddenIcons.filter(entry => entry !== key);
        tray.order = tray.order.filter(entry => entry !== key);
    }

    // Commits the order the settings list shows, so the config holds every key it
    // lists rather than only the ones a drag happened to touch.
    function move(from: int, to: int): void {
        const keys = root.entries.map(entry => entry.key);
        if (from < 0 || from >= keys.length || to < 0 || to >= keys.length || from === to)
            return;
        keys.splice(to, 0, keys.splice(from, 1)[0]);
        GlobalConfig.bar.tray.order = keys;
    }

    function popoutName(key: string): string {
        return `${root.popoutPrefix}${key}`;
    }

    function popoutNameOf(item: var): string {
        return root.popoutName(root.keyOfItem(item));
    }

    function isTrayPopout(name: string): bool {
        return name.startsWith(root.popoutPrefix);
    }

    function refreshProcNames(): void {
        if (proc.running) {
            root.procRefreshPending = true;
            return;
        }
        const pids = [...new Set([...SystemTray.items.values].map(item => TrayIcons.pidOf(item.id)).filter(pid => pid))];
        if (pids.length === 0)
            return;
        proc.command = ["ps", "-o", "pid=,comm=", "-p", pids.join(",")];
        proc.running = true;
    }

    // Settings written before aliases existed hold notifier ids, which only the
    // running icons can map back to an alias, so the rewrite happens as they appear.
    // It is idempotent and leaves anything it cannot map alone.
    function migrateLegacyKeys(): void {
        const aliases = {};
        let found = false;
        for (const item of SystemTray.items.values) {
            const key = root.keyOfItem(item);
            if (key === item.id)
                continue;
            aliases[item.id] = key;
            found = true;
        }
        if (found)
            ConfigMigrations.migrateTrayIcons(aliases);
    }

    Component.onCompleted: {
        root.refreshProcNames();
        root.migrateLegacyKeys();
    }

    onProcNamesChanged: root.migrateLegacyKeys()

    Connections {
        function onValuesChanged(): void {
            root.refreshProcNames();
            root.migrateLegacyKeys();
        }

        target: SystemTray.items
    }

    Process {
        id: proc

        command: []

        stdout: StdioCollector {
            id: procOut
        }

        onExited: {
            const next = Object.assign({}, root.procNames);
            let changed = false;
            for (const line of procOut.text.trim().split("\n")) {
                const fields = line.trim().split(/\s+/);
                const pid = fields.shift() ?? "";
                const comm = fields.join(" ");
                if (!pid || !comm || next[pid] === comm)
                    continue;
                next[pid] = comm;
                changed = true;
            }
            if (changed)
                root.procNames = next;
            if (root.procRefreshPending) {
                root.procRefreshPending = false;
                root.refreshProcNames();
            }
        }
    }
}
