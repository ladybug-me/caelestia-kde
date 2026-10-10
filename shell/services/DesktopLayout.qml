pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

// Persistent state of the desktop icons: where each icon sits, the virtual
// groups and the view preferences. Kept out of the C++ config so that it can
// change at runtime without a plugin rebuild.
Singleton {
    id: root

    readonly property string layoutPath: `${Paths.data}/desktop_layout.json`
    readonly property var iconSizes: [48, 64, 80, 96]

    property bool loaded: false
    // Item key ("f/<file name>" or "g/<group id>") -> { col, row }.
    property var positions: ({})
    // Group id -> { name, members: [file name, ...], size: { w, h } }. A size
    // above 1x1 shows the group as a large folder.
    property var groups: ({})
    // Widget id -> { type, size: { w, h }, config: {} }.
    property var widgets: ({})
    property int iconSize: 64
    property bool autoArrange: false
    // Clip full-colour icons to a rounded square.
    property bool roundIcons: true
    // "" keeps the manual order; otherwise name, type, modified or size.
    property string sortKey: ""

    // Follows KDE's "single click to open files" setting.
    property bool singleClick: false
    // Whether the clipboard holds files, checked when the desktop menu opens.
    property bool clipboardHasFiles: false
    // Screen name -> DesktopIcons controller instance
    property var controllers: ({})

    signal pasteRequested(string screenName, real x, real y)
    signal viewOptionsRequested(string screenName, real x, real y)
    signal addWidgetRequested(string screenName, real x, real y)
    signal arrangeRequested(string screenName, string sortKey)
    signal openIconContextMenu(string screenName, real x, real y, var keys, string inGroup)
    signal openDropMenu(string screenName, real x, real y, var urls, string target, var cell)

    function registerController(screenName: string, controller: var): void {
        const next = Object.assign({}, controllers);
        next[screenName] = controller;
        controllers = next;
    }

    function unregisterController(screenName: string): void {
        const next = Object.assign({}, controllers);
        delete next[screenName];
        controllers = next;
    }

    function controllerFor(screenName: string): var {
        return controllers[screenName] ?? null;
    }

    function fileKey(name: string): string {
        return "f/" + name;
    }

    function groupKey(id: string): string {
        return "g/" + id;
    }

    function widgetKey(id: string): string {
        return "w/" + id;
    }

    function setWidgets(next: var): void {
        widgets = next;
        scheduleSave();
    }

    function setWidgetConfig(id: string, patch: var): void {
        const w = widgets[id];
        if (!w)
            return;
        const next = Object.assign({}, widgets);
        next[id] = Object.assign({}, w, { config: Object.assign({}, w.config, patch) });
        setWidgets(next);
    }

    function setPositions(next: var): void {
        positions = next;
        scheduleSave();
    }

    function setGroups(next: var): void {
        groups = next;
        scheduleSave();
    }

    function setIconSize(size: int): void {
        if (iconSizes.indexOf(size) === -1 || size === iconSize)
            return;
        iconSize = size;
        scheduleSave();
    }

    function stepIconSize(delta: int): void {
        const idx = Math.max(0, iconSizes.indexOf(iconSize));
        setIconSize(iconSizes[Math.max(0, Math.min(iconSizes.length - 1, idx + delta))]);
    }

    function setAutoArrange(on: bool): void {
        if (autoArrange === on)
            return;
        autoArrange = on;
        scheduleSave();
    }

    function setRoundIcons(on: bool): void {
        if (roundIcons === on)
            return;
        roundIcons = on;
        scheduleSave();
    }

    function setSortKey(key: string): void {
        if (sortKey === key)
            return;
        sortKey = key;
        scheduleSave();
    }

    function newGroupId(): string {
        let id;
        do
            id = Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
        while (id in groups || id in widgets);
        return id;
    }

    function refreshClipboard(): void {
        clipboardProc.running = true;
    }

    function scheduleSave(): void {
        if (loaded)
            saveTimer.restart();
    }

    function parseLayout(text: string): void {
        let data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = null;
        }
        const nextPositions = {};
        const nextGroups = {};
        const nextWidgets = {};
        const size = v => v && v.w >= 1 && v.h >= 1 ? { w: v.w | 0, h: v.h | 0 } : { w: 1, h: 1 };
        if (Array.isArray(data)) {
            // Version 1: a bare list of { name, col, row }.
            for (const it of data)
                if (it && typeof it.name === "string")
                    nextPositions[fileKey(it.name)] = { col: it.col | 0, row: it.row | 0 };
        } else if (data && typeof data === "object") {
            for (const it of data.items ?? [])
                if (it && typeof it.key === "string")
                    nextPositions[it.key] = { col: it.col | 0, row: it.row | 0 };
            for (const g of data.groups ?? [])
                if (g && typeof g.id === "string" && Array.isArray(g.members))
                    nextGroups[g.id] = { name: String(g.name ?? ""), members: g.members.filter(m => typeof m === "string"), size: size(g.size) };
            for (const w of data.widgets ?? [])
                if (w && typeof w.id === "string" && typeof w.type === "string")
                    nextWidgets[w.id] = { type: w.type, size: size(w.size), config: w.config && typeof w.config === "object" ? w.config : {} };
            const prefs = data.prefs ?? {};
            if (iconSizes.indexOf(prefs.iconSize) !== -1)
                iconSize = prefs.iconSize;
            autoArrange = prefs.autoArrange === true;
            roundIcons = prefs.roundIcons !== false;
            sortKey = typeof prefs.sortKey === "string" ? prefs.sortKey : "";
        }
        positions = nextPositions;
        groups = nextGroups;
        widgets = nextWidgets;
        loaded = true;
    }

    function serialise(): string {
        const items = [];
        for (const key in positions)
            items.push({ key, col: positions[key].col, row: positions[key].row });
        const groupList = [];
        for (const id in groups)
            groupList.push({ id, name: groups[id].name, members: groups[id].members, size: groups[id].size ?? { w: 1, h: 1 } });
        const widgetList = [];
        for (const id in widgets)
            widgetList.push({ id, type: widgets[id].type, size: widgets[id].size, config: widgets[id].config });
        return JSON.stringify({
            version: 2,
            prefs: { iconSize, autoArrange, sortKey, roundIcons },
            items,
            groups: groupList,
            widgets: widgetList
        });
    }

    Process {
        id: clipboardProc

        command: ["wl-paste", "--list-types"]
        stdout: StdioCollector {
            onStreamFinished: root.clipboardHasFiles = text.split("\n").some(t => t.trim() === "text/uri-list")
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.clipboardHasFiles = false;
        }
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: layoutFile.setText(root.serialise())
    }

    FileView {
        id: layoutFile

        path: root.layoutPath
        printErrors: false
        onLoaded: root.parseLayout(text())
        onLoadFailed: root.parseLayout("")
    }

    FileView {
        id: kdeGlobals

        path: `${Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config"}/kdeglobals`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let group = "";
            let single = false;
            for (const raw of text().split("\n")) {
                const line = raw.trim();
                if (line.startsWith("[")) {
                    group = line;
                    continue;
                }
                if (group === "[KDE]" && line.startsWith("SingleClick=")) {
                    single = line.substring(12).trim() === "true";
                    break;
                }
            }
            root.singleClick = single;
        }
    }
}
