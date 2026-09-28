pragma Singleton

import Quickshell
import qs.components
import qs.services

Singleton {
    property var screens: new Map()
    property var bars: new Map()
    property string launcherInitialSearch: ""
    property string initialSidebarTab: "notifications"
    property string preOverviewActiveWindowAddress: ""
    property string dragAddress: ""
    property string dragOriginScreen: ""
    property real dragX: 0
    property real dragY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    property string streamClaim: ""

    signal cycleOverview(bool backwards)

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(Kwin.monitorFor(screen), visibilities);
        screens = new Map(screens);
        visibilities.launcherChanged.connect(() => {
            if (!visibilities.launcher) {
                Kwin.clearHighlight();
                return;
            }
            for (const other of screens.values()) {
                if (other !== visibilities)
                    other.launcher = false;
            }
        });
        visibilities.overviewChanged.connect(() => {
            if (visibilities.overview)
                Kwin.clearHighlight();
        });
        visibilities.sessionChanged.connect(() => {
            if (visibilities.session)
                Kwin.clearHighlight();
        });
    }
    function registerBar(screen: ShellScreen, barWrapper: var): void {
        bars.set(screen.name, barWrapper);
        bars = new Map(bars);
    }
    function getForActive(): DrawerVisibilities {
        const monitor = Kwin.monitors[Kwin.cursorOutputName()] || Kwin.focusedMonitor;
        return screens.get(monitor) || screens.values().next().value;
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
}
