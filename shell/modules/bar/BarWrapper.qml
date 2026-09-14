pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    Config.screen: screen.name
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    readonly property string position: Config.bar.position
    readonly property real barScale: Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0)
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Math.round(Tokens.sizes.bar.innerWidth * barScale) + padding * 2
    readonly property bool dodgeEnabled: Config.bar.dodgeWindows && Config.bar.persistent && !disabled
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
    // Touch the tracked QML properties here so QML re-evaluates this binding
    // whenever window data, focus, or workspace changes — hasWindowOverlapping()
    // is a plain JS function and QML does not track what it reads internally.
    readonly property var _dodgeWatchWindowList: (true) ? Kwin.windowList : null
    readonly property var _dodgeWatchActiveWindow: (true) ? Kwin.activeWindow : null
    readonly property int _dodgeWatchActiveId: (true) ? Kwin.activeWsId : -1
    // activeByOutput tracks per-screen workspace changes independently — needed
    // so switching ws on an unfocused screen still re-evaluates dodge on that bar.
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

    // Treat a dodging bar as non-persistent: it stays out of the way but is
    // still reachable through the hover edge and the usual toggles.
    readonly property bool keptOpen: Config.bar.persistent && !dodging
    // Reserving space while dodging would keep windows off the bar, so nothing
    // would ever overlap it and the mode would never engage.
    readonly property int exclusiveZone: !disabled && !dodgeEnabled && (Config.bar.persistent || visibilities.bar) ? contentWidth : Config.border.thickness
    // What the desktop layer (icons, the clock, the audio visualiser) should
    // leave clear so its own content doesn't render under the bar. This is
    // exclusiveZone without the dodge carve-out: dodging drops the reported
    // zone to (near) nothing so KWin will let windows slide under the bar,
    // which is exactly what makes overlap detection possible, but the bar is
    // still visually there whenever it isn't actively dodging, and desktop
    // content needs to keep leaving room for it regardless of what KWin was
    // told for window-placement purposes.
    readonly property int visualThickness: !disabled && (Config.bar.persistent || visibilities.bar) ? contentWidth : Config.border.thickness
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
        }
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
}
