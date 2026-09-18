pragma ComponentBehavior: Bound

import org.kde.pipewire as Pipewire
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import Caelestia.Images
import Caelestia.Services
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
    property real saturation: 1.0
    property real brightness: 0.1
    property real contrast: 0.1
    property real radius: Tokens.rounding.medium
    property bool deform: true
    property bool active: GlobalConfig.appearance.ambientColor && !Colours.light
    property real bloomProgress: 0.0
    property bool _thumbExists: root.thumbPath ? IUtils.fileExists(root.thumbPath) : false

    readonly property string thumbPath: root.address ? `${Paths.runtimeDir}/caelestia/window-thumbs/${root.address.startsWith("0x") ? root.address.slice(2) : root.address}.png` : ""
    readonly property real fitted: root.sourceAspect > (root.width / Math.max(1, root.height)) ? root.width / root.sourceAspect : root.height
    readonly property bool hasLiveStream: stream.available

    onAddressChanged: {
        if (root.active && root.address)
            switchAnim.restart();
    }

    onActiveChanged: {
        if (root.active && root.address)
            switchAnim.restart();
    }

    Component.onCompleted: {
        if (root.active && root.address)
            switchAnim.restart();
    }

    opacity: root.active ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    SequentialAnimation {
        id: switchAnim

        NumberAnimation {
            target: root
            property: "bloomProgress"
            to: 0.0
            duration: 500
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "bloomProgress"
            to: 1.0
            duration: 1000
            easing.type: Easing.OutCubic
        }
    }

    WindowStream {
        id: stream

        active: root.active && GlobalConfig.bar.livePreviews
        address: root.address
    }

    Item {
        id: glowContainer

        anchors.fill: parent
        opacity: root.glowOpacity * root.bloomProgress
        transform: Scale {
            origin.x: glowContainer.width / 2
            origin.y: glowContainer.height / 2
            xScale: 1.0 + (root.glowScaleX - 1.0) * root.bloomProgress
            yScale: 1.0 + (root.glowScaleY - 1.0) * root.bloomProgress
        }

        Item {
            id: liveGlowItem

            anchors.fill: parent
            visible: root.hasLiveStream
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: root.blurMax
                saturation: root.saturation
                brightness: root.brightness
                contrast: root.contrast
            }

            Pipewire.PipeWireSourceItem {
                anchors.fill: root.deform ? parent : undefined
                anchors.centerIn: root.deform ? undefined : parent
                width: root.deform ? parent.width : root.fitted * root.sourceAspect
                height: root.deform ? parent.height : root.fitted

                Component.onCompleted: {
                    if ("objectSerial" in this)
                        this.objectSerial = Qt.binding(() => stream.objectSerial);
                    else if ("nodeId" in this)
                        this.nodeId = Qt.binding(() => stream.nodeId);
                }
            }
        }

        Item {
            id: thumbGlowItem

            anchors.fill: parent
            visible: !liveGlowItem.visible && root._thumbExists && thumbImage.status === Image.Ready
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: root.blurMax
                saturation: root.saturation
                brightness: root.brightness
                contrast: root.contrast
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
            visible: !liveGlowItem.visible && !thumbGlowItem.visible
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: root.blurMax
            }

            Rectangle {
                anchors.fill: parent
                radius: root.radius
                color: root.fallbackColor
            }
        }
    }
}
