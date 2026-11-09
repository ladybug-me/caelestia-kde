pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar as Bar

Scope {
    id: root

    required property ShellScreen screen
    required property Bar.BarWrapper bar
    required property DrawerVisibilities visibilities
    // Frame thickness each full-edge panel takes on its side (the panel edges of
    // the content window). It is reserved even while the panels are collapsed,
    // so opening the overview does not resize the maximised windows.
    required property FrameEdges reservations

    // A pinned sidebar reserves its width so maximised windows sit beside it
    // rather than under it. It stays reserved while hidden for a fullscreen window
    // so the other windows are not resized back and forth.
    readonly property bool reserveSidebar: Visibilities.sidebarPinned && Config.sidebar.enabled
        && (visibilities.sidebar || visibilities.sidebarSuspended)

    // Follows the sidebar width, but only once a resize drag ends: reserving every
    // step of the drag would resize maximised windows on each frame. The default
    // comes from the bar, which has the screen's tokens.
    property real sidebarWidth

    // Every side reserves whichever is larger: the bar (or the plain border) plus
    // the pinned sidebar, or the full-edge panels sitting on that side.
    readonly property int leftExclusion: Math.max((root.bar.position === "left" ? root.bar.exclusiveZone : Config.border.thickness)
        + (root.reserveSidebar && root.bar.position === "right" ? root.sidebarWidth : 0), root.reservations.left)
    readonly property int topExclusion: Math.max(root.bar.position === "top" ? root.bar.exclusiveZone : Config.border.thickness, root.reservations.top)
    readonly property int rightExclusion: Math.max((root.bar.position === "right" ? root.bar.exclusiveZone : Config.border.thickness)
        + (root.reserveSidebar && root.bar.position !== "right" ? root.sidebarWidth : 0), root.reservations.right)
    readonly property int bottomExclusion: Math.max(root.bar.position === "bottom" ? root.bar.exclusiveZone : Config.border.thickness, root.reservations.bottom)

    readonly property real usableWidth: Math.max(100, root.screen.width - leftExclusion - rightExclusion)
    readonly property real usableHeight: Math.max(100, root.screen.height - topExclusion - bottomExclusion)
    readonly property rect usableArea: Qt.rect(leftExclusion, topExclusion, usableWidth, usableHeight)

    onLeftExclusionChanged: Visibilities.notifyExclusionBoundsChanged(root.screen)
    onTopExclusionChanged: Visibilities.notifyExclusionBoundsChanged(root.screen)
    onRightExclusionChanged: Visibilities.notifyExclusionBoundsChanged(root.screen)
    onBottomExclusionChanged: Visibilities.notifyExclusionBoundsChanged(root.screen)
    onUsableWidthChanged: Visibilities.notifyExclusionBoundsChanged(root.screen)
    onUsableHeightChanged: Visibilities.notifyExclusionBoundsChanged(root.screen)

    Component.onCompleted: Visibilities.registerExclusions(root.screen, root)

    Binding on sidebarWidth {
        value: Visibilities.sidebarWidthFor(root.bar.Tokens.sizes.sidebar.width)
        when: !Visibilities.sidebarResizing
        restoreMode: Binding.RestoreNone
    }

    ExclusionZone {
        anchors.left: true
        exclusiveZone: root.leftExclusion
        Config.screen: root.screen.name
    }

    ExclusionZone {
        anchors.top: true
        exclusiveZone: root.topExclusion
        Config.screen: root.screen.name
    }

    ExclusionZone {
        anchors.right: true
        exclusiveZone: root.rightExclusion
        Config.screen: root.screen.name
    }

    ExclusionZone {
        anchors.bottom: true
        exclusiveZone: root.bottomExclusion
        Config.screen: root.screen.name
    }

    component ExclusionZone: StyledWindow {
        screen: root.screen
        name: "border-exclusion"
        exclusiveZone: Config.border.thickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
        Config.screen: root.screen.name
    }
}
