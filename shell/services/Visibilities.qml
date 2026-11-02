pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

Singleton {
    id: root

    property var screens: new Map()
    property var bars: new Map()
    property var docks: new Map()
    property var exclusions: new Map()
    property string initialSidebarTab: ""
    property string lastSidebarTab: "notifications"
    property int openDialogs: 0
    readonly property bool contextPopoutOpen: {
        for (const bar of bars.values())
            if (bar?.popouts?.isContextPopout)
                return true;
        return false;
    }
    readonly property bool sidebarPinned: GlobalConfig.sidebar.pinned
    // Live width while the pinned sidebar's edge is dragged; otherwise follows
    // sidebar.width, where 0 means the default width.
    property int sidebarWidth
    property bool sidebarResizing: false
    property string preOverviewActiveWindowAddress: ""
    /// The names of the application the overview is limited to, or empty for every
    /// window. Set by the dock's "Show all windows" action, cleared when it closes.
    property var overviewAppFilter: []
    property string dragAddress: ""
    property string dragOriginScreen: ""
    property real dragX: 0
    property real dragY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    property string streamClaim: ""
    // The launcher is one panel across outputs, so the screen that opened it owns
    // it. `launcherMode` is the mode it is in: "" for the app grid. The service
    // seeds both when the launcher opens; the launcher keeps the mode in sync with
    // its search field.
    property DrawerVisibilities launcherScreen: null
    property string launcherMode: ""
    readonly property bool launcherOpen: launcherScreen !== null

    signal cycleOverview(bool backwards)
    signal exclusionBoundsChanged(ShellScreen screen)
    signal launcherOpened(string mode)

    function sidebarWidthFor(defaultWidth: real): real {
        return sidebarPinned && sidebarWidth > 0 ? sidebarWidth : defaultWidth;
    }

    function setSidebarWidth(width: int): void {
        // Also set the live width: the binding is off mid-drag, and a
        // double-click's second press starts one.
        sidebarWidth = Math.max(0, width);
        GlobalConfig.sidebar.width = sidebarWidth;
    }

    function sidebarOpenTab(): string {
        return GlobalConfig.sidebar.defaultTab === "last" ? lastSidebarTab : GlobalConfig.sidebar.defaultTab;
    }

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(Kwin.monitorFor(screen), visibilities);
        screens = new Map(screens);
        visibilities.launcherChanged.connect(() => setLauncherOwner(visibilities, visibilities.launcher));
        // PersistentProperties can restore the launcher as open, before the change
        // handler above is connected.
        if (visibilities.launcher)
            setLauncherOwner(visibilities, true);
        visibilities.overviewChanged.connect(() => {
            if (visibilities.overview)
                Kwin.clearHighlight();
        });
        visibilities.sessionChanged.connect(() => {
            if (visibilities.session)
                Kwin.clearHighlight();
        });
    }

    function unload(visibilities: DrawerVisibilities): void {
        for (const monitor of screens.keys()) {
            if (screens.get(monitor) !== visibilities)
                continue;
            screens.delete(monitor);
            screens = new Map(screens);
            break;
        }
        // The screen is going away: skip the highlight reset, which needs Kwin to
        // still be up when the shell is shutting down with it.
        if (launcherScreen === visibilities)
            clearLauncherOwner();
    }

    function registerBar(screen: ShellScreen, barWrapper: var): void {
        bars.set(screen.name, barWrapper);
        bars = new Map(bars);
    }
    function registerDock(screen: ShellScreen, dock: var): void {
        docks.set(screen.name, dock);
        docks = new Map(docks);
    }
    function unregisterDock(screen: ShellScreen): void {
        docks.delete(screen.name);
        docks = new Map(docks);
    }
    function registerExclusions(screen: ShellScreen, exclusionObj: var): void {
        exclusions.set(screen.name, exclusionObj);
        exclusions = new Map(exclusions);
        exclusionBoundsChanged(screen);
    }
    function exclusionsFor(screen: ShellScreen): var {
        return exclusions.get(screen?.name) ?? null;
    }
    function notifyExclusionBoundsChanged(screen: ShellScreen): void {
        exclusionBoundsChanged(screen);
    }
    function getForActive(): DrawerVisibilities {
        const monitor = Kwin.monitors.find(m => m.name === Kwin.cursorOutputName()) || Kwin.focusedMonitor;
        return screens.get(monitor) || screens.values().next().value;
    }
    function modeForText(text: string): string {
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (!text.startsWith(prefix))
            return "";
        const rest = text.slice(prefix.length);
        const space = rest.indexOf(" ");
        return space < 0 ? "" : rest.slice(0, space);
    }
    function openLauncher(mode: string): void {
        const v = launcherScreen ?? getForActive();
        if (!v)
            return;
        // The mode has to be in place first: the launcher applies it to its search
        // field when it opens.
        launcherMode = mode;
        v.launcher = true;
        launcherOpened(mode);
    }
    function closeLauncher(): void {
        if (launcherScreen)
            launcherScreen.launcher = false;
    }
    function toggleLauncher(mode: string): void {
        if (launcherOpen && (mode === "" || launcherMode === mode)) {
            closeLauncher();
            return;
        }
        openLauncher(mode);
    }
    function drawerOpen(drawer: string): bool {
        if (drawer === "launcher")
            return launcherOpen;
        const v = getForActive();
        return v ? v[drawer] === true : false;
    }
    function setDrawer(drawer: string, open: boolean): void {
        if (drawer === "launcher") {
            if (open)
                openLauncher("");
            else
                closeLauncher();
            return;
        }
        if (drawer === "overview") {
            setOverview(open);
            return;
        }
        const v = getForActive();
        if (v)
            v[drawer] = open;
    }
    function setLauncherOwner(visibilities: DrawerVisibilities, open: boolean): void {
        if (!open) {
            if (launcherScreen !== visibilities)
                return;
            Kwin.clearHighlight();
            clearLauncherOwner();
            return;
        }
        for (const other of screens.values()) {
            if (other !== visibilities)
                other.launcher = false;
        }
        launcherScreen = visibilities;
    }
    function clearLauncherOwner(): void {
        launcherMode = "";
        launcherScreen = null;
    }
    function setDrag(address: string, x: real, y: real, w: real, h: real, originScreen: string): void {
        dragAddress = address;
        dragX = x;
        dragY = y;
        dragWidth = w;
        dragHeight = h;
        dragOriginScreen = originScreen;
    }

    function clearDrag(): void {
        dragAddress = "";
        dragOriginScreen = "";
    }

    function setOverview(visible: bool): void {
        if (!visible)
            overviewAppFilter = [];
        for (const visibilities of screens.values())
            visibilities.overview = visible;
    }

    /// Opens the overview limited to one application, the way App Exposé does.
    function showAppWindows(names: var): void {
        overviewAppFilter = (names || []).filter(name => typeof name === "string" && name.length > 0);
        setOverview(true);
    }
    function closeContextPopouts(): void {
        for (const bar of bars.values())
            if (bar?.popouts?.isContextPopout)
                bar.popouts.close();
    }

    Binding on sidebarWidth {
        value: GlobalConfig.sidebar.width
        when: !sidebarResizing
        restoreMode: Binding.RestoreNone
    }

    Timer {
        id: pinRestore

        interval: 1500
        running: GlobalConfig.sidebar.pinned
        onTriggered: {
            const v = getForActive();
            if (v && GlobalConfig.sidebar.pinned)
                v.sidebar = true;
        }
    }

    IpcHandler {
        /// Opens the overview limited to one application, for keybinds and scripts:
        /// the names are the desktop entry id or window class, comma separated.
        function showAppWindows(names: string): void {
            root.showAppWindows(names.split(","));
        }

        target: "overview"
    }
}
