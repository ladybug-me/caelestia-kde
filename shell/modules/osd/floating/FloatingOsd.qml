pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar as Bar
import qs.modules.osd as Osd

Item {
    id: root

    required property ShellScreen screen
    required property Bar.BarWrapper bar
    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    property bool shown: false
    property real offsetScale: shown ? 0 : 1
    readonly property bool active: shown || offsetScale < 0.99
    readonly property alias panelItem: contentLoader
    readonly property alias contentLoader: contentLoader
    property real activeValue: 0
    property bool isMuted: false
    property string activeType: "volume"
    property string activeIcon: "volume_up"
    property string activeTitle: qsTr("Volume")

    function trigger(type: string, val: real, muted: bool): void {
        const osdStyle = GlobalConfig.osd.style;
        if (!GlobalConfig.osd.enabled || osdStyle === "default")
            return;

        if (!osdFunctions.isEnabled(type))
            return;

        root.activeType = type;
        root.activeValue = val;
        root.isMuted = muted;
        root.activeTitle = osdFunctions.getTitle(type);
        root.activeIcon = osdFunctions.getIcon(type, val, muted);

        root.shown = true;
        hideTimer.restart();
    }

    anchors.fill: parent
    z: 100

    Osd.Content.Functions {
        id: osdFunctions
    }

    Behavior on offsetScale {
        Anim {
            type: Anim.Emphasized
        }
    }

    Connections {
        function onVolumeChanged(): void {
            root.trigger("volume", Audio.volume, Audio.muted);
        }

        function onMutedChanged(): void {
            root.trigger("volume", Audio.volume, Audio.muted);
        }

        function onSourceVolumeChanged(): void {
            root.trigger("mic", Audio.sourceVolume, Audio.sourceMuted);
        }

        function onSourceMutedChanged(): void {
            root.trigger("mic", Audio.sourceVolume, Audio.sourceMuted);
        }

        target: Audio
    }

    Connections {
        function onBrightnessChanged(): void {
            root.trigger("brightness", root.monitor?.effectiveBrightness ?? 0, false);
        }

        target: root.monitor
    }

    Timer {
        id: hideTimer

        interval: GlobalConfig.osd.hideDelay
        onTriggered: root.shown = false
    }

    Loader {
        id: contentLoader

        readonly property string pos: GlobalConfig.osd.position
        readonly property bool isBottom: pos === "bottom" || (!pos && pos !== "top" && pos !== "center" && pos !== "right" && pos !== "left")
        readonly property bool isTop: pos === "top"
        readonly property bool isCenter: pos === "center"
        readonly property bool isRight: pos === "right"
        readonly property bool isLeft: pos === "left"
        readonly property string vAnchor: "none"
        readonly property string hAnchor: "none"
        readonly property real offsetScale: root.offsetScale
        readonly property real slideDistanceY: (height > 0 ? height : 60) + 60
        readonly property real slideDistanceX: (width > 0 ? width : 200) + 60

        width: item ? item.implicitWidth : implicitWidth
        height: item ? item.implicitHeight : implicitHeight

        x: {
            if (isLeft) {
                const barOffset = root.bar.position === "left" ? root.bar.clampedThickness : 0;
                return barOffset + 36 - 16 * root.offsetScale;
            }
            if (isRight) {
                const barOffset = root.bar.position === "right" ? root.bar.clampedThickness : 0;
                return parent.width - width - (barOffset + 36 - 16 * root.offsetScale);
            }
            return (parent.width - width) / 2;
        }

        y: {
            if (isTop) {
                const barOffset = root.bar.position === "top" ? root.bar.clampedThickness : 0;
                return barOffset + 36 - 16 * root.offsetScale;
            }
            if (isBottom) {
                const barOffset = root.bar.position === "bottom" ? root.bar.clampedThickness : 0;
                return parent.height - height - (barOffset + 44 - 16 * root.offsetScale);
            }
            return (parent.height - height) / 2 + 16 * root.offsetScale;
        }

        scale: Math.max(0, 1 - root.offsetScale)
        opacity: Math.max(0, Math.min(1, 1 - root.offsetScale))
        visible: root.active

        sourceComponent: {
            switch (GlobalConfig.osd.style) {
                case "pill": return pillComp;
                case "compact": return compactComp;
                case "radial": return radialComp;
                case "card": return cardComp;
                case "bar": return barComp;
                default: return null;
            }
        }
    }

    Component {
        id: pillComp

        PillOsd {
            value: root.activeValue
            isMuted: root.isMuted
            icon: root.activeIcon
            title: root.activeTitle
            type: root.activeType
        }
    }

    Component {
        id: compactComp

        CompactOsd {
            value: root.activeValue
            isMuted: root.isMuted
            icon: root.activeIcon
            title: root.activeTitle
            type: root.activeType
        }
    }

    Component {
        id: radialComp

        RadialOsd {
            value: root.activeValue
            isMuted: root.isMuted
            icon: root.activeIcon
            title: root.activeTitle
            type: root.activeType
        }
    }

    Component {
        id: cardComp

        CardOsd {
            value: root.activeValue
            isMuted: root.isMuted
            icon: root.activeIcon
            title: root.activeTitle
            type: root.activeType
        }
    }

    Component {
        id: barComp

        MinimalBarOsd {
            value: root.activeValue
            isMuted: root.isMuted
            icon: root.activeIcon
            title: root.activeTitle
            type: root.activeType
        }
    }
}
