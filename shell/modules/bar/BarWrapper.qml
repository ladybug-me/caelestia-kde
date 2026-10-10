pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.bar.popouts as BarPopouts
import qs.modules.drawers.blur as Blur

Item {
    id: root

    required property ShellScreen screen
    Config.screen: screen.name
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    // Null means the legacy primary bar (global Config.bar keys). A barDef
    // object makes this an overlay bar: own position/widgets/visibility,
    // floating without an exclusive zone so the primary bar keeps owning
    // the screen edges and all the border geometry built around it.
    property var barDef: null
    readonly property bool isOverlay: root.barDef !== null && root.barDef !== undefined
    readonly property string effectivePosition: root.isOverlay && root.barDef.position ? root.barDef.position : Config.bar.position
    readonly property bool effectivePersistent: root.isOverlay && root.barDef.persistent !== undefined ? root.barDef.persistent : Config.bar.persistent
    readonly property bool disabled: root.isOverlay ? false : Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    // Separator offset for stacked overlay panels (passed from ContentWindow)
    property int sepOffset: -1
    // Dock mode: floating centered segment rendered with the shared frame
    // material, so it reads as frame rather than as a card on top of it.
    property bool docked: false
    property var frameGroup: null
    readonly property string position: root.effectivePosition
    readonly property real barScale: Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0)
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Math.round(Tokens.sizes.bar.innerWidth * barScale) + padding * 2
    readonly property bool dodgeEnabled: Config.bar.dodgeWindows && Config.bar.persistent && !disabled && !root.isOverlay
    // The strip the bar occupies, in the absolute multi-monitor coordinates
    // KWin reports window geometry in — hence the screen origin offset.
    readonly property rect dodgeRect: {
        const ox = screen.x ?? 0;
        const oy = screen.y ?? 0;
        if (position === "top")
            return Qt.rect(ox, oy, screen.width, contentWidth);
        if (position === "bottom")
            return Qt.rect(ox, oy + screen.height - contentWidth, screen.width, contentWidth);
        if (position === "left")
            return Qt.rect(ox, oy, contentWidth, screen.height);
        return Qt.rect(ox + screen.width - contentWidth, oy, contentWidth, screen.height);
    }
    readonly property var _dodgeWatchWindowList: (true) ? Kwin.windowList : null
    readonly property var _dodgeWatchActiveWindow: (true) ? Kwin.activeWindow : null
    readonly property int _dodgeWatchActiveId: (true) ? Kwin.activeWsId : -1
    readonly property var _dodgeWatchActiveByOutput: (true) ? Kwin.activeByOutput : null
    readonly property bool dodging: {
        // Reading these tracked props here makes QML invalidate this binding
        // when windowList, activeWindow, activeId, or per-screen workspace changes.
        void _dodgeWatchWindowList;
        void _dodgeWatchActiveWindow;
        void _dodgeWatchActiveId;
        void _dodgeWatchActiveByOutput;
        return dodgeEnabled && Kwin.hasWindowOverlapping(screen.name, dodgeRect.x, dodgeRect.y, dodgeRect.width, dodgeRect.height, Config.bar.dodgeFocusedOnly);
    }

    readonly property bool keptOpen: root.effectivePersistent && !dodging
    readonly property int exclusiveZone: root.isOverlay ? Config.border.thickness : (!disabled && !dodgeEnabled && (Config.bar.persistent || visibilities.bar) ? contentWidth : Config.border.thickness)
    readonly property int visualThickness: root.isOverlay ? Config.border.thickness : (!disabled && (Config.bar.persistent || visibilities.bar) ? contentWidth : Config.border.thickness)
    readonly property bool shouldBeVisible: !fullscreen && !disabled && !visibilities.overview && (keptOpen || visibilities.bar || isHovered)
    property bool isHovered
    readonly property bool isHorizontal: root.position === "top" || root.position === "bottom"
    readonly property int clampedThickness: Math.max(Config.border.minThickness, isHorizontal ? implicitHeight : implicitWidth)
    readonly property int clampedWidth: isHorizontal ? root.width : clampedThickness
    readonly property int clampedHeight: isHorizontal ? clampedThickness : root.height

    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }
    function checkPopout(y: real): void {
        (content.item as Bar)?.checkPopout(y);
    }
    function resetHover(): void {
        (content.item as Bar)?.resetHover();
    }
    function handleWheel(y: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(y, angleDelta);
    }

    clip: true
    visible: isHorizontal ? height > Config.border.thickness : width > Config.border.thickness
    implicitWidth: isHorizontal ? 0 : (fullscreen ? 0 : Config.border.thickness)
    implicitHeight: isHorizontal ? (fullscreen ? 0 : Config.border.thickness) : 0
    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            target: root
            implicitWidth: root.isHorizontal ? 0 : root.contentWidth
            implicitHeight: root.isHorizontal ? root.contentWidth : 0
        }
    }
    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: root.isHorizontal ? "implicitHeight" : "implicitWidth"
                type: Anim.DefaultSpatial
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: root.isHorizontal ? "implicitHeight" : "implicitWidth"
                type: Anim.Emphasized
            }
        }
    ]

    Component {
        id: horizontalBar

        Bar {
            anchors.fill: parent
            anchors.leftMargin: root.padding
            anchors.rightMargin: root.padding
            width: root.contentWidth
            screen: root.screen
            visibilities: root.visibilities
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
            barDef: root.barDef
        }
    }
    Component {
        id: verticalBar

        Bar {
            anchors.fill: parent
            anchors.topMargin: root.padding
            anchors.bottomMargin: root.padding
            screen: root.screen
            visibilities: root.visibilities
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
            barDef: root.barDef
        }
    }
    // Dock segment: same frame material, merging into the edge it hangs
    // from (square on the frame side, rounded on the outer side).
    BlobRect {
        anchors.fill: parent
        visible: root.docked && root.isOverlay && root.frameGroup !== null
        group: root.frameGroup
        radius: Config.border.rounding
        topLeftRadius: (root.position === "bottom" || root.position === "right") ? Config.border.rounding : 0
        topRightRadius: (root.position === "bottom" || root.position === "left") ? Config.border.rounding : 0
        bottomLeftRadius: (root.position === "top" || root.position === "right") ? Config.border.rounding : 0
        bottomRightRadius: (root.position === "top" || root.position === "left") ? Config.border.rounding : 0
        deformScale: (GlobalConfig.appearance.blurMask || !GlobalConfig.appearance.transparency.enabled) ? ((0.1 * Config.appearance.deformScale) / 10000) : 0
        Config.screen: root.screen.name
    }

    Loader {
        id: content

        active: true
        sourceComponent: root.isHorizontal ? horizontalBar : verticalBar
        width: root.isHorizontal ? root.width : root.contentWidth
        height: root.isHorizontal ? root.contentWidth : root.height
        states: [
            State {
                name: "left"
                when: root.position === "left"

                AnchorChanges {
                    target: content
                    anchors.left: undefined
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: undefined
                }
            },
            State {
                name: "right"
                when: root.position === "right"

                AnchorChanges {
                    target: content
                    anchors.left: parent.left
                    anchors.right: undefined
                    anchors.top: parent.top
                    anchors.bottom: undefined
                }
            },
            State {
                name: "top"
                when: root.position === "top"

                AnchorChanges {
                    target: content
                    anchors.left: parent.left
                    anchors.right: undefined
                    anchors.top: undefined
                    anchors.bottom: parent.bottom
                }
            },
            State {
                name: "bottom"
                when: root.position === "bottom"

                AnchorChanges {
                    target: content
                    anchors.left: parent.left
                    anchors.right: undefined
                    anchors.top: parent.top
                    anchors.bottom: undefined
                }
            }
        ]
    }

    // Separator line between stacked overlay panels (no background - the frame IS the panel)
    Rectangle {
        visible: root.isOverlay && root.sepOffset !== undefined && root.sepOffset >= 0
        color: Colours.palette.m3outline
        z: 0
        width: root.isHorizontal ? parent.width : 1
        height: root.isHorizontal ? 1 : parent.height
        anchors.top: root.isHorizontal ? parent.top : undefined
        anchors.bottom: root.isHorizontal ? undefined : undefined
        anchors.left: !root.isHorizontal ? parent.left : undefined
        anchors.right: !root.isHorizontal ? undefined : undefined
        x: root.isHorizontal ? 0 : root.sepOffset
        y: root.isHorizontal ? root.sepOffset : 0
    }
    // Overlay bars get the same blur as the primary bar so they match the frame
    // (BlurMask doesn't support visible, conditionally create via Loader)
    Loader {
        visible: root.isOverlay
        active: root.isOverlay
        sourceComponent: Blur.BlurMask {
            target: content.item
            contentItem: root.contentItem
            blurOffsetTop: root.blurOffsetTop
            blurOffsetBottom: root.blurOffsetBottom
            blurOffsetLeft: root.blurOffsetLeft
            blurOffsetRight: root.blurOffsetRight
            vAnchor: root.vAnchor
            hAnchor: root.hAnchor
        }
    }
}
