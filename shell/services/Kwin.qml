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
    readonly property string highlightedAddress: KWinActiveWindowBridge.highlightedAddress
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
    // Per-output index (1-based, as reported by the workspace tracker) of the last
    // normal (non special:) desktop each output was on. Special-workspace toggles
    // return the output here instead of guessing.
    property var _lastNormalByOutput: ({})
    // A toggle for a special desktop that does not exist yet: creation is async
    // over DBus, so the switch is parked here and completed from onWorkspacesChanged
    // once KWin reports the new desktop. { name: "special:xyz", output: "DP-1" }
    property var _pendingSpecialSwitch: null
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

    function activeWorkspaceFor(screenName: string): int {
        const perOutput = (screenName && root.activeByOutput) ? root.activeByOutput[screenName] : 0;
        return perOutput > 0 ? perOutput : (root.activeWsId > 0 ? root.activeWsId : 1);
    }

    function activeWorkspaceUuidFor(screenName: string): string {
        const wsId = root.activeWorkspaceFor(screenName);
        return (root.workspaces && wsId > 0 && wsId <= root.workspaces.length)
            ? (root.workspaces[wsId - 1].id ?? "")
            : "";
    }

    function isWindowOnWorkspace(win: var, wsTarget: var, includeAll: bool): bool {
        if (!win)
            return false;
        const incAll = includeAll ?? true;
        const ws = win.workspace;
        let wsId = -1;
        let wsUuid = "";
        if (ws !== undefined && ws !== null) {
            if (typeof ws === "object") {
                wsId = ws.id ?? -1;
                wsUuid = ws.uuid ?? "";
            } else if (typeof ws === "number") {
                wsId = ws;
            } else if (typeof ws === "string") {
                wsUuid = ws;
            }
        }
        if (!wsUuid && win.workspaceUuid)
            wsUuid = win.workspaceUuid;

        if (wsId <= 0 && wsUuid) {
            const resolved = root.indexForId(wsUuid);
            if (resolved > 0)
                wsId = resolved;
        }

        if (wsId <= 0 && !wsUuid)
            return incAll;

        if (typeof wsTarget === "number" && wsTarget > 0)
            return wsId === wsTarget || (wsUuid !== "" && wsUuid === root.uuidForIndex(wsTarget));
        if (typeof wsTarget === "string" && wsTarget.length > 0)
            return wsUuid === wsTarget || (wsId > 0 && wsId === root.indexForId(wsTarget));
        return true;
    }

    function filterWindows(list: var, wsTarget: var, screenName: string, includeAllWorkspaces: bool): var {
        const source = list || root.windowList || [];
        const incAll = includeAllWorkspaces ?? true;
        return source.filter(w => {
            if (wsTarget !== undefined && wsTarget !== null && !root.isWindowOnWorkspace(w, wsTarget, incAll))
                return false;
            if (screenName && Quickshell.screens.length > 1) {
                const out = w.output || w.monitor;
                if (out && out !== screenName)
                    return false;
            }
            return true;
        });
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

    function setShowingDesktop(showing: bool): void {
        KWinWorkspaceState.setShowingDesktop(showing);
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
        const screenWsId = root.activeWorkspaceFor(screenName);
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

        const isMaximizedOnWs = (win, outName) => {
            if (win.minimized === true || (!win.maximized && !win.fullscreen))
                return false;
            const winWs = win.workspace?.id ?? -1;
            const activeWs = root.activeWorkspaceFor(outName);
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

        if (request.startsWith("togglespecialworkspace")) {
            const name = request.slice("togglespecialworkspace".length).trim();
            root.toggleSpecialWorkspace(name);
            return;
        }
    }

    function toggleSpecialWorkspace(name: string, outputName: string): void {
        // Accepts "special:xyz", a bare "xyz" ("" toggles the default "special")
        // or a desktop uuid. KWin has no native special workspaces, so they are
        // ordinary named desktops with a "special:" prefix, created on demand.
        const bare = String(name ?? "").trim();
        const target = bare.startsWith("special:") ? bare : `special:${bare || "special"}`;
        const out = String(outputName ?? "");
        const wss = root.workspaces || [];
        const ws = wss.find(w => w.name === target || w.id === target);

        // Resolve the output's currently active workspace from the tracker's
        // per-output state, falling back to the global active desktop.
        const byOutput = root.activeByOutput || {};
        const activeIdx = out ? byOutput[out] : 0;
        let activeName = "";
        if (activeIdx > 0 && activeIdx <= wss.length)
            activeName = String(wss[activeIdx - 1]?.name ?? "");
        else
            activeName = String(wss[root.activeWsId - 1]?.name ?? "");

        if (activeName === target) {
            // Toggling the active one off: return this output to its last normal
            // desktop, or the first normal desktop when nothing is recorded.
            const last = root._lastNormalByOutput[out];
            const fallback = wss.find(w => !String(w.name ?? "").startsWith("special:"));
            const dest = (last > 0 && last <= wss.length) ? String(wss[last - 1].id)
                : (fallback ? String(fallback.id) : "");
            root._pendingSpecialSwitch = null;
            if (dest)
                root.switchToWorkspace(dest, out);
            return;
        }

        if (ws) {
            root.lastSpecialWorkspace = target;
            root.switchToWorkspace(String(ws.id), out);
            return;
        }

        // Missing: create it asynchronously and park the switch until KWin
        // reports the new desktop.
        root._pendingSpecialSwitch = { name: target, output: out };
        root.createWorkspace(target);
    }

    function trackLastNormalDesktops(): void {
        // Remember, per output, the desktop it was last on whenever that desktop
        // is a normal one. While an output sits on a special: desktop its entry
        // is left untouched, so toggling off can always return to it.
        const byOutput = root.activeByOutput || {};
        const wss = root.workspaces || [];
        for (const out in byOutput) {
            const idx = byOutput[out];
            if (!(idx > 0) || idx > wss.length)
                continue;
            if (String(wss[idx - 1]?.name ?? "").startsWith("special:"))
                continue;
            if (root._lastNormalByOutput[out] !== idx)
                root._lastNormalByOutput[out] = idx;
        }
    }

    function syncMonitorMocks(): void {
        // Feed the real per-output special-workspace state into the monitor
        // mocks so the active pill, the pill window counts and the
        // wheel-over-workspaces toggle read actual state instead of the
        // never-updated defaults.
        const byOutput = root.activeByOutput || {};
        const wss = root.workspaces || [];
        const globalName = String(wss[root.activeWsId - 1]?.name ?? "");
        for (const key in root._monitorCache) {
            if (key === "values")
                continue;
            const m = root._monitorCache[key];
            if (!m || typeof m !== "object")
                continue;
            let specialName = "";
            const idx = byOutput[m.name];
            if (idx > 0 && idx <= wss.length)
                specialName = String(wss[idx - 1]?.name ?? "");
            else if (globalName.startsWith("special:") && (m.focused || m.name === root.activeOutputName))
                specialName = globalName;
            if (!specialName.startsWith("special:"))
                specialName = "";
            if (m.specialWorkspace?.name !== specialName)
                m.specialWorkspace = { name: specialName, toplevels: { values: [] } };
        }
    }

    function completePendingSpecialSwitch(): void {
        const pending = root._pendingSpecialSwitch;
        if (!pending)
            return;
        root._pendingSpecialSwitch = null;
        const ws = (root.workspaces || []).find(w => w.name === pending.name || w.id === pending.name);
        if (ws) {
            root.lastSpecialWorkspace = pending.name;
            root.switchToWorkspace(String(ws.id), String(pending.output ?? ""));
        }
    }

    function cycleSpecialWorkspace(direction: string): void {
        // Workspace maps carry { id, name, index, active } — there is no windows
        // key, so cycle over every special: desktop that exists.
        const openSpecials = root.workspaces.filter(w => String(w.name ?? "").startsWith("special:"));
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
            if (key !== "values")
                names.push(root.monitors[key].name);
        return names;
    }

    function monitorFor(screen: ShellScreen): var {
        let cached = root._monitorCache[screen.name];
        if (!cached) {
            cached = root.createMonitorMock(screen.name, Object.keys(root._monitorCache).filter(k => k !== "values").length);
            root._monitorCache[screen.name] = cached;
            root.syncMonitorMocks();
        }
        return cached;
    }

    function refreshDevices(): void {
        extras.refreshDevices();
    }

    function listSpecialWorkspaces(): string {
        return root.workspaces.filter(w => String(w.name ?? "").startsWith("special:")).map(w => w.name).join("\n");
    }

    function getFocusedMonitor(): string {
        const m = root.focusedMonitor;
        if (!m)
            return "null";
        return JSON.stringify({ id: m.id, name: m.name, focused: m.focused, activeWorkspace: m.activeWorkspace, specialWorkspace: m.specialWorkspace }, null, 2);
    }

    function listMonitors(): string {
        return root.monitorNames().join(", ");
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
    onWorkspacesChanged: {
        root.refreshWindows();
        root.trackLastNormalDesktops();
        root.syncMonitorMocks();
        root.completePendingSpecialSwitch();
    }

    onActiveByOutputChanged: {
        root.trackLastNormalDesktops();
        root.syncMonitorMocks();
    }

    Component.onCompleted: {
        root.trackLastNormalDesktops();
        root.syncMonitorMocks();
    }

    IpcHandler {
        function refreshDevices(): void {
            root.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.listSpecialWorkspaces();
        }

        function getFocusedMonitor(): string {
            return root.getFocusedMonitor();
        }

        function listMonitors(): string {
            return root.listMonitors();
        }

        target: "kwin"
    }

    IpcHandler {
        function refreshDevices(): void {
            root.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.listSpecialWorkspaces();
        }

        function getFocusedMonitor(): string {
            return root.getFocusedMonitor();
        }

        function listMonitors(): string {
            return root.listMonitors();
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
