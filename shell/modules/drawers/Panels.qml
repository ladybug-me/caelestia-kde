import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.overview as Overview
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities.toasts as Toasts
import "../utilities/toasts/corner.js" as Corner

Item {
    id: root

    required property ShellScreen screen
    Config.screen: screen.name
    required property ScreenState screenState
    required property DrawerVisibilities visibilities
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property real overviewBorderThickness
    // Per-side frame thickness, supplied by ContentWindow. The panels live
    // inside the frame, so their insets follow it directly instead of
    // recomputing it from the bar.
    required property FrameEdges frameEdges
    property var overviewAnimConfig
    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar
    readonly property alias overview: overview
    readonly property real leftMargin: anchors.leftMargin
    readonly property real rightMargin: anchors.rightMargin
    readonly property real topMargin: anchors.topMargin
    readonly property real bottomMargin: anchors.bottomMargin
    property point cursorPos
    readonly property string notifAutoPosition: {
        const barPos = bar.position;
        const v = barPos === "bottom" ? "bottom" : "top";
        const h = barPos === "right" ? "left" : "right";
        return `${v}-${h}`;
    }
    readonly property string notifPosition: GlobalConfig.notifs.position !== "auto" ? GlobalConfig.notifs.position : notifAutoPosition
    readonly property bool notifAtTop: notifPosition.startsWith("top")
    readonly property bool notifAtBottom: notifPosition.startsWith("bottom")
    readonly property real notifReservedHeight: notifications.implicitHeight > 0 ? notifications.implicitHeight + Tokens.spacing.extraLarge : 0

    /// How tall the notification stack may grow before it would run into a panel that is
    /// open beside it. Measured here because this is the only place that holds every
    /// panel in one coordinate space; the stack gets a number instead of guessing at each
    /// panel in turn.
    readonly property real notifRoom: {
        const bottom = root.height;
        let lowestPanelEdge = 0;
        if (osd.offsetScale < 1)
            lowestPanelEdge = Math.max(lowestPanelEdge, osdWrapper.y + osdWrapper.height);
        if (session.offsetScale < 1)
            lowestPanelEdge = Math.max(lowestPanelEdge, sessionWrapper.y + sessionWrapper.height);
        if (utilities.offsetScale < 1)
            lowestPanelEdge = Math.max(lowestPanelEdge, utilities.y + utilities.height);

        return Math.max(0, bottom - lowestPanelEdge);
    }

    /// Whether this window has to take the keyboard: a panel that owns text fields is
    /// open. The OSD is deliberately absent, because it only ever shows things, and so is
    /// the notification stack. Panels say it here, where they are built, so the next panel
    /// to grow a text field cannot be forgotten in another file.
    readonly property bool wantsKeyboard: launcher.offsetScale < 1 || session.offsetScale < 1 || dashboard.offsetScale < 1 || sidebar.offsetScale < 1 || overview.visible || utilities.offsetScale < 1 || (popouts.hasCurrent && !popouts.isDockPopout)

    readonly property bool popoutIntersectsRight: {
        if (!popoutsWrapper.visible || popoutsWrapper.offsetScale >= 1) return false;
        if (bar.isHorizontal) {
            const notifLeft = notifications.x;
            const notifRight = notifLeft + (notifications.implicitWidth > 0 ? notifications.implicitWidth : Tokens.sizes.notifs.width);
            // Use where the popout ends up, not where its slide currently is, so
            // switching between bar items doesn't push the sidebar on the way.
            const popLeft = popoutsWrapper.targetX;
            const popRight = popoutsWrapper.targetX + popoutsWrapper.content.nonAnimWidth;
            return popLeft < notifRight && popRight > notifLeft;
        } else {
            const notifTop = notifications.y;
            const notifBottom = notifTop + (notifications.implicitHeight > 0 ? notifications.implicitHeight : 300);
            const popTop = popoutsWrapper.y;
            const popBottom = popoutsWrapper.y + popoutsWrapper.content.nonAnimHeight;
            return popTop < notifBottom && popBottom > notifTop;
        }
    }

    readonly property bool popoutIntersectsSidebar: {
        if (!popoutsWrapper.visible || popoutsWrapper.offsetScale >= 1) return false;
        if (!sidebar.visible) return false;
        if (bar.isHorizontal) {
            const sideLeft = sidebar.x;
            const sideRight = sideLeft + sidebar.width;
            const popLeft = popoutsWrapper.x;
            const popRight = popoutsWrapper.x + popoutsWrapper.content.nonAnimWidth;
            return popLeft < sideRight && popRight > sideLeft;
        } else {
            const sideTop = sidebar.y;
            const sideBottom = sideTop + sidebar.height;
            const popTop = popoutsWrapper.y;
            const popBottom = popoutsWrapper.y + popoutsWrapper.content.nonAnimHeight;
            return popTop < sideBottom && popBottom > sideTop;
        }
    }

    anchors.fill: parent
    anchors.leftMargin: frameEdges.left + (GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge * (bar.position === "left" ? 2 : 1) : 0)
    anchors.rightMargin: frameEdges.right + (GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge * (bar.position === "right" ? 2 : 1) : 0)
    anchors.topMargin: frameEdges.top + (GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge * (bar.position === "top" ? 2 : 1) : 0)
    anchors.bottomMargin: frameEdges.bottom + (GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge * (bar.position === "bottom" ? 2 : 1) : 0)
    states: [
        State {
            name: "right"
            when: bar.position === "right"

            AnchorChanges {
                target: osdWrapper
                anchors.left: parent.left
                anchors.right: undefined
            }
            AnchorChanges {
                target: osd
                anchors.left: parent.left
                anchors.right: undefined
            }
            AnchorChanges {
                target: sessionWrapper
                anchors.left: parent.left
                anchors.right: undefined
            }
            AnchorChanges {
                target: session
                anchors.left: parent.left
                anchors.right: undefined
            }
            AnchorChanges {
                target: utilities
                anchors.left: parent.left
                anchors.right: undefined
            }
            AnchorChanges {
                target: sidebar
                anchors.left: parent.left
                anchors.right: undefined
            }
        },
        State {
            name: "bottom"
            when: bar.position === "bottom"

            AnchorChanges {
                target: utilities
                anchors.bottom: undefined
                anchors.top: parent.top
            }
            AnchorChanges {
                target: sidebar
                anchors.top: utilities.bottom
                anchors.bottom: parent.bottom
            }
            PropertyChanges {
                target: sidebar
                anchors.topMargin: -4
                anchors.bottomMargin: (root.notifAtBottom ? root.notifReservedHeight : 0)
                    + (sidebar.shouldPush ? popoutsWrapper.implicitHeight + sidebar.pushSpacing : 0)
            }
        }
    ]

    Item {
        id: osdWrapper

        property string vAnchor: "center"
        property string hAnchor: bar.position === "right" ? "left" : "right"

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.leftMargin: bar.position === "right" ? sidebar.width * (1 - sidebar.offsetScale) + session.width * (1 - session.offsetScale) : 0
        anchors.rightMargin: bar.position !== "right" ? sidebar.width * (1 - sidebar.offsetScale) + session.width * (1 - session.offsetScale) : 0
        clip: sidebar.visible || session.visible
        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight
        visible: osd.offsetScale < 1

        Osd.Wrapper {
            id: osd

            screen: root.screen
            visibilities: root.visibilities
            sidebarOrSessionVisible: sidebar.visible || session.visible
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }
    Notifications.Wrapper {
        id: notifications

        readonly property string _notifV: root.notifPosition.split("-")[0]
        readonly property string _notifH: root.notifPosition.split("-")[1]
        property string vAnchor: _notifV
        property string hAnchor: _notifH
        property bool shouldPush: root.popoutIntersectsRight && !popoutsWrapper.content.isDockPopout && !sidebar.visible

        readonly property real _pushOffset: shouldPush ? (popoutsWrapper.implicitHeight + Tokens.spacing.extraLarge) : 0

        visibilities: root.visibilities
        screen: root.screen
        sidebarPanel: sidebar
        room: root.notifRoom

        width: implicitWidth
        height: implicitHeight

        x: {
            if (_notifH === "left") return 0;
            if (_notifH === "right") return Math.max(0, parent.width - implicitWidth);
            return Math.max(0, (parent.width - implicitWidth) / 2);
        }
        y: {
            if (_notifV === "top") return _pushOffset;
            return Math.max(0, parent.height - implicitHeight - _pushOffset);
        }
    }
    Item {
        id: sessionWrapper

        property string vAnchor: "center"
        property string hAnchor: bar.position === "right" ? "left" : "right"

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.leftMargin: bar.position === "right" ? sidebar.width * (1 - sidebar.offsetScale) : 0
        anchors.rightMargin: bar.position !== "right" ? sidebar.width * (1 - sidebar.offsetScale) : 0
        clip: sidebar.visible
        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight
        visible: session.offsetScale < 1

        Session.Wrapper {
            id: session

            visibilities: root.visibilities
            sidebarVisible: sidebar.visible
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }
    Launcher.Wrapper {
        id: launcher

        property string vAnchor: "bottom"
        property string hAnchor: "center"

        screen: root.screen
        visibilities: root.visibilities
        panels: root
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }
    Dashboard.Wrapper {
        id: dashboard

        property string vAnchor: "top"
        property string hAnchor: "center"

        screenState: root.screenState
        visibilities: root.visibilities
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }
    BarPopouts.ClipWrapper {
        id: popoutsWrapper

        property string vAnchor: (popoutsWrapper.edge === "top" || popoutsWrapper.edge === "bottom") ? popoutsWrapper.edge : "none"
        property string hAnchor: (popoutsWrapper.edge === "left" || popoutsWrapper.edge === "right") ? popoutsWrapper.edge : "none"

        screen: root.screen
        bar: root.bar
        borderThickness: root.borderThickness
        visibilities: root.visibilities
    }
    Utilities.Wrapper {
        id: utilities

        property string vAnchor: bar.position === "bottom" ? "top" : "bottom"
        property string hAnchor: bar.position === "right" ? "left" : "right"

        visibilities: root.visibilities
        sidebar: sidebar
        popouts: popoutsWrapper.content
        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }
    Toasts.Toasts {
        id: toasts

        /// The corner the stack grows from, with `auto` resolved against the bar and an
        /// unknown value treated as `auto`: the setting's own vocabulary lives in
        /// corner.js, so nothing else has to know what a corner is called.
        readonly property string corner: Corner.resolve(GlobalConfig.utilities.toasts.position, bar.position)
        /// Which side the sidebar slides in from. It follows the bar, so a right-hand
        /// corner is not always the sidebar's side.
        readonly property bool sidebarOnRight: sidebar.hAnchor === "right"
        /// How much of each edge a panel that is open already occupies.
        readonly property real sidebarInset: sidebar.visible && Corner.isLeft(toasts.corner) !== toasts.sidebarOnRight ? sidebar.width : 0
        readonly property real drawerInset: utilities.visible && utilities.vAnchor === "bottom" ? utilities.implicitHeight : 0

        fromTop: Corner.isTop(toasts.corner)
        fromLeft: Corner.isLeft(toasts.corner)
        visibilities: root.visibilities
        // The corner is the only owner of these edges: the bar-position states below must
        // not move the stack, or the setting quietly stops meaning anything.
        anchors.top: Corner.isTop(toasts.corner) ? parent.top : undefined
        anchors.bottom: Corner.isTop(toasts.corner) ? undefined : parent.bottom
        anchors.left: Corner.isLeft(toasts.corner) ? parent.left : undefined
        anchors.right: Corner.isLeft(toasts.corner) ? undefined : parent.right
        anchors.topMargin: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.medium + (Corner.isLeft(toasts.corner) ? toasts.sidebarInset : 0)
        anchors.rightMargin: Tokens.padding.medium + (Corner.isLeft(toasts.corner) ? 0 : toasts.sidebarInset)
        anchors.bottomMargin: Tokens.padding.medium + (Corner.isTop(toasts.corner) ? 0 : toasts.drawerInset)
    }
    Sidebar.Wrapper {
        id: sidebar

        property string vAnchor: "bottom"
        property string hAnchor: bar.position === "right" ? "left" : "right"
        property bool shouldPush: root.popoutIntersectsSidebar && !popoutsWrapper.content.isDockPopout
        // A popout no wider than the sidebar is drawn joined to it (ContentWindow.qml),
        // so it goes right below the sidebar instead of leaving a gap.
        readonly property real pushSpacing: popoutsWrapper.content.implicitWidth <= Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) + 1 ? 0 : Tokens.spacing.extraLarge

        visibilities: root.visibilities
        popouts: popoutsWrapper.content
        utilities: utilities
        followsPopout: shouldPush
        anchors.top: parent.top
        anchors.bottom: utilities.top
        anchors.right: parent.right
        anchors.topMargin: root.notifAtTop
            ? (root.notifReservedHeight + ((bar.position === "top" && shouldPush) ? popoutsWrapper.implicitHeight + sidebar.pushSpacing : 0))
            : ((bar.position === "top" && shouldPush) ? (popoutsWrapper.implicitHeight + sidebar.pushSpacing) : 0)
        anchors.bottomMargin: (bar.position === "bottom" && shouldPush) ? (popoutsWrapper.implicitHeight + sidebar.pushSpacing) : 0
    }
    Overview.Wrapper {
        id: overview

        property string vAnchor: "center"
        property string hAnchor: "center"
        property var animConfig: root.overviewAnimConfig

        screen: root.screen
        visibilities: root.visibilities
        panels: root
    }
}
