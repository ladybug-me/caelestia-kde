import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components.misc
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.launcher.services

Scope {
    id: root

    property bool launcherInterrupted
    property string lastAction: ""

    // Whether a fullscreen window covers the screen the drawers would open on
    // (Visibilities tracks them per active screen). Kwin.hasFullscreenOn() is a
    // plain function call, so the Kwin properties it reads are referenced up
    // front to re-run the binding when the window list, the active workspace or
    // the active screen changes - the same idiom as ContentWindow.actualFullscreen.
    readonly property bool hasFullscreen: (Kwin.activeWsId, Kwin.windowList, Kwin.hasFullscreenOn(Kwin.activeOutputName))

    Component.onCompleted: {
        // Force KeybindsModel to instantiate and load shortcuts from disk
        let _ = KeybindsModel;
    }
    // qmllint disable unresolved-type

    CustomShortcut {
        // qmllint enable unresolved-type
        name: "nexus"
        description: qsTr("Open nexus")
        onPressed: WindowFactory.create()
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "showall"
        description: qsTr("Toggle launcher, dashboard and osd")
        onPressed: {
            const v = Visibilities.getForActive();
            v.launcher = v.dashboard = v.osd = v.utilities = !(v.launcher || v.dashboard || v.osd || v.utilities);
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "dashboard"
        description: qsTr("Toggle dashboard")
        onPressed: {
            const visibilities = Visibilities.getForActive();
            visibilities.dashboard = !visibilities.dashboard;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "overview"
        description: qsTr("Toggle overview")
        onPressed: {
            const visibilities = Visibilities.getForActive();
            if (visibilities.overview) {
                Visibilities.setOverview(false);
            } else {
                if (Kwin.activeWindow && Kwin.activeWindow.address) {
                    Visibilities.preOverviewActiveWindowAddress = Kwin.activeWindow.address;
                } else {
                    Visibilities.preOverviewActiveWindowAddress = "";
                }
                Visibilities.setOverview(true);
            }
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshot"
        description: qsTr("Toggle screenshot overlay")
        onPressed: {
            regionSelector.screenshot();
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "googleLens"
        description: qsTr("Toggle Google Lens search")
        onPressed: {
            regionSelector.search();
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "ocr"
        description: qsTr("Recognize text on screen")
        onPressed: {
            regionSelector.ocr();
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenRecording"
        description: qsTr("Toggle screen recording")
        onPressed: {
            if (Recorder.running) {
                if (Recorder.paused) {
                    Recorder.togglePause();
                } else {
                    Recorder.stop();
                }
            } else {
                Recorder.start();
            }
        }
    }
    // qmllint disable unresolved-type
    // Using Caelestia lockscreen greeter
    // CustomShortcut {
    //     // qmllint enable unresolved-type
    //     name: "lock"
    //     key: "Meta+L"
    //     description: "Lock the current session"
    //     onPressed: {
    //         if (root.hasFullscreen)
    //             return;
    //         Quickshell.execDetached(["caelestia", "shell", "lock", "lock"]);
    //     }
    // }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "session"

        description: qsTr("Toggle session menu")
        onPressed: {
            const visibilities = Visibilities.getForActive();
            visibilities.session = !visibilities.session;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcher"
        description: qsTr("Toggle launcher")
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted) {
                root.lastAction = "launcher";
                const visibilities = Visibilities.getForActive();
                visibilities.launcher = !visibilities.launcher;
            }
            root.launcherInterrupted = false;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcherInterrupt"
        description: qsTr("Interrupt launcher keybind")
        onPressed: root.launcherInterrupted = true
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "sidebar"
        description: qsTr("Toggle sidebar")
        onPressed: {
            const visibilities = Visibilities.getForActive();
            Visibilities.initialSidebarTab = "notifications";
            visibilities.sidebar = !visibilities.sidebar;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "aiAssistant"
        description: qsTr("Toggle AI Assistant")
        onPressed: {
            const visibilities = Visibilities.getForActive();
            Visibilities.initialSidebarTab = "ai";
            visibilities.sidebar = true;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "utilities"
        description: qsTr("Toggle utilities")
        onPressed: {
            const visibilities = Visibilities.getForActive();
            visibilities.utilities = !visibilities.utilities;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "emoji"
        description: qsTr("Open emoji picker")
        onPressed: {
            Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}emoji `;
            const visibilities = Visibilities.getForActive();
            visibilities.launcher = true;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clipboard"
        description: qsTr("Open clipboard history")
        onPressed: {
            Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}clipboard `;
            const visibilities = Visibilities.getForActive();
            visibilities.launcher = true;
        }
    }

    Connections {
        function onModifierReleased(): void {
            const visibilities = Visibilities.getForActive();
            if (visibilities.launcher && root.lastAction === "windows") {
                const switcherKey = (typeof KeybindsModel !== "undefined" && KeybindsModel.getKey("windowSwitcher")) || "Alt+Tab";
                if (!CUtils.isShortcutModifierPressed(switcherKey)) {
                    Windows.focusSelectedWindow();
                    visibilities.launcher = false;
                    root.lastAction = "";
                }
            }
        }

        target: CUtils
    }


    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "windowSwitcher"
        description: qsTr("Open window switcher")
        enabled: Config.tabSwitch.enabled
        onPressed: {
            const visibilities = Visibilities.getForActive();
            // Check if launcher is already open and in windows mode
            if (visibilities.launcher && root.lastAction === "windows") {
                Windows.triggerCycleNext();
            } else {
                root.lastAction = "windows";
                Windows.isSwitching = true;
                Windows.updateItems();
                Windows.selectedIndex = (Windows.items.length > 1) ? 1 : 0;
                Windows.refreshHighlight();
                Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}windows `;
                visibilities.launcher = true;
            }
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "windowSwitcherReverse"
        description: qsTr("Open window switcher (reverse)")
        enabled: Config.tabSwitch.enabled
        onPressed: {
            const visibilities = Visibilities.getForActive();
            if (visibilities.launcher && root.lastAction === "windows") {
                Windows.triggerCyclePrev();
            } else {
                root.lastAction = "windows";
                Windows.isSwitching = true;
                Windows.updateItems();
                Windows.selectedIndex = (Windows.items.length > 1) ? Windows.items.length - 1 : 0;
                Windows.refreshHighlight();
                Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}windows `;
                visibilities.launcher = true;
            }
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "wallpaper"
        description: qsTr("Open wallpaper picker")
        onPressed: {
            Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}wallpaper `;
            const visibilities = Visibilities.getForActive();
            visibilities.launcher = true;
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "keybinds"
        description: qsTr("Open keybinds list")
        onPressed: {
            Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}keybinds `;
            const visibilities = Visibilities.getForActive();
            visibilities.launcher = true;
        }
    }
    CustomShortcut {
        name: "foot"
        description: qsTr("Launch Terminal")
        onPressed: Launch.exec(["foot"])
    }
    CustomShortcut {
        name: "firefox"
        description: qsTr("Launch Browser")
        onPressed: Launch.exec(["firefox"])
    }
    CustomShortcut {
        name: "code"
        description: qsTr("Launch Editor")
        onPressed: Launch.exec(["code"])
    }
    CustomShortcut {
        name: "github-desktop"
        description: qsTr("Launch GitHub Desktop")
        onPressed: Launch.exec(["github-desktop"])
    }
    CustomShortcut {
        name: "nemo"
        description: qsTr("Launch File Manager")
        onPressed: Launch.exec(["nemo"])
    }
    CustomShortcut {
        name: "kcolorpicker"
        description: qsTr("Color Picker")
        onPressed: ColorPicker.pickColor()
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace1"
        description: qsTr("Switch to workspace 1")
        onPressed: Kwin.setDesktop(1)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace2"
        description: qsTr("Switch to workspace 2")
        onPressed: Kwin.setDesktop(2)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace3"
        description: qsTr("Switch to workspace 3")
        onPressed: Kwin.setDesktop(3)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace4"
        description: qsTr("Switch to workspace 4")
        onPressed: Kwin.setDesktop(4)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace5"
        description: qsTr("Switch to workspace 5")
        onPressed: Kwin.setDesktop(5)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace6"
        description: qsTr("Switch to workspace 6")
        onPressed: Kwin.setDesktop(6)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace7"
        description: qsTr("Switch to workspace 7")
        onPressed: Kwin.setDesktop(7)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace8"
        description: qsTr("Switch to workspace 8")
        onPressed: Kwin.setDesktop(8)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace9"
        description: qsTr("Switch to workspace 9")
        onPressed: Kwin.setDesktop(9)
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "workspace10"
        description: qsTr("Switch to workspace 10")
        onPressed: Kwin.setDesktop(10)
    }
    IpcHandler {
        function toggle(drawer: string): void {
            if (list().split("\n").includes(drawer)) {
                if (root.hasFullscreen && ["launcher", "session", "dashboard"].includes(drawer))
                    return;
                const visibilities = Visibilities.getForActive();
                // The overview spans every screen; see Visibilities.setOverview.
                if (drawer === "overview")
                    Visibilities.setOverview(!visibilities.overview);
                else
                    visibilities[drawer] = !visibilities[drawer];
            } else {
                console.warn(lc, `Drawer "${drawer}" does not exist`);
            }
        }
        function toggleTab(drawer: string, tab: string): void {
            if (list().split("\n").includes(drawer)) {
                if (root.hasFullscreen && ["launcher", "session", "dashboard"].includes(drawer))
                    return;
                if (drawer === "sidebar" && tab !== "") {
                    Visibilities.initialSidebarTab = tab;
                    const visibilities = Visibilities.getForActive();
                    visibilities.sidebar = true;
                    return;
                }
                const visibilities = Visibilities.getForActive();
                if (drawer === "overview")
                    Visibilities.setOverview(!visibilities.overview);
                else
                    visibilities[drawer] = !visibilities[drawer];
            } else {
                console.warn(lc, `Drawer "${drawer}" does not exist`);
            }
        }
        function list(): string {
            const visibilities = Visibilities.getForActive();
            return Object.keys(visibilities).filter(k => typeof visibilities[k] === "boolean").join("\n");
        }

        target: "drawers"
    }
    IpcHandler {
        function open(): void {
            WindowFactory.create();
        }
        function openPage(pageIdx: string, subPageIdx: string): void {
            const hasSubPage = subPageIdx !== "-1" && subPageIdx !== "";
            WindowFactory.create(null, {
                initialPageIdx: parseInt(pageIdx),
                initialSubPageIdx: hasSubPage ? parseInt(subPageIdx) : -1
            });
        }

        target: "nexus"
    }
    IpcHandler {
        function info(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Info);
        }
        function success(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Success);
        }
        function warn(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Warning);
        }
        function error(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Error);
        }

        target: "toaster"
    }
    IpcHandler {
        function action(name: string): void {
            root.lastAction = name;
            Visibilities.launcherInitialSearch =
            `${GlobalConfig.launcher.actionPrefix}${name} `;

            const visibilities = Visibilities.getForActive();
            visibilities.launcher = true;
        }
        target: "launcher"
    }
    // --- Window Tiling Shortcuts ---
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFocusUp"
        description: qsTr("Focus the window above")
        key: Config.general.krohnkiteEnabled ? "Meta+Up" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFocusUp"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFocusDown"
        description: qsTr("Focus the window below")
        key: Config.general.krohnkiteEnabled ? "Meta+Down" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFocusDown"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFocusLeft"
        description: qsTr("Focus the window to the left")
        key: Config.general.krohnkiteEnabled ? "Meta+Left" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFocusLeft"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFocusRight"
        description: qsTr("Focus the window to the right")
        key: Config.general.krohnkiteEnabled ? "Meta+Right" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFocusRight"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteShiftUp"
        description: qsTr("Move window up")
        key: Config.general.krohnkiteEnabled ? "Meta+Shift+Up" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteShiftUp"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteShiftDown"
        description: qsTr("Move window down")
        key: Config.general.krohnkiteEnabled ? "Meta+Shift+Down" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteShiftDown"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteShiftLeft"
        description: qsTr("Move window left")
        key: Config.general.krohnkiteEnabled ? "Meta+Shift+Left" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteShiftLeft"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteShiftRight"
        description: qsTr("Move window right")
        key: Config.general.krohnkiteEnabled ? "Meta+Shift+Right" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteShiftRight"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteCloseWindow"
        description: qsTr("Close current window")
        key: Config.general.krohnkiteEnabled ? "Meta+Q" : ""
        onPressed: {
            if (Config.general.krohnkiteEnabled)
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "Window Close"])
        }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFocusNext"
        description: qsTr("Focus next window")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFocusNext"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFocusPrev"
        description: qsTr("Focus previous window")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFocusPrev"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteSetMaster"
        description: qsTr("Set active window as Master")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteSetMaster"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteNextLayout"
        description: qsTr("Switch to next layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteNextLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkitePreviousLayout"
        description: qsTr("Switch to previous layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkitePreviousLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteBTreeLayout"
        description: qsTr("Switch to BTree layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteBTreeLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteMonocleLayout"
        description: qsTr("Switch to Monocle layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteMonocleLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFloatingLayout"
        description: qsTr("Switch to Floating layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFloatingLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteQuarterLayout"
        description: qsTr("Switch to Quarter layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteQuarterLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteSpreadLayout"
        description: qsTr("Switch to Spread layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteSpreadLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteStackedLayout"
        description: qsTr("Switch to Stacked layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteStackedLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteStairLayout"
        description: qsTr("Switch to Stair layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteStairLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteColumnsLayout"
        description: qsTr("Switch to Columns layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteColumnsLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteTreeColumnLayout"
        description: qsTr("Switch to Three Column layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteThreeColumnLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteSpiralLayout"
        description: qsTr("Switch to Spiral layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteSpiralLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteTileLayout"
        description: qsTr("Switch to Tile layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteTileLayout"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteGrowHeight"
        description: qsTr("Increase window height")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteGrowHeight"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteShrinkHeight"
        description: qsTr("Decrease window height")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteShrinkHeight"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteGrowWidth"
        description: qsTr("Increase window width")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkitegrowWidth"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteShrinkWidth"
        description: qsTr("Decrease window width")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteShrinkWidth"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteIncreaseMaster"
        description: qsTr("Increase master area size")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteIncrease"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteDecreaseMaster"
        description: qsTr("Decrease master area size")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteDecrease"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteToggleFloat"
        description: qsTr("Toggle floating state")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteToggleFloat"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteFloatAll"
        description: qsTr("Toggle floating state for all")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteFloatAll"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteRotate"
        description: qsTr("Rotate the window layout")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteRotate"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteRotatePart"
        description: qsTr("Rotate windows within a part")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkiteRotatePart"]) }
    }
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "krohnkiteToggleDock"
        description: qsTr("Toggle dock support")
        onPressed: { if (Config.general.krohnkiteEnabled) Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "KrohnkitetoggleDock"]) }
    }
    LoggingCategory {
        id: lc

        name: "caelestia.qml.shortcuts"
        defaultLogLevel: LoggingCategory.Info
    }
}
