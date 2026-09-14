pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components.misc
import qs.services

Singleton {
    id: root

    readonly property var activeWindow: KWinActiveWindowBridge.activeWindow
    readonly property var windowList: KWinActiveWindowBridge.windowList || []
    readonly property string activeOutputName: KWinActiveWindowBridge.activeOutputName
    readonly property string pendingFocusAddress: KWinActiveWindowBridge.pendingFocusAddress
    readonly property var workspaces: KWinWorkspaceState.workspaces || []
    readonly property int activeWsId: KWinWorkspaceState.activeId
    readonly property var activeByOutput: KWinWorkspaceState.activeByOutput || ({})
    readonly property real swipeOffset: KWinWorkspaceState.swipeOffset
    readonly property var swipeOffsetByOutput: KWinWorkspaceState.swipeOffsetByOutput || ({})
    readonly property bool showingDesktop: KWinWorkspaceState.showingDesktop
    readonly property var toplevels: ({ values: root.windowList })
    readonly property var activeToplevel: root.activeWindow
    readonly property var focusedWorkspace: ({ id: root.activeWsId, name: root.activeWsId.toString() })
    readonly property bool capsLock: CUtils.capsLock
    readonly property bool numLock: CUtils.numLock
    readonly property string defaultKbLayout: ""
    readonly property string kbLayoutFull: KbLayout.activeLabel
    readonly property string kbLayout: KbLayout.activeShortLabel
    readonly property bool usingLua: false
    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices
    property var monitorState: []
    property var _monitorCache: ({})
    property bool hadKeyboard: false
    property string lastSpecialWorkspace: ""
    readonly property var monitors: {
        const screens = [...Quickshell.screens];
        const screenNames = screens.map(s => s.name);
        const cachedNames = Object.keys(root._monitorCache).filter(key => key !== "values");
        const topologyChanged = cachedNames.length !== screenNames.length
            || cachedNames.some(name => !screenNames.includes(name));

        if (topologyChanged) {
            for (const name of cachedNames) {
                if (!screenNames.includes(name))
                    delete root._monitorCache[name];
            }
            for (let i = 0; i < screens.length; i++) {
                if (!root._monitorCache[screens[i].name])
                    root._monitorCache[screens[i].name] = root.createMonitorMock(screens[i].name, i);
            }
        }

        for (let i = 0; i < screens.length; i++) {
            root._monitorCache[screens[i].name].id = i;
            root._monitorCache[screens[i].name].focused = i === 0;
        }

        const cache = root._monitorCache;
        const vals = Object.values(cache).filter(v => typeof v === "object" && v !== null);
        cache.values = vals;
        cache.values.find   = pred => Array.prototype.find.call(vals, pred);
        cache.values.filter = pred => Array.prototype.filter.call(vals, pred);
        cache.values.some   = pred => Array.prototype.some.call(vals, pred);
        cache.values.every  = pred => Array.prototype.every.call(vals, pred);
        return cache;
    }
    readonly property var focusedMonitor: {
        let _ = root.monitors;
        const targetName = root.activeOutputName;

        if (targetName) {
            for (const key in root._monitorCache) {
                if (root._monitorCache[key].name === targetName)
                    return root._monitorCache[key];
            }
        }

        for (const key in root._monitorCache) {
            if (root._monitorCache[key].focused)
                return root._monitorCache[key];
        }

        const keys = Object.keys(root._monitorCache);
        return keys.length > 0 ? root._monitorCache[keys[0]] : null;
    }

    signal configReloaded

    function focusWindow(address: string): void {
        KWinActiveWindowBridge.focusWindow(address);
    }

    function closeWindow(address: string): void {
        KWinActiveWindowBridge.closeWindow(address);
    }

    function minimizeWindow(address: string): void {
        KWinActiveWindowBridge.minimizeWindow(address);
    }

    function maximizeWindow(address: string, horz: bool, vert: bool): void {
        KWinActiveWindowBridge.maximizeWindow(address, horz ?? true, vert ?? true);
    }

    function raiseWindow(address: string): void {
        KWinActiveWindowBridge.raiseWindow(address);
    }

    function setWindowDesktop(address: string, desktopId: int): void {
        KWinActiveWindowBridge.setWindowDesktop(address, desktopId);
    }

    function sendToOutput(address: string, outputName: string): void {
        KWinActiveWindowBridge.sendToOutput(address, outputName);
    }

    function setFullscreen(address: string, fullscreen: bool): void {
        KWinActiveWindowBridge.setFullscreen(address, fullscreen);
    }

    function setMaximized(address: string, maximized: bool): void {
        KWinActiveWindowBridge.setMaximized(address, maximized);
    }

    function highlightWindow(address: string): void {
        KWinActiveWindowBridge.highlightWindow(address);
    }

    function clearHighlight(): void {
        KWinActiveWindowBridge.clearHighlight();
    }

    function windowsForWorkspace(workspace: var, includeAll: bool): var {
        return KWinActiveWindowBridge.windowsForWorkspace(workspace, includeAll ?? true);
    }

    function cursorOutputName(): string {
        return KWinActiveWindowBridge.cursorOutputName();
    }

    function refreshWindows(): void {
        KWinActiveWindowBridge.refreshWindows();
    }

    function setActiveOutputName(outputName: string): void {
        KWinActiveWindowBridge.setActiveOutputName(outputName);
    }

    function switchToWorkspace(wsId: var, screenName: string): void {
        if (screenName)
            KWinWorkspaceState.switchTo(wsId, screenName);
        else
            KWinWorkspaceState.switchTo(wsId);
    }

    function createWorkspace(name: string): void {
        KWinWorkspaceState.createWorkspace(name ?? "");
    }

    function removeWorkspace(id: string): void {
        KWinWorkspaceState.removeWorkspace(id);
    }

    function indexForId(id: string): int {
        return KWinWorkspaceState.indexForId(id);
    }

    function uuidForIndex(index: int): string {
        return KWinWorkspaceState.uuidForIndex(index);
    }

    function setDesktop(index: int): void {
        KWinWorkspaceState.setDesktop(index);
    }

    function nextDesktop(): void {
        KWinWorkspaceState.nextDesktop();
    }

    function previousDesktop(): void {
        KWinWorkspaceState.previousDesktop();
    }

    function createMonitorMock(name: string, index: int): var {
        const m = Qt.createQmlObject(`
            import QtQuick
            QtObject {
                property int id: 0
                property string name: ""
                property bool focused: false
                property real scale: 1.0
                property real x: 0
                property real y: 0
                property var activeWorkspace: ({ id: 1, toplevels: { values: [] } })
                property var specialWorkspace: ({ name: "", toplevels: { values: [] } })
                property var lastIpcObject: null
                Component.onCompleted: lastIpcObject = this
            }
        `, root, "monitorMock");
        m.name = name;
        m.id = index;
        m.focused = index === 0;
        return m;
    }

    function isIgnoredWindow(win: var): bool {
        if (!win)
            return true;
        const cls = String(win["class"] ?? "");
        if (cls === "quickshell" || cls === "plasmashell")
            return true;
        const ignored = GlobalConfig.bar.workspaces.ignoredTags;
        if (!ignored || ignored.length === 0)
            return false;
        const tags = win.lastIpcObject?.tags ?? win.tags;
        const names = cls ? [cls] : [];
        if (tags)
            names.push(...(Array.isArray(tags) ? tags : [tags]));
        return names.some(n => ignored.includes(String(n).replace(/\*$/, "")));
    }

    function hasFullscreen(): bool {
        const wins = root.windowList;
        const activeWs = root.activeWsId;
        for (let i = 0; i < wins.length; i++) {
            if (wins[i].fullscreen === true && !wins[i].minimized) {
                const winWs = wins[i].workspace?.id ?? -1;
                if (activeWs !== -1 && winWs !== -1 && winWs !== activeWs)
                    continue;
                return true;
            }
        }
        return false;
    }

    function hasFullscreenOn(screenName: string): bool {
        if (!screenName)
            return hasFullscreen();
        const wins = root.windowList;
        const activeWs = root.activeWsId;
        for (let i = 0; i < wins.length; i++) {
            if (!wins[i].fullscreen || wins[i].minimized)
                continue;
            if (wins[i].output !== screenName)
                continue;
            const winWs = wins[i].workspace?.id ?? -1;
            if (activeWs !== -1 && winWs !== -1 && winWs !== activeWs)
                continue;
            return true;
        }
        return false;
    }

    function hasWindowOverlapping(screenName: string, x: real, y: real, width: real, height: real, focusedOnly: bool): bool {
        const wins = root.windowList;
        const activeWin = root.activeWindow;
        const activeAddr = activeWin ? String(activeWin.address ?? "") : "";
        const byOutput = root.activeByOutput;
        const screenWsId = (byOutput && byOutput[screenName] !== undefined) ? byOutput[screenName] : root.activeWsId;
        const activeWinWsId = activeWin?.workspace?.id ?? -1;
        const activeOnThisWs = activeWinWsId === -1 || screenWsId === -1 || activeWinWsId === screenWsId;
        const isActiveScreen = screenName && activeWin && activeWin.output === screenName && activeOnThisWs;
        const applyFocusedOnly = focusedOnly && isActiveScreen && activeAddr.length > 0;

        for (let i = 0; i < wins.length; i++) {
            const win = wins[i];
            if (win.minimized === true)
                continue;
            const winWsId = win.workspace?.id ?? -1;
            if (screenWsId !== -1 && winWsId !== -1 && winWsId !== screenWsId)
                continue;
            if (applyFocusedOnly && String(win.address) !== activeAddr)
                continue;
            if (win.x < x + width && win.x + win.width > x && win.y < y + height && win.y + win.height > y)
                return true;
        }
        return false;
    }

    function windowHidesDesktopWidgets(screenName: string, hideOnAll: bool): bool {
        const wins = root.windowList;
        const byOutput = root.activeByOutput;
        const globalActiveWs = root.activeWsId;

        const getActiveWs = outName => (byOutput && byOutput[outName] !== undefined) ? byOutput[outName] : globalActiveWs;

        const isMaximizedOnWs = (win, outName) => {
            if (win.minimized === true || (!win.maximized && !win.fullscreen))
                return false;
            const winWs = win.workspace?.id ?? -1;
            const activeWs = getActiveWs(outName);
            return activeWs === -1 || winWs === -1 || winWs === activeWs;
        };

        if (hideOnAll)
            return wins.some(w => isMaximizedOnWs(w, w.output || screenName));
        return wins.some(w => (screenName === "" || w.output === screenName) && isMaximizedOnWs(w, screenName));
    }

    function dispatch(request: string): void {
        if (request.startsWith("workspace ")) {
            const ws = request.split(" ").slice(1).join(" ");
            if (/^r[+-]\d+$/.test(ws)) {
                if (ws.charAt(1) === "+")
                    root.nextDesktop();
                else
                    root.previousDesktop();
            } else {
                root.switchToWorkspace(ws);
            }
            return;
        }

        if (request.startsWith("focuswindow address:0x")) {
            root.focusWindow(request.slice("focuswindow address:0x".length).trim());
            return;
        }

        if (request.startsWith("closewindow address:0x")) {
            root.closeWindow(request.slice("closewindow address:0x".length).trim());
            return;
        }

        const moveMatch = request.match(/^movetoworkspace\s+(\S+),address:0x/);
        if (moveMatch) {
            const desktopId = parseInt(moveMatch[1], 10);
            const addr = request.slice(moveMatch[0].length).trim();
            if (!isNaN(desktopId))
                root.setWindowDesktop(addr, desktopId);
            return;
        }

        if (request === "dpms off" || request === "dpms on") {
            const method = (request === "dpms on") ? "turnOn" : "turnOff";
            Quickshell.execDetached([
                "qdbus6", "org.kde.Solid.PowerManagement",
                "/org/kde/Solid/PowerManagement/Actions/DPMSControl",
                "org.kde.Solid.PowerManagement.Actions.DPMSControl." + method
            ]);
            return;
        }

        if (request.startsWith("togglespecialworkspace"))
            return;
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = root.workspaces.filter(w => (w.name ?? "").startsWith("special:") && (w.windows ?? 0) > 0);
        if (openSpecials.length === 0)
            return;

        const activeSpecial = root.focusedMonitor?.specialWorkspace?.name ?? "";
        if (!activeSpecial) {
            if (root.lastSpecialWorkspace) {
                const ws = openSpecials.find(w => w.name === root.lastSpecialWorkspace);
                if (ws) {
                    root.dispatch(`workspace ${root.lastSpecialWorkspace}`);
                    return;
                }
            }
            root.dispatch(`workspace ${openSpecials[0].name}`);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = currentIndex === -1 ? 0
            : (direction === "next")
                ? (currentIndex + 1) % openSpecials.length
                : (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        root.dispatch(`workspace ${openSpecials[nextIndex].name}`);
    }

    function monitorNames(): list<string> {
        const names = [];
        for (const key in root.monitors)
            names.push(root.monitors[key].name);
        return names;
    }

    function monitorFor(screen: ShellScreen): var {
        let cached = root._monitorCache[screen.name];
        if (!cached) {
            cached = root.createMonitorMock(screen.name, Object.keys(root._monitorCache).filter(k => k !== "values").length);
            root._monitorCache[screen.name] = cached;
        }
        return cached;
    }

    onCapsLockChanged: {
        if (!GlobalConfig.utilities.toasts.capsLockChanged)
            return;
        Toaster.toast(
            capsLock ? qsTr("Caps lock enabled") : qsTr("Caps lock disabled"),
            capsLock ? qsTr("Caps lock is currently enabled") : qsTr("Caps lock is currently disabled"),
            capsLock ? "keyboard_capslock_badge" : "keyboard_capslock"
        );
    }

    onNumLockChanged: {
        if (!GlobalConfig.utilities.toasts.numLockChanged)
            return;
        Toaster.toast(
            numLock ? qsTr("Num lock enabled") : qsTr("Num lock disabled"),
            numLock ? qsTr("Num lock is currently enabled") : qsTr("Num lock is currently disabled"),
            numLock ? "looks_one" : "timer_1"
        );
    }

    onKbLayoutFullChanged: {
        if (hadKeyboard && GlobalConfig.utilities.toasts.kbLayoutChanged)
            Toaster.toast(qsTr("Keyboard layout changed"), qsTr("Layout changed to: %1").arg(kbLayoutFull), "keyboard");
        hadKeyboard = kbLayoutFull.length > 0;
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.filter(w => (w.name ?? "").startsWith("special:") && (w.windows ?? 0) > 0).map(w => w.name).join("\n");
        }

        function getFocusedMonitor(): string {
            const m = root.focusedMonitor;
            if (!m) return "null";
            return JSON.stringify({ id: m.id, name: m.name, focused: m.focused, activeWorkspace: m.activeWorkspace, specialWorkspace: m.specialWorkspace }, null, 2);
        }

        function listMonitors(): string {
            return root.monitorNames().join(", ");
        }

        target: "kwin"
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.filter(w => (w.name ?? "").startsWith("special:") && (w.windows ?? 0) > 0).map(w => w.name).join("\n");
        }

        function getFocusedMonitor(): string {
            const m = root.focusedMonitor;
            if (!m) return "null";
            return JSON.stringify({ id: m.id, name: m.name, focused: m.focused, activeWorkspace: m.activeWorkspace, specialWorkspace: m.specialWorkspace }, null, 2);
        }

        function listMonitors(): string {
            return root.monitorNames().join(", ");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: qsTr("Reload devices")
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: false
    }
}
