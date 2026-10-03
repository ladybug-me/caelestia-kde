pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components

Item {
    id: root

    required property DrawerVisibilities visibilities
    property var popouts
    property var utilities
    // Set while a popout pushes the sidebar; its height is already animated.
    property bool followsPopout: false
    readonly property Props props: Props {}
    readonly property bool shouldBeActive: visibilities.sidebar && Config.sidebar.enabled && !visibilities.overview
    property bool keepLoaded: false
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.leftMargin: Config.bar.position === "right" ? (-implicitWidth - 5) * offsetScale : 0
    anchors.rightMargin: Config.bar.position !== "right" ? (-implicitWidth - 5) * offsetScale : 0
    implicitWidth: Tokens.sizes.sidebar.width
    opacity: 1 - offsetScale

    Connections {
        function onKeepLoadedChanged(): void {
            root.keepLoaded = content.item ? content.item.keepLoaded : false;
        }

        target: content.item
        ignoreUnknownSignals: true
    }
    Behavior on offsetScale {
        Anim {}
    }
    // Animating on top of the popout's own height animation makes the edge lag
    // behind it, leaving a gap or an overlap while switching popouts.
    Behavior on anchors.bottomMargin {
        enabled: !root.followsPopout

        Anim {}
    }
    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.large
        anchors.margins: CUtils.clamp(anchors.leftMargin - Config.border.thickness, 0, anchors.leftMargin)
        anchors.bottomMargin: 0
        active: root.shouldBeActive || root.visible || root.keepLoaded
        sourceComponent: Content {
            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins
            props: root.props
            visibilities: root.visibilities
            popouts: root.popouts
            utilities: root.utilities
        }
    }
}
