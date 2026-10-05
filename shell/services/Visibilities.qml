pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Singleton {
    property var screens: new Map()
    property var bars: new Map()
    property var docks: new Map()
    property string launcherInitialSearch: ""
    property string initialSidebarTab: ""
    property string lastSidebarTab: "notifications"
    property int openDialogs: 0
    readonly property bool sidebarPinned: GlobalConfig.sidebar.pinned
    // Live width while the pinned sidebar's edge is dragged; otherwise follows
    // sidebar.width, where 0 means the default width.
    property int sidebarWidth
    property bool sidebarResizing: false
    property string preOverviewActiveWindowAddress: ""
    property string dragAddress: ""
    property string dragOriginScreen: ""
    property real dragX: 0
    property real dragY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    property string streamClaim: ""
    property bool launcherOpenAnywhere: false
    property string launcherMode: ""
    property DrawerVisibilities launcherInitialSearchTarget: null

    signal cycleOverview(bool backwards)

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
        visibilities.launcherChanged.connect(() => {
            if (!visibilities.launcher) {
                Kwin.clearHighlight();
                _syncLauncherState();
                return;
            }
            for (const other of screens.values()) {
                if (other !== visibilities)
                    other.launcher = false;
            }
            _syncLauncherState();
        });
        visibilities.overviewChanged.connect(() => {
            if (visibilities.overview)
                Kwin.clearHighlight();
        });
        visibilities.sessionChanged.connect(() => {
            if (visibilities.session)
                Kwin.clearHighlight();
        });
        _syncLauncherState();
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
    function getForActive(): DrawerVisibilities {
        const monitor = Kwin.monitors[Kwin.cursorOutputName()] || Kwin.focusedMonitor;
        return screens.get(monitor) || screens.values().next().value;
    }
    function launcherOpenVisibilities(): DrawerVisibilities {
        for (const v of screens.values())
            if (v.launcher)
                return v;
        return null;
    }
    function launcherTarget(): DrawerVisibilities {
        return launcherOpenVisibilities() ?? getForActive();
    }
    function openLauncher(mode: string): void {
        const v = launcherTarget();
        if (!v)
            return;
        if (mode) {
            launcherInitialSearchTarget = v;
            launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}${mode} `;
        } else {
            launcherInitialSearchTarget = null;
            launcherInitialSearch = "";
        }
        launcherMode = mode;
        v.launcher = true;
    }
    function closeLauncher(): void {
        const v = launcherOpenVisibilities();
        if (v)
            v.launcher = false;
        launcherMode = "";
    }
    function toggleLauncher(mode: string): void {
        const open = launcherOpenVisibilities();
        if (open && launcherMode === mode) {
            open.launcher = false;
            launcherMode = "";
            return;
        }
        openLauncher(mode);
    }
    function modeForText(text: string): string {
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (!text.startsWith(prefix))
            return "";
        const rest = text.slice(prefix.length);
        const space = rest.indexOf(" ");
        return space < 0 ? "" : rest.slice(0, space);
    }
    function _syncLauncherState(): void {
        let any = false;
        for (const v of screens.values()) {
            if (v.launcher) {
                any = true;
                break;
            }
        }
        launcherOpenAnywhere = any;
        if (!any)
            launcherMode = "";
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
        for (const visibilities of screens.values())
            visibilities.overview = visible;
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
}
