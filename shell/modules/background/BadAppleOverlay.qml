pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.services

Item {
    id: root

    required property ShellScreen screen

    anchors.fill: parent

    Item {
        id: badAppleMaskContainer

        anchors.fill: parent
        layer.enabled: BadApplePlayer.shouldPlay
        layer.effect: BadApplePlayer.shouldPlay ? badAppleShaderComponent : null

        Rectangle {
            anchors.fill: parent
            color: GlobalConfig.appearance.pitchBlack ? "#000000" : Colours.tPalette.m3surface
            visible: BadApplePlayer.shouldPlay
            opacity: 1.0
        }
    }

    Component {
        id: badAppleShaderComponent

        ShaderEffect {
            property variant mask: ShaderEffectSource {
                sourceItem: badAppleMaskSource.videoOutput
                hideSource: true
            }
            property real videoRatio: {
                if (badAppleMaskSource.videoOutput && badAppleMaskSource.videoOutput.sourceRect.height > 0)
                    return badAppleMaskSource.videoOutput.sourceRect.width / badAppleMaskSource.videoOutput.sourceRect.height;
                return 16.0 / 9.0;
            }
            property real screenRatio: root.width / Math.max(1.0, root.height)

            fragmentShader: "qrc:/shaders/badapple.frag.qsb"
        }
    }

    BadAppleVideo {
        id: badAppleMaskSource

        screenModel: root.screen
        anchors.fill: parent
        opacity: 0.0
    }
}
