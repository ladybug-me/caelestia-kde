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
    // A window card being dragged, shared so every screen's overview knows about
    // it.
    //
    // Each overview is its own window and can only draw on its own screen, so a
    // card dragged towards the next monitor simply vanishes at the edge -- the
    // drag is still running and still lands correctly, but there is nothing to
    // see, and it reads as having dropped the window into nowhere. Publishing
    // the position here lets the screen the pointer has reached draw what is
    // arriving.
    property string dragAddress: ""
    property string dragOriginScreen: ""
    property real dragX: 0
    property real dragY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    /// Address of a window whose screencast is claimed by something other than
    /// its card in the grid -- the preview shown on the screen a drag has been
    /// carried to, or an icon pulled up out of the strip.
    ///
    /// KWin serves one node per window and a node feeds one consumer: a second
    /// PipeWireSourceItem bound to the same stream draws black, which is what
    /// both of those did. The card gives it up while the claim stands, and takes
    /// it back afterwards. It is off screen or covered at that point, so there
    /// is nothing to lose.
    property string streamClaim: ""

    // Raised when the overview shortcut is pressed while the overview is
    // already up: the grid moves its selection on instead of the drawer
    // closing under the user.
    signal cycleOverview(bool backwards)

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(Kwin.monitorFor(screen), visibilities);
        screens = new Map(screens); // Force QML property change notification
        visibilities.launcherChanged.connect(() => {
            if (!visibilities.launcher)
                return;
            for (const other of screens.values()) {
                if (other !== visibilities)
                    other.launcher = false;
            }
        });
    }
    function registerBar(screen: ShellScreen, barWrapper: var): void {
        bars.set(screen.name, barWrapper);
        bars = new Map(bars); // Force QML property change notification by changing the Map reference
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
    /**
     * Opens or closes the overview on every screen at once.
     *
     * Unlike the other drawers, the overview is a place you drag things across:
     * a window can be moved to another monitor, or to a desktop that only exists
     * on that monitor, and neither is possible if the destination is still
     * showing the desktop underneath. Opening it on the focused screen alone
     * also reads as broken on a multi-monitor setup -- one screen goes to the
     * overview and the other carries on as if nothing happened.
     */
    function setOverview(visible: bool): void {
        for (const visibilities of screens.values())
            visibilities.overview = visible;
    }
}
