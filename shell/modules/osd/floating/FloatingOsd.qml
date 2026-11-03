pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar as Bar

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

        if (type === "volume" && !GlobalConfig.osd.enableVolume)
            return;
        if (type === "mic" && !GlobalConfig.osd.enableMicrophone)
            return;
        if (type === "brightness" && !GlobalConfig.osd.enableBrightness)
            return;

        root.activeType = type;
        root.activeValue = val;
        root.isMuted = muted;

        if (type === "volume") {
            root.activeTitle = qsTr("Volume");
            root.activeIcon = Icons.getVolumeIcon(val, muted);
        } else if (type === "mic") {
            root.activeTitle = qsTr("Microphone");
            root.activeIcon = Icons.getMicVolumeIcon(val, muted);
        } else if (type === "brightness") {
            root.activeTitle = qsTr("Brightness");
            const step = Math.min(7, Math.max(1, Math.round(val * 6) + 1));
            root.activeIcon = `brightness_${step}`;
        }

        root.shown = true;
        hideTimer.restart();
    }

    anchors.fill: parent
    z: 100

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

        width: item ? item.implicitWidth : implicitWidth
        height: item ? item.implicitHeight : implicitHeight

        anchors.horizontalCenter: (isBottom || isTop || isCenter) ? parent.horizontalCenter : undefined
        anchors.verticalCenter: (isRight || isLeft || isCenter) ? parent.verticalCenter : undefined
        anchors.verticalCenterOffset: isCenter ? (root.shown ? 0 : 20) : 0

        anchors.top: isTop ? parent.top : undefined
        anchors.topMargin: isTop ? ((root.bar.position === "top" ? root.bar.clampedThickness : 0) + (root.shown ? 36 : 16)) : 0

        anchors.bottom: isBottom ? parent.bottom : undefined
        anchors.bottomMargin: isBottom ? ((root.bar.position === "bottom" ? root.bar.clampedThickness : 0) + (root.shown ? 44 : 24)) : 0

        anchors.right: isRight ? parent.right : undefined
        anchors.rightMargin: isRight ? ((root.bar.position === "right" ? root.bar.clampedThickness : 0) + (root.shown ? 36 : 16)) : 0

        anchors.left: isLeft ? parent.left : undefined
        anchors.leftMargin: isLeft ? ((root.bar.position === "left" ? root.bar.clampedThickness : 0) + (root.shown ? 36 : 16)) : 0

        opacity: 1 - root.offsetScale
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

        Behavior on anchors.bottomMargin {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on anchors.topMargin {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on anchors.rightMargin {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on anchors.leftMargin {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on anchors.verticalCenterOffset {
            Anim {
                type: Anim.Emphasized
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
