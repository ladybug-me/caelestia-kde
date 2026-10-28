pragma ComponentBehavior: Bound

import QtQuick
import "performance"
import Caelestia.Config
import qs.components
import qs.services

// System stats entry: shows the stat pill picked in Nexus, the full data lives
// in the popout. The widget style picks between the speed icon and a pill;
// the specific per-component pills follow the global pill style instead.
StyledRect {
    id: root

    required property var popouts

    property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    readonly property string pill: String(Config.bar.performance?.pill ?? "").trim().toLowerCase()
    readonly property string widgetStyle: String(Config.bar.performance?.widgetStyle ?? "classic").trim().toLowerCase()
    readonly property bool widgetShowText: typeof Config.bar.performance !== "undefined" && Config.bar.performance.widgetShowText !== undefined ? Config.bar.performance.widgetShowText : true
    // An empty stored pill is a leftover from before the widget had its own
    // style: it behaves like the icon style and migrates on load.
    readonly property string effectivePill: root.pill === "" ? "cpu" : root.pill
    readonly property bool effectiveIcon: root.widgetStyle === "icon" || root.pill === ""
    readonly property string widgetPillStyle: root.widgetStyle === "compact" ? "compact" : "classic"

    readonly property var pillComponent: {
        switch (root.effectivePill) {
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

    // Keyed on effectiveIcon instead of the loader's implicit size: when the
    // pill unloads the loader can keep reporting its old size until the
    // shell restarts, leaving the icon centered in the pill's old space.
    implicitWidth: isHorizontal ? (root.effectiveIcon ? Tokens.sizes.bar.innerWidth : Math.max(Tokens.sizes.bar.innerWidth, pillLoader.implicitWidth)) : Tokens.sizes.bar.innerWidth
    implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : (root.effectiveIcon ? Tokens.sizes.bar.innerWidth : Math.max(Tokens.sizes.bar.innerWidth, pillLoader.implicitHeight))

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0)
    radius: Tokens.rounding.full

    visible: enabled

    Component.onCompleted: {
        if (root.pill === "" && root.widgetStyle === "classic") {
            GlobalConfig.bar.performance.pill = "cpu";
            GlobalConfig.bar.performance.widgetStyle = "icon";
            GlobalConfig.save();
        }
    }

    Loader {
        id: pillLoader

        anchors.centerIn: parent
        // Outside a layout the loader keeps zero size, so the pill needs to be
        // sized from the component it loaded.
        width: implicitWidth
        height: implicitHeight
        sourceComponent: root.effectiveIcon ? null : root.pillComponent
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: "speed"
        color: Colours.palette.m3onSurface
        fontStyle: Tokens.font.icon.builders.medium.build()

        visible: root.effectiveIcon
    }

    // The Loader needs real components, not bare types. Each pill gets the
    // widget's own text and style overrides so the specific pills keep
    // following the global ones.
    Component {
        id: cpuPill

        PerfCpu {
            isHorizontal: root.isHorizontal
            showText: root.widgetShowText
            pillStyle: root.widgetPillStyle
        }
    }

    Component {
        id: gpuPill

        PerfGpu {
            isHorizontal: root.isHorizontal
            showText: root.widgetShowText
            pillStyle: root.widgetPillStyle
        }
    }

    Component {
        id: memoryPill

        PerfMemory {
            isHorizontal: root.isHorizontal
            showText: root.widgetShowText
            pillStyle: root.widgetPillStyle
        }
    }

    Component {
        id: storagePill

        PerfStorage {
            isHorizontal: root.isHorizontal
            showText: root.widgetShowText
            pillStyle: root.widgetPillStyle
        }
    }

    Component {
        id: networkPill

        PerfNetwork {
            isHorizontal: root.isHorizontal
            showText: root.widgetShowText
            pillStyle: root.widgetPillStyle
        }
    }

    Component {
        id: batteryPill

        PerfBattery {
            isHorizontal: root.isHorizontal
            showText: root.widgetShowText
            pillStyle: root.widgetPillStyle
        }
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
