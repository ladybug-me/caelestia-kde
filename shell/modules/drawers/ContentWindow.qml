pragma ComponentBehavior: Bound

import "blur"
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtCore
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils
import qs.modules.background
import qs.modules.bar
import qs.modules.overview as Overview
import qs.modules.background.desktopicons

StyledWindow {
    id: root

    property real blurOffsetTop: 0
    property real blurOffsetBottom: 0
    property real blurOffsetLeft: 0
    property real blurOffsetRight: 0
    property alias overviewAnimConfig: animConfig
    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions
    readonly property alias visibilities: visibilities
    // The per-screen state object the drawers share. The dashboard's tab and the
    // month its calendar is showing live in it, which is where upstream keeps
    // them, so both survive the dashboard closing and a shell reload.
    readonly property ScreenState screenState: ShellState.forScreen(screen)
    readonly property var monitor: Kwin.monitorFor(screen)
    // Reference Kwin.activeWsId so QML re-evaluates this binding whenever the
    // active workspace changes — hasFullscreenOn() filters by workspace, but
    // a plain function call only re-runs when its direct property deps change.
    readonly property bool actualFullscreen: (Kwin.activeWsId, Kwin.hasFullscreenOn(screen?.name ?? ""))
    readonly property bool transientOverlayOpen: panels.popouts.isDetached || panels.popouts.isContextPopout || desktopContextMenu.expanded || desktopIconContextMenu.expanded || dropMenu.expanded || viewOptions.open || widgetGallery.open || visibilities.overview || Visibilities.launcherOpen || visibilities.dashboard || visibilities.session || visibilities.utilities
    readonly property bool hasOpenOverlay: focusGrabState.active || transientOverlayOpen || visibilities.sidebar
    readonly property bool hasFullscreen: actualFullscreen && !hasOpenOverlay
    // The launcher is one panel across outputs: a screen that does not show it
    // still takes input, so that a press there dismisses it.
    readonly property bool foreignLauncherOpen: Visibilities.launcherOpen && !visibilities.launcher
    // A context menu on another screen still needs this layer to take the dismiss
    // click; it must not lift the fullscreen suppression above, which is per screen.
    readonly property bool capturesOverlayInput: hasOpenOverlay || Visibilities.contextPopoutOpen

    // The sidebar is the only thing open and it is pinned (or one of the shell's
    // file dialogs is up): take input only over the panels, not the whole screen,
    // so clicks outside reach other windows instead of closing the sidebar.
    readonly property bool sidebarPassthrough: visibilities.sidebar && (Visibilities.sidebarPinned || Visibilities.openDialogs > 0)
        && !(transientOverlayOpen || (TrayRegistry.isTrayPopout(panels.popouts.currentName) && (panels.popouts.current as StackView)?.depth > 1))
    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg
    readonly property real overviewBorderThickness: Math.min(root.width, root.height) * 0.15
    property real dynamicBorderThickness: visibilities.overview ? overviewBorderThickness : Config.border.thickness
    property real overviewVerticalOffset: {
        if (!visibilities.overview) return 0;
        const grid = panels && panels.overview ? panels.overview.windowGrid : null;
        return grid ? grid.verticalOffset : 0;
    }
    readonly property real borderThickness: dynamicBorderThickness * (1 - fsTransitionProg)
    readonly property real borderRounding: Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : dynamicBorderThickness
    property color surfaceColour: Colours.tPalette.m3surface
    readonly property int dragMaskPadding: {
        if (focusGrabState.active || panels.popouts.isDetached)
            return 0;
        if (!monitor || monitor.lastIpcObject?.specialWorkspace?.name || monitor.activeWorkspace?.lastIpcObject === undefined || monitor.activeWorkspace.lastIpcObject.windows > 0)
            return 0;
        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (Config[panel].enabled)
                thresholds.push(Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    // The window takes the keyboard while a panel that owns text is open, and that is
    // Panels' answer to give: it is the one place that has them all.
    readonly property bool wantsKeyboard: panels.wantsKeyboard

    onHasFullscreenChanged: {
        if (!hasFullscreen)
            return;
        visibilities.launcher = false;
        visibilities.session = false;
        visibilities.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"

    WlrLayershell.namespace: "dock"
    mask: {
        if (capturesOverlayInput && !sidebarPassthrough) return fullRegion;
        if (hasFullscreen) return emptyRegion;
        return regions;
    }
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: !wantsKeyboard && (capturesOverlayInput || (actualFullscreen && fsTransitionProg < 1) || (fsTransitionProg > 0 && Config.general.showOverFullscreen) || (panels.notifications.visible && panels.notifications.height > 0 && GlobalConfig.notifs.fullscreen === "on") || (((monitor?.lastIpcObject?.specialWorkspace?.name?.length ?? 0) > 0) && (monitor?.activeWorkspace?.toplevels?.values?.some(t => (t?.lastIpcObject?.fullscreen ?? 0) > 1) ?? false))) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // A pinned sidebar gets out of the way of fullscreen windows (games, video)
    // and comes back once fullscreen ends.
    onActualFullscreenChanged: {
        if (actualFullscreen) {
            if (visibilities.sidebar && Visibilities.sidebarPinned) {
                visibilities.sidebarSuspended = true;
                visibilities.sidebar = false;
            }
        } else if (visibilities.sidebarSuspended) {
            visibilities.sidebarSuspended = false;
            if (Visibilities.sidebarPinned)
                visibilities.sidebar = true;
        }
    }

    FocusReturn {
        active: root.wantsKeyboard
    }

    Overview.Anim {
        id: animConfig
    }
    Settings {
        id: borderBlurSettings

        property int blurQuality: 20

        category: "Blur"
    }
    Behavior on dynamicBorderThickness { NumberAnimation { duration: animConfig.blobDuration; easing.type: animConfig.easingType } }
    Behavior on overviewVerticalOffset { NumberAnimation { duration: animConfig.blobDuration; easing.type: animConfig.easingType } }
    Behavior on fsTransitionProg {
        Anim {}
    }
    Behavior on surfaceColour {
        CAnim {}
    }
    Region {
        id: emptyRegion

        x: panels.notifications.x + panels.leftMargin
        y: panels.notifications.y + panels.topMargin
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.width - width
            y: panels.osdWrapper.y + panels.topMargin
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + panels.topMargin
            height: panels.osd.height
        }
    }
    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }
    Region {
        id: fullRegion

        x: 0
        y: 0
        width: root.width
        height: root.height
    }
    QtObject {
        id: focusGrabState

        property bool active: (visibilities.launcher && Config.launcher.enabled) || (visibilities.session && Config.session.enabled) || (visibilities.sidebar && Config.sidebar.enabled) || (!Config.dashboard.showOnHover && visibilities.dashboard && Config.dashboard.enabled) || (!Config.utilities.showOnHover && visibilities.utilities && Config.utilities.enabled) || (TrayRegistry.isTrayPopout(panels.popouts.currentName) && (panels.popouts.current as StackView)?.depth > 1)

        function clear() {
            visibilities.launcher = false;
            visibilities.session = false;
            if (!Visibilities.sidebarPinned)
                visibilities.sidebar = false;
            visibilities.dashboard = false;
            visibilities.utilities = false;
            Visibilities.setOverview(false);
            Visibilities.closeContextPopouts();
            panels.popouts.close();
            bar.closeTray();
        }

        onActiveChanged: {
        }
    }
    StyledRect {
        property bool _wasActive: false

        anchors.fill: parent
        opacity: (visibilities.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Timer {
            id: kdeFocusGrab

            interval: 100
            repeat: true
            running: focusGrabState.active || panels.popouts.isDetached
            onRunningChanged: {
                if (!running) {
                    parent._wasActive = false;
                }
            }
            onTriggered: {
                // Focus moved to one of the shell's own file dialogs: keep the
                // drawers open, and wait for the shell to be focused again before
                // treating focus loss as a reason to close them.
                if (Visibilities.openDialogs > 0) {
                    parent._wasActive = false;
                    return;
                }

                let anyActive = root.active || root.activeFocusItem !== null;

                if (anyActive) {
                    parent._wasActive = true;
                } else if (parent._wasActive && !anyActive) {
                    parent._wasActive = false;
                    focusGrabState.clear();
                    if (panels.popouts.isDetached) panels.popouts.close();
                }
            }
        }
        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }
    Item {
        id: overviewWallpaperLayer

        property bool active: visibilities.overview || warming
        property bool keepAlive: false
        property bool warming: false
        property real _maxBorder: Math.max(1, Math.min(root.width, root.height) * 0.15)
        property real bgScale: 1.0 + (dynamicBorderThickness / _maxBorder) * 0.1

        onActiveChanged: {
            if (active)
                keepAlive = true;
        }

        anchors.fill: parent
        visible: active || opacity > 0
        layer.enabled: true
        opacity: warming ? 0.004 : ((visibilities.overview && wallpaperLoader.status === Loader.Ready) ? 1 : 0)

        Behavior on opacity { NumberAnimation { duration: overviewWallpaperLayer.warming ? 0 : animConfig.wallpaperDuration; easing.type: animConfig.easingType } }
        Timer {
            running: true
            interval: 2500
            onTriggered: { overviewWallpaperLayer.warming = true; warmDone.start(); }
        }
        Timer {
            id: warmDone

            interval: 400
            onTriggered: overviewWallpaperLayer.warming = false
        }
        Item {
            id: scaledWallpaperContainer

            anchors.fill: parent

            Loader {
                id: wallpaperLoader

                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                scale: overviewWallpaperLayer.bgScale
                active: overviewWallpaperLayer.active || overviewWallpaperLayer.opacity > 0
                        || (overviewWallpaperLayer.keepAlive && wallpaperLoader.item && !wallpaperLoader.item.isVideo(wallpaperLoader.item.source))
                sourceComponent: Component {
                    Wallpaper {
                        screen: root.screen
                        skipTransition: true
                        source: {
                            const cur = Wallpapers.current;
                            if (Images.isVideo(cur)) {
                                const hifi = Wallpapers.thumbHifi(cur);
                                return hifi !== "" ? hifi : Wallpapers.getThumbnailHifiPath(cur);
                            }
                            return cur;
                        }
                    }
                }
            }
        }
        Item {
            id: maskContainer

            anchors.fill: parent

            BlobGroup {
                id: overviewBlurMask

                color: "white"
            }
            BlobInvertedRect {
                anchors.fill: parent
                anchors.margins: -50
                group: overviewBlurMask
                radius: root.borderRounding
                borderLeft: Math.max(bar.position === "left" ? bar.implicitWidth : 0, root.borderThickness) - anchors.margins - root.sdfBorderOffset
                borderRight: Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness) - anchors.margins - root.sdfBorderOffset
                borderTop: Math.max(bar.position === "top" ? bar.implicitHeight : 0, root.borderThickness) - root.overviewVerticalOffset - anchors.margins - root.sdfBorderOffset
                borderBottom: Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness) + root.overviewVerticalOffset - anchors.margins - root.sdfBorderOffset
                Config.screen: root.screen.name
            }
        }
        ShaderEffectSource {
            id: overviewWallpaperSource

            sourceItem: scaledWallpaperContainer
            anchors.fill: parent
            hideSource: false
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: overviewWallpaperSource
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: ShaderEffectSource {
                sourceItem: maskContainer
                hideSource: true
            }
            blurEnabled: GlobalConfig.appearance.blur && GlobalConfig.overview.enableOverviewBlur
            blurMax: 64
            blur: 1.0
        }
    }
    Item {
        id: layoutContainer

        anchors.fill: parent
        opacity: GlobalConfig.appearance.pitchBlack ? 1 : (Colours.transparency.enabled ? Colours.transparency.base : 1.0)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: GlobalConfig.appearance.pitchBlack ? "#000000" : root.surfaceColour
            smoothing: Config.border.smoothing
        }
        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50
            group: GlobalConfig.appearance.islands ? null : blobGroup
            visible: !GlobalConfig.appearance.islands
            radius: root.borderRounding
            borderLeft: Math.max(bar.position === "left" ? bar.implicitWidth : 0, root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderRight: Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderTop: Math.max(bar.position === "top" ? bar.implicitHeight : 0, root.borderThickness) - root.overviewVerticalOffset - anchors.margins - root.sdfBorderOffset
            borderBottom: Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness) + root.overviewVerticalOffset - anchors.margins - root.sdfBorderOffset
            Config.screen: root.screen.name
        }
        BlobRect {
            visible: GlobalConfig.appearance.islands
            group: GlobalConfig.appearance.islands ? blobGroup : null
            x: bar.x
            y: bar.y
            implicitWidth: bar.width
            implicitHeight: bar.height
            radius: Tokens.rounding.extraLarge
            deformScale: (GlobalConfig.appearance.blurMask || !GlobalConfig.appearance.transparency.enabled) ? ((0.1 * Config.appearance.deformScale) / 10000) : 0
        }
        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
        }
        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }
        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.sessionWrapper.x + panels.leftMargin
            implicitWidth: panels.sessionWrapper.width
        }
        PanelBg {
            id: sidebarBg

            property bool connectedToPopout: (bar.position === "top" || bar.position === "bottom") && panels.popouts.sidebarOpen && panels.popouts.implicitWidth <= Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) + 1 && !panels.popouts.isDockPopout

            panel: panels.sidebar
            deformAmount: Visibilities.sidebarResizing ? 0 : 0.03
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: {
                let arr = [];
                if (panels.sidebar.offsetScale <= 0.08) arr.push(utilsBg);
                if (connectedToPopout) arr.push(popoutBg);
                return arr;
            }
            topLeftRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "top" && connectedToPopout) ? 0 : (bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius))
            topRightRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "top" && connectedToPopout) ? 0 : (bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius))
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "bottom" && connectedToPopout) ? 0 : (bar.position === "right" ? radius : Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius))
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "bottom" && connectedToPopout) ? 0 : (bar.position === "right" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius))
        }
        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.leftMargin
            implicitWidth: panels.osdWrapper.width
        }
        PanelBg {
            id: notifsBg

            panel: panels.notifications
            // A notification is transient and the drawer is not: keeping them out of one
            // another's blob stops the two backgrounds bridging into a shape that is
            // neither panel when they share the corner. Exclusion is symmetric, so this
            // side stating it is enough.
            exclude: [utilsBg]
        }
        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: GlobalConfig.appearance.islands ? radius : (bar.position === "right" ? radius : (bar.position === "bottom" ? radius : Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius))
            topRightRadius: GlobalConfig.appearance.islands ? radius : (bar.position === "right" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : (bar.position === "bottom" ? radius : Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius))
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : (bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius)
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : (bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius)
        }
        PanelBg {
            id: contextMenuBg

            // Squared off while the panel beside it shares one of its edges, so that
            // the two meet on a single straight line instead of leaving a notch.
            readonly property bool attachedTop: contextSubmenuBg.attachedTop
            readonly property bool attachedBottom: contextSubmenuBg.attachedBottom

            panel: desktopContextMenu.backgroundItem
            // Stay up while the closing animation runs, not just while expanded.
            visible: desktopContextMenu.visible && panel.width > 0
            x: panel.x
            y: panel.y
            // Held out of the fusion: blended together, the edges the two panels share
            // swell where they meet, which reads as a bump on an otherwise straight line.
            exclude: contextSubmenuBg.seamed ? [contextSubmenuBg] : []
            topRightRadius: attachedTop && contextSubmenuBg.opensRight ? 0 : radius
            topLeftRadius: attachedTop && !contextSubmenuBg.opensRight ? 0 : radius
            bottomRightRadius: attachedBottom && contextSubmenuBg.opensRight ? 0 : radius
            bottomLeftRadius: attachedBottom && !contextSubmenuBg.opensRight ? 0 : radius
        }
        PanelBg {
            id: contextSubmenuBg

            // The entries a row unfolds sit flush against the menu and share its
            // backdrop, so the two read as one surface. The corners on the edge they
            // share are squared off, so the junction is a plain right angle and the
            // outer line stays straight.
            // qmllint disable missing-property
            readonly property bool attachedTop: seamed && desktopContextMenu.submenuPanel.flushTop
            readonly property bool attachedBottom: seamed && desktopContextMenu.submenuPanel.flushBottom
            readonly property bool opensRight: !seamed || desktopContextMenu.submenuPanel.opensRight
            // qmllint enable missing-property
            // Stays on while the panel is still on screen, its closing animation
            // included: the corners flipping back mid-animation would show the two
            // fused again, with the bump that comes with it.
            readonly property bool seamed: desktopContextMenu.submenuOpen || desktopContextMenu.submenuPanel.hScale > 0

            panel: desktopContextMenu.submenuPanel
            visible: desktopContextMenu.visible && panel.width > 0
            x: panel.x
            y: panel.y
            exclude: seamed ? [contextMenuBg] : []
            excludeCorners: seamed ? [contextMenuBg] : []
            topLeftRadius: opensRight ? 0 : radius
            bottomLeftRadius: opensRight ? 0 : radius
            topRightRadius: opensRight ? radius : 0
            bottomRightRadius: opensRight ? radius : 0
        }
        PanelBg {
            id: popoutBg

            property real extraShift: panels.popouts.isDetached ? 0 : 0.2
            property bool connectedToSidebar: (bar.position === "top" || bar.position === "bottom") && panels.popouts.sidebarOpen && panels.popouts.implicitWidth <= Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) + 1 && !panels.popouts.isDockPopout

            panel: panels.popoutsWrapper
            deformAmount: connectedToSidebar ? 0.03 : (panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1)
            exclude: connectedToSidebar ? [sidebarBg] : []
            x: {
                const baseX = panels.popoutsWrapper.x + panels.popouts.x + panels.leftMargin;
                if (bar.position === "left")
                    return baseX - panels.popouts.implicitWidth * extraShift;
                return baseX;
            }
            implicitWidth: {
                if (bar.position === "left" || bar.position === "right")
                    return panels.popouts.implicitWidth * (1 + extraShift);
                return panels.popouts.implicitWidth;
            }
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "top" && connectedToSidebar) ? 0 : radius)
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "top" && connectedToSidebar) ? 0 : radius)
            topLeftRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "bottom" && connectedToSidebar) ? 0 : radius)
            topRightRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "bottom" && connectedToSidebar) ? 0 : radius)
            y: {
                const baseY = panels.popoutsWrapper.y + panels.popouts.y + panels.topMargin;
                if (bar.position === "top")
                    return baseY - panels.popouts.implicitHeight * extraShift;
                if (bar.position === "bottom" && connectedToSidebar)
                    return baseY - Tokens.spacing.extraLarge - 10;
                return baseY;
            }
            implicitHeight: {
                if (bar.position === "top" || bar.position === "bottom") {
                    let h = panels.popouts.implicitHeight * (1 + extraShift);
                    if (connectedToSidebar) h += Tokens.spacing.extraLarge + 10;
                    return h;
                }
                return panels.popouts.implicitHeight;
            }

            Behavior on extraShift {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }
    }
    DrawerVisibilities {
        id: visibilities

        onOverviewChanged: {
            if (overview && !GlobalConfig.overview.enabled) {
                overview = false;
            }
        }
        Component.onCompleted: Visibilities.load(root.screen, this)
        Component.onDestruction: Visibilities.unload(this)
    }
    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        visibilities: visibilities
        dismissLauncher: root.foreignLauncherOpen
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen
        capturesDismissClick: root.capturesOverlayInput
        focusGrab: focusGrabState
        states: [
            State {
                name: "left"
                when: bar.position === "left"

                AnchorChanges {
                    target: bar
                    anchors.left: parent.left
                    anchors.right: undefined
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                }
                PropertyChanges {
                    target: bar
                    width: bar.implicitWidth
                    height: undefined
                    anchors.topMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.leftMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.rightMargin: 0
                }
            },
            State {
                name: "right"
                when: bar.position === "right"

                AnchorChanges {
                    target: bar
                    anchors.left: undefined
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                }
                PropertyChanges {
                    target: bar
                    width: bar.implicitWidth
                    height: undefined
                    anchors.topMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.leftMargin: 0
                    anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                }
            },
            State {
                name: "top"
                when: bar.position === "top"

                AnchorChanges {
                    target: bar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: undefined
                }
                PropertyChanges {
                    target: bar
                    width: undefined
                    height: bar.implicitHeight
                    anchors.leftMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.topMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: 0
                }
            },
            State {
                name: "bottom"
                when: bar.position === "bottom"

                AnchorChanges {
                    target: bar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: undefined
                    anchors.bottom: parent.bottom
                }
                PropertyChanges {
                    target: bar
                    width: undefined
                    height: bar.implicitHeight
                    anchors.leftMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.topMargin: 0
                }
            }
        ]

        MouseArea {
            anchors.fill: parent
            visible: visibilities.overview
            onClicked: Visibilities.setOverview(false)
        }
        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            visibilities: visibilities
            bar: bar
            borderThickness: root.borderThickness
            overviewBorderThickness: root.overviewBorderThickness
            overviewAnimConfig: root.overviewAnimConfig
            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix
            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
            cursorPos: Qt.point(interactions.mouseX, interactions.mouseY)
        }
        BarWrapper {
            id: bar

            property string vAnchor: (bar.position === "left" || bar.position === "right") ? "both" : (bar.position === "top" ? "top" : "bottom")
            property string hAnchor: (bar.position === "top" || bar.position === "bottom") ? "both" : (bar.position === "left" ? "left" : "right")

            screen: root.screen
            visibilities: visibilities
            popouts: panels.popouts
            fullscreen: root.hasFullscreen
            Component.onCompleted: Visibilities.registerBar(root.screen, this)
        }
        Connections {
            function onOpenDesktopContextMenu(x, y, screenName) {
                if (ContextMenuStore.editMode || Config.background.disableQuickshellDesktop)
                    return;
                if (root.screen.name === screenName) {
                    desktopContextMenuAnchor.x = x;
                    desktopContextMenuAnchor.y = y;
                    // Already open: jump to the new spot and unfold again
                    // instead of closing and waiting before reopening.
                    if (desktopContextMenu.expanded)
                        desktopContextMenu.reopen();
                    else
                        desktopContextMenu.expanded = true;
                }
            }

            target: ContextMenuStore
        }
        Connections {
            function onOpenIconContextMenu(screenName: string, x: real, y: real, keys: var, inGroup: string): void {
                if (root.screen.name === screenName) {
                    desktopIconContextMenu.openAt(x, y, keys, inGroup);
                }
            }

            function onOpenDropMenu(screenName: string, x: real, y: real, urls: var, target: string, cell: var): void {
                if (root.screen.name === screenName) {
                    dropMenu.openAt(x, y, urls, target, cell);
                }
            }

            function onViewOptionsRequested(screenName: string, x: real, y: real): void {
                if (root.screen.name === screenName) {
                    viewOptions.openAt(x, y);
                }
            }

            function onAddWidgetRequested(screenName: string, x: real, y: real): void {
                if (root.screen.name === screenName) {
                    const ctrl = DesktopLayout.controllerFor(screenName);
                    widgetGallery.openAt(x, y, ctrl ? ctrl.cellAt(x, y) : null);
                }
            }

            target: DesktopLayout
        }
        Item {
            id: desktopContextMenuAnchor
        }
        DesktopContextMenu {
            id: desktopContextMenu

            attachTo: desktopContextMenuAnchor
            screenName: root.screen.name
            z: 9999
        }
        DesktopIconContextMenu {
            id: desktopIconContextMenu

            controller: DesktopLayout.controllerFor(root.screen.name)
            z: 9999
        }
        DropMenu {
            id: dropMenu

            controller: DesktopLayout.controllerFor(root.screen.name)
            z: 9999
        }
        ViewOptions {
            id: viewOptions

            controller: DesktopLayout.controllerFor(root.screen.name)
            z: 10000
        }
        WidgetGallery {
            id: widgetGallery

            controller: DesktopLayout.controllerFor(root.screen.name)
            z: 10000
        }
    }

    Config.screen: screen.name
    BackgroundEffect.blurRegion: Region {
        Region { x: -10; y: -10; width: 1; height: 1 }
        Region {
            x: 0; y: 0
            width: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur) ? Math.max(bar.position === "left" ? bar.implicitWidth : 0, root.borderThickness) : 0
            height: root.height
            intersection: Intersection.Combine
        }
        Region {
            x: root.width - Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness); y: 0
            width: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur) ? Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness) : 0
            height: root.height
            intersection: Intersection.Combine
        }
        Region {
            x: 0; y: 0
            width: root.width
            height: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur) ? Math.max(bar.position === "top" ? bar.implicitHeight : 0, root.borderThickness) : 0
            intersection: Intersection.Combine
        }
        Region {
            x: 0; y: root.height - Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness)
            width: root.width
            height: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur) ? Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness) : 0
            intersection: Intersection.Combine
        }
        Region {
            x: Math.max(bar.position === "left" ? bar.implicitWidth : 0, root.borderThickness)
            y: Math.max(bar.position === "top" ? bar.implicitHeight : 0, root.borderThickness)
            width: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            height: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            intersection: Intersection.Combine
        }
        Region {
            x: root.width - Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness) - root.borderRounding
            y: Math.max(bar.position === "top" ? bar.implicitHeight : 0, root.borderThickness)
            width: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            height: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            intersection: Intersection.Combine
        }
        Region {
            x: Math.max(bar.position === "left" ? bar.implicitWidth : 0, root.borderThickness)
            y: root.height - Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness) - root.borderRounding
            width: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            height: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            intersection: Intersection.Combine
        }
        Region {
            x: root.width - Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness) - root.borderRounding
            y: root.height - Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness) - root.borderRounding
            width: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            height: (!GlobalConfig.appearance.islands && GlobalConfig.appearance.blur && GlobalConfig.appearance.blurMask) ? root.borderRounding : 0
            intersection: Intersection.Combine
        }
        BlurCorners {
            intersection: Intersection.Subtract
            vAnchor: "none"
            hAnchor: "none"
            blurQuality: borderBlurSettings.blurQuality
            inLeft: Math.max(bar.position === "left" ? bar.implicitWidth : 0, root.borderThickness) + root.borderRounding
            inRight: root.width - Math.max(bar.position === "right" ? bar.implicitWidth : 0, root.borderThickness) - root.borderRounding
            inTop: Math.max(bar.position === "top" ? bar.implicitHeight : 0, root.borderThickness) + root.borderRounding
            inBottom: root.height - Math.max(bar.position === "bottom" ? bar.implicitHeight : 0, root.borderThickness) - root.borderRounding
            rTop: !GlobalConfig.appearance.islands ? root.borderRounding : 0
            rBottom: !GlobalConfig.appearance.islands ? root.borderRounding : 0
            rLeft: !GlobalConfig.appearance.islands ? root.borderRounding : 0
            rRight: !GlobalConfig.appearance.islands ? root.borderRounding : 0
        }
        BlurMask {
            target: bar
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: bar.vAnchor
            hAnchor: bar.hAnchor
        }
        BlurMask {
            target: panels.sidebar
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.sidebar.vAnchor
            hAnchor: panels.sidebar.hAnchor
            offsetScale: panels.sidebar.offsetScale
            deformMatrix: sidebarBg.deformMatrix
        }
        BlurMask {
            target: panels.notifications
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.notifications.vAnchor
            hAnchor: panels.notifications.hAnchor
            deformMatrix: notifsBg.deformMatrix
        }
        BlurMask {
            target: panels.osdWrapper
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.osdWrapper.vAnchor
            hAnchor: panels.osdWrapper.hAnchor
            offsetScale: panels.osd.offsetScale
            deformMatrix: osdBg.deformMatrix
        }
        BlurMask {
            target: panels.sessionWrapper
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.sessionWrapper.vAnchor
            hAnchor: panels.sessionWrapper.hAnchor
            offsetScale: panels.session.offsetScale
            deformMatrix: sessionBg.deformMatrix
        }
        BlurMask {
            target: panels.launcher
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.launcher.vAnchor
            hAnchor: panels.launcher.hAnchor
            offsetScale: panels.launcher.offsetScale
            deformMatrix: launcherBg.deformMatrix
        }
        BlurMask {
            target: panels.dashboard
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.dashboard.vAnchor
            hAnchor: panels.dashboard.hAnchor
            offsetScale: panels.dashboard.offsetScale
            deformMatrix: dashBg.deformMatrix
        }
        BlurMask {
            target: panels.popoutsWrapper
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop - (popoutBg.connectedToSidebar ? Tokens.spacing.extraLarge + 10 + Tokens.rounding.extraLarge : 0)
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.popoutsWrapper.vAnchor
            hAnchor: panels.popoutsWrapper.hAnchor
            offsetScale: panels.popoutsWrapper.offsetScale
            deformMatrix: popoutBg.deformMatrix
        }
        BlurMask {
            target: panels.utilities
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: panels.utilities.vAnchor
            hAnchor: panels.utilities.hAnchor
            offsetScale: panels.utilities.offsetScale
            deformMatrix: utilsBg.deformMatrix
        }
        BlurMask {
            target: desktopContextMenu.visible ? desktopContextMenu.backgroundItem : null
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft + 1
            blurOffsetRight: root.blurOffsetRight
            vAnchor: desktopContextMenu.backgroundItem.vAnchor
            hAnchor: desktopContextMenu.backgroundItem.hAnchor
            offsetScale: desktopContextMenu.backgroundItem.offsetScale
            deformMatrix: contextMenuBg.deformMatrix
        }
        BlurMask {
            target: (visibilities.overview && !GlobalConfig.overview.disableWallpaperBlur) ? panels.overview : null
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: "both"
            hAnchor: "both"
        }
        BlurMask {
            target: desktopContextMenu.visible && (desktopContextMenu.submenuOpen || desktopContextMenu.submenuPanel.hScale > 0) ? desktopContextMenu.submenuPanel : null
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: desktopContextMenu.submenuPanel.vAnchor
            hAnchor: desktopContextMenu.submenuPanel.hAnchor
            deformMatrix: contextSubmenuBg.deformMatrix
        }
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        group: panel.visible ? blobGroup : null
        visible: panel.visible
        x: panel.x + panels.leftMargin
        y: panel.y + panels.topMargin
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Surface.panelRounding
        deformScale: (GlobalConfig.appearance.blurMask || !GlobalConfig.appearance.transparency.enabled) ? ((deformAmount * Config.appearance.deformScale) / 10000) : 0
        Config.screen: root.screen.name
    }
}
