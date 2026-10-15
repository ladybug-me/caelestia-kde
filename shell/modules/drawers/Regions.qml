pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win
    required property var overlayExtents
    required property var topDockDef
    readonly property real borderThickness: Config.border.thickness
    readonly property real clampedThickness: Config.border.clampedThickness
    // Overlay extents widen the input area, floored at the screen edges:
    // negative coordinates break the region combination downstream.
    readonly property real maskX: Math.max(0, barLeftWidth + win.dragMaskPadding - overlayExtents.left)
    readonly property real maskY: Math.max(0, barTopHeight + win.dragMaskPadding - overlayExtents.top)
    readonly property real barLeftWidth: bar.position === "left" ? bar.clampedThickness : clampedThickness
    readonly property real barRightWidth: bar.position === "right" ? bar.clampedThickness : clampedThickness
    readonly property real barTopHeight: bar.position === "top" ? bar.clampedThickness : clampedThickness
    readonly property real barBottomHeight: bar.position === "bottom" ? bar.clampedThickness : clampedThickness
    // A closed panel's input region must be at least as deep as its hover trigger,
    // otherwise the pointer never reaches the area Interactions tests against.

    function edgeExtent(hoverThickness: real): real {
        return Math.max(borderThickness, hoverThickness);
    }

    x: maskX
    y: maskY
    width: win.width - barLeftWidth - barRightWidth - win.dragMaskPadding * 2 + overlayExtents.left + overlayExtents.right - (maskX - (barLeftWidth + win.dragMaskPadding - overlayExtents.left))
    height: win.height - barTopHeight - barBottomHeight - win.dragMaskPadding * 2 + overlayExtents.top + overlayExtents.bottom - (maskY - (barTopHeight + win.dragMaskPadding - overlayExtents.top))
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.edgeExtent(root.Config.dashboard.hoverThickness)
    }
    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.edgeExtent(root.Config.launcher.hoverThickness)
    }
    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: root.bar.position === "right" ? 0 : root.win.width - sessionRegion.width
        width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width
    }
    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.bar.position === "right" ? 0 : root.win.width - sidebarRegion.width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }
    R {
        id: osdRegion

        panel: root.panels.osdWrapper
        x: root.bar.position === "right" ? 0 : root.win.width - osdRegion.width
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.edgeExtent(root.Config.osd.hoverThickness) + sessionRegion.width
    }
    R {
        panel: root.panels.notifications
    }
    R {
        panel: root.panels.utilities
        y: root.bar.position === "bottom" ? 0 : root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.edgeExtent(root.Config.utilities.hoverThickness)
    }
    // Overlay panel bands need explicit input like drawers get: the root
    // region excludes everything and children add back what the shell
    // needs, so without this the panel area never receives pointer events.
    // Top dock segments only cover their centered span.
    Region {
        x: root.topDockDef ? (root.win.width - root.win.width * Math.max(10, Math.min(100, root.topDockDef.lengthPercent ?? 100)) / 100) / 2 : 0
        y: 0
        width: root.topDockDef ? root.win.width * Math.max(10, Math.min(100, root.topDockDef.lengthPercent ?? 100)) / 100 : root.win.width
        height: root.topDockDef ? root.bar.contentWidth : Math.max(0, root.overlayExtents.top)
        intersection: Intersection.Subtract
    }
    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }
    Region {
        x: 0; y: 0
        width: (root.Config.overview.enabled && root.Config.overview.hoverTopLeft) ? root.Config.overview.hoverThickness : 0
        height: root.Config.overview.hoverThickness
        intersection: Intersection.Subtract
    }
    Region {
        x: root.win.width - root.Config.overview.hoverThickness; y: 0
        width: (root.Config.overview.enabled && root.Config.overview.hoverTopRight) ? root.Config.overview.hoverThickness : 0
        height: root.Config.overview.hoverThickness
        intersection: Intersection.Subtract
    }
    Region {
        x: 0; y: root.win.height - root.Config.overview.hoverThickness
        width: (root.Config.overview.enabled && root.Config.overview.hoverBottomLeft) ? root.Config.overview.hoverThickness : 0
        height: root.Config.overview.hoverThickness
        intersection: Intersection.Subtract
    }
    Region {
        x: root.win.width - root.Config.overview.hoverThickness; y: root.win.height - root.Config.overview.hoverThickness
        width: (root.Config.overview.enabled && root.Config.overview.hoverBottomRight) ? root.Config.overview.hoverThickness : 0
        height: root.Config.overview.hoverThickness
        intersection: Intersection.Subtract
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.panels.leftMargin
        y: panel.y + root.panels.topMargin
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
    Config.screen: win.screen.name
}
