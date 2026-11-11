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
    property bool keepAlive: false

    readonly property bool avatarVisible: root.visible && (content.item?.showAvatar ?? false)
    readonly property int avatarSize: content.item?.avatarSize ?? 0

    signal closed()

    onOffsetScaleChanged: {
        if (offsetScale >= 1 && !shouldBeActive)
            closed();
    }
    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => content.implicitHeight);
        } else
            implicitHeight = implicitHeight;
    }
    // Keep the clip while the panel slides away, but not while it is open: the
    // profile picture deliberately overhangs the top edge of the card.
    clip: Config.bar.position === "bottom" && !root.avatarVisible
    visible: offsetScale < 1
    anchors.bottomMargin: (Config.bar.position === "bottom" ? 0 : -implicitHeight - 5) * offsetScale
    height: Config.bar.position === "bottom" ? implicitHeight * (1 - offsetScale) : implicitHeight
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630
    opacity: 1 - offsetScale
    Component.onCompleted: Qt.callLater(() => Apps)

    Timer {
        running: Config.launcher.enabled && !root.keepAlive
        interval: 1500

        onTriggered: root.keepAlive = true
    }

    Behavior on offsetScale {
        enabled: !visibilities.skipLauncherAnim

        Anim {}
    }
    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        active: root.shouldBeActive || root.visible || root.keepAlive
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
