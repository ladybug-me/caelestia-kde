pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.dashboard.dash as Dash

Item {
    id: root

    required property ShellScreen screen
    required property Item wallpaper
    required property real absX
    required property real absY

    property real shapesScale: Config.background.desktopShapes.scale
    readonly property bool autoHide: Config.background.desktopShapes.autoHide
    readonly property bool windowHidesShapes: Kwin.windowHidesDesktopWidgets(root.screen ? root.screen.name : "", Config.background.visualiser.hideOnAllMonitors)
    readonly property bool shouldHide: autoHide && windowHidesShapes
    readonly property bool isPlaying: Players.active?.isPlaying ?? false

    implicitWidth: 220 * root.shapesScale
    implicitHeight: 220 * root.shapesScale
    width: implicitWidth
    height: implicitHeight

    opacity: (root.isPlaying && !root.shouldHide) ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.SlowEffects
        }
    }

    Behavior on shapesScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on implicitWidth {
        Anim {
            type: Anim.StandardSmall
        }
    }

    Behavior on implicitHeight {
        Anim {
            type: Anim.StandardSmall
        }
    }

    Dash.MediaShapes {
        id: shapes

        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.92
        height: width
        visible: root.visible
        active: root.visible && root.isPlaying
    }
}
