pragma ComponentBehavior: Bound

import QtQuick
import "performance"
import Caelestia.Config
import qs.components
import qs.services

// System stats entry: shows the stat pill picked in Nexus, the full data lives
// in the popout. Falls back to a single icon when no pill is picked.
StyledRect {
    id: root

    required property var popouts

    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"
    readonly property string pill: String(Config.bar.performance?.pill ?? "").trim().toLowerCase()

    readonly property var pillComponent: {
        switch (root.pill) {
        case "cpu":
            return cpuPill;
        case "gpu":
            return gpuPill;
        case "memory":
            return memoryPill;
        case "storage":
            return storagePill;
        case "network":
            return networkPill;
        case "battery":
            return batteryPill;
        default:
            return null;
        }
    }

    implicitWidth: isHorizontal ? Math.max(Tokens.sizes.bar.innerWidth, pillLoader.implicitWidth) : Tokens.sizes.bar.innerWidth
    implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : Math.max(Tokens.sizes.bar.innerWidth, pillLoader.implicitHeight)

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0)
    radius: Tokens.rounding.full

    visible: enabled

    Loader {
        id: pillLoader

        anchors.centerIn: parent
        // Outside a layout the loader keeps zero size, so the pill needs to be
        // sized from the component it loaded.
        width: implicitWidth
        height: implicitHeight
        sourceComponent: root.pillComponent
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: "speed"
        color: Colours.palette.m3onSurface
        fontStyle: Tokens.font.icon.builders.medium.build()

        visible: root.pillComponent === null
    }

    // The Loader needs real components, not bare types.
    Component {
        id: cpuPill

        PerfCpu {}
    }

    Component {
        id: gpuPill

        PerfGpu {}
    }

    Component {
        id: memoryPill

        PerfMemory {}
    }

    Component {
        id: storagePill

        PerfStorage {}
    }

    Component {
        id: networkPill

        PerfNetwork {}
    }

    Component {
        id: batteryPill

        PerfBattery {}
    }

    MouseArea {
        id: contextArea

        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            root.popouts.currentName = "performancecontext";
            root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
            root.popouts.hasCurrent = true;
            mouse.accepted = true;
        }
    }
}
