pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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
    readonly property bool windowHidesShapes: {
const wins = Kwin.windowList || [];
const hideOnAll = Config.background.visualiser.hideOnAllMonitors;
const currentScreenName = root.screen ? root.screen.name : "";
const byOutput = Kwin.activeByOutput;
const globalActiveWs = Kwin.activeWsId;

const getActiveWs = outName => {
    if (byOutput && byOutput[outName] !== undefined)
        return byOutput[outName];
    return globalActiveWs;
};

const isWindowMaximizedOnWs = (win, outName) => {
    if (win.minimized === true)
        return false;
    if (!win.maximized && !win.fullscreen)
        return false;
    const winWs = win.workspace?.id ?? -1;
    const activeWs = getActiveWs(outName);
    return activeWs === -1 || winWs === -1 || winWs === activeWs;
};

if (hideOnAll) {
    return wins.some(w => isWindowMaximizedOnWs(w, w.output || currentScreenName));
} else {
    return wins.some(w => (currentScreenName === "" || w.output === currentScreenName) && isWindowMaximizedOnWs(w, currentScreenName));
}
    }
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
