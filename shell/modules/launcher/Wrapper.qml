pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property var panels
    Config.screen: root.screen.name
    readonly property real maxWidth: screen.width
    readonly property bool shouldBeActive: visibilities.launcher && Config.launcher.enabled && !visibilities.overview
    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 + Tokens.padding.extraLarge;
        if (visibilities.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }
    property real offsetScale: shouldBeActive ? 0 : 1
    // Build the content once, shortly after startup, instead of inside the frame
    // that handles the click. The loader below is synchronous, so the first open
    // constructs Content -> ContentList -> the app list/browser on the GUI
    // thread; nothing is painted until that finishes, so the open animation only
    // starts after it. It is paid on every open, because `visible` going false
    // unloads the content again once the close animation reaches offsetScale 1.
    property bool warmWanted: false
    // Whether the warm-up load is asynchronous, kept separate so it can be
    // flipped to true before `active`: both bindings depend on the same property
    // and their evaluation order is not defined, so the warm-up could otherwise
    // end up loading synchronously and defeat the point.
    property bool warmAsync: false

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => content.implicitHeight);
        } else
            implicitHeight = implicitHeight;
    }
    clip: Config.bar.position === "bottom"
    visible: offsetScale < 1
    anchors.bottomMargin: (Config.bar.position === "bottom" ? 0 : -implicitHeight - 5) * offsetScale
    height: Config.bar.position === "bottom" ? implicitHeight * (1 - offsetScale) : implicitHeight
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630
    opacity: 1 - offsetScale
    Component.onCompleted: Qt.callLater(() => Apps)

    Timer {
        running: !root.warmWanted
        interval: 1500

        onTriggered: {
            root.warmAsync = true;
            root.warmWanted = true;
        }
    }
    Behavior on offsetScale {
        enabled: !visibilities.skipLauncherAnim

        Anim {}
    }
    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        // The warm-up load is incubated off the GUI thread and the item is kept
        // from then on; a click that arrives before the warm-up has run still
        // loads synchronously, so the drawer can never come up empty.
        asynchronous: root.warmAsync
        active: root.shouldBeActive || root.visible || root.warmWanted
        sourceComponent: Component {
            Content {
                visibilities: root.visibilities
                panels: root.panels
                maxWidth: root.maxWidth
                maxHeight: root.maxHeight
            }
        }
    }
}
