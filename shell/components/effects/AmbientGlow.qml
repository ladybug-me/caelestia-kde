pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import Caelestia.Images
import qs.components
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string address: ""
    property url fallbackIcon: ""
    property color fallbackColor: Colours.palette.m3primary
    property real sourceAspect: 16 / 9
    property real glowScaleX: 2.0
    property real glowScaleY: 2.0
    property int blurMax: 96
    property real glowOpacity: GlobalConfig.appearance.ambientOpacity
    property real saturation: 0.9
    property real colorization: 0.35
    property real radius: Tokens.rounding.medium
    property bool deform: true
    property bool active: GlobalConfig.appearance.ambientColor
    property bool _thumbExists: root.thumbPath ? IUtils.fileExists(root.thumbPath) : false

    readonly property string thumbPath: root.address ? `${Paths.runtimeDir}/caelestia/window-thumbs/${root.address.startsWith("0x") ? root.address.slice(2) : root.address}.png` : ""
    readonly property real fitted: root.sourceAspect > (root.width / Math.max(1, root.height)) ? root.width / root.sourceAspect : root.height
    readonly property color glowColor: {
        const dominant = analyser.dominantColour;
        const hasDominant = dominant.a > 0;
        return root.extractGlowColor(hasDominant ? dominant : root.fallbackColor, !hasDominant);
    }

    // Maps the dominant color to the perceptual glow sweet spot (L 0.45–0.65, S ~max).
    function extractGlowColor(col: color, isFallback: bool): color {
        const h = col.hslHue >= 0 ? col.hslHue : 0;
        const rawS = col.hslSaturation;
        const rawL = col.hslLightness;

        if (!isFallback && rawS < 0.12) {
            return root.extractGlowColor(root.fallbackColor, true);
        }

        const s = Math.min(1.0, rawS < 0.5 ? rawS * 1.8 + 0.15 : rawS * 1.2);

        let l;
        if (rawL < 0.15) {
            l = 0.45;
        } else if (rawL < 0.40) {
            l = 0.45 + (rawL - 0.15) / 0.25 * 0.10;
        } else if (rawL < 0.60) {
            l = 0.55 + (rawL - 0.40) / 0.20 * 0.05;
        } else if (rawL < 0.80) {
            l = 0.60 + (rawL - 0.60) / 0.20 * 0.05;
        } else {
            l = 0.60;
        }

        return Qt.hsla(h, s, l, 1.0);
    }

    opacity: root.active ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Item {
        id: glowContainer

        anchors.fill: parent
        opacity: root.glowOpacity
        transform: Scale {
            origin.x: glowContainer.width / 2
            origin.y: glowContainer.height / 2
            xScale: root.glowScaleX
            yScale: root.glowScaleY
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Item {
            id: thumbGlowItem

            anchors.fill: parent
            visible: root._thumbExists && thumbImage.status === Image.Ready
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: root.blurMax
                saturation: root.saturation
                colorization: root.colorization
                colorizationColor: root.glowColor
            }

            CachingImage {
                id: thumbImage

                anchors.fill: root.deform ? parent : undefined
                anchors.centerIn: root.deform ? undefined : parent
                width: root.deform ? parent.width : root.fitted * root.sourceAspect
                height: root.deform ? parent.height : root.fitted
                path: root._thumbExists ? root.thumbPath : ""
                fillMode: root.deform ? Image.Stretch : Image.PreserveAspectFit
                asynchronous: true
            }
        }

        Item {
            id: fallbackGlowItem

            anchors.fill: parent
            visible: !thumbGlowItem.visible
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: root.blurMax
            }

            Rectangle {
                anchors.fill: parent
                radius: root.radius
                color: root.glowColor
            }
        }
    }

    ImageAnalyser {
        id: analyser

        source: root._thumbExists ? root.thumbPath : (root.fallbackIcon.toString().startsWith("file://") ? root.fallbackIcon.toString() : "")
    }
}
