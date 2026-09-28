pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import Caelestia.Components
import Caelestia.Services
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property Item wallpaper
    readonly property bool windowHidesVisualiser: Kwin.windowHidesDesktopWidgets(root.screen ? root.screen.name : "", Config.background.visualiser.hideOnAllMonitors)
    readonly property bool shouldBeActive: Config.background.visualiser.enabled && !(GameMode.enabled && GlobalConfig.utilities.gameMode.disableVisualizer) && (!Config.background.visualiser.autoHide || !windowHidesVisualiser)
    property real offset: shouldBeActive ? 0 : screen.height * 0.2
    readonly property var barWrapper: {
        let name = root.screen ? root.screen.name : undefined;
        let bar = name ? Visibilities.bars.get(name) : undefined;
        return bar;
    }
    readonly property int barExclusiveZone: barWrapper ? barWrapper.visualThickness : 0
    readonly property real visualiserSpacing: Tokens.spacing.small * Config.background.visualiser.spacing
    readonly property real fallbackMargin: Tokens.padding.large + Tokens.spacing.small

    opacity: shouldBeActive ? 1 : 0

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: root.opacity > 0 && Config.background.visualiser.blur
        sourceComponent: MultiEffect {
            source: root.wallpaper
            maskSource: wrapper
            maskEnabled: true
            blurEnabled: true
            blur: 1
            blurMax: 32
            autoPaddingEnabled: false
        }
    }
    Item {
        id: wrapper

        anchors.fill: parent
        layer.enabled: true

        Loader {
            asynchronous: true
            anchors.fill: parent
            anchors.topMargin: root.offset
            anchors.bottomMargin: -root.offset
            active: root.opacity > 0
            sourceComponent: Item {
                ServiceRef {
                    service: Audio.cava
                }
                VisualiserBars {
                    id: bars

                    readonly property real baseMargin: root.barExclusiveZone + root.visualiserSpacing

                    anchors.fill: parent
                    anchors.margins: Config.border.thickness
                    anchors.leftMargin: Config.bar.position === "left" ? (root.barExclusiveZone + root.fallbackMargin) : root.fallbackMargin
                    anchors.rightMargin: Config.bar.position === "right" ? (root.barExclusiveZone + root.fallbackMargin) : root.fallbackMargin
                    anchors.topMargin: Config.bar.position === "top" ? root.barExclusiveZone : Config.border.thickness
                    anchors.bottomMargin: Config.bar.position === "bottom" ? root.barExclusiveZone : Config.border.thickness
                    values: Audio.cava?.values ?? []
                    primaryColor: Qt.alpha(Colours.palette.m3primary, 0.7)
                    secondaryColor: Qt.alpha(Colours.palette.m3inversePrimary, 0.7)
                    rounding: Tokens.rounding.medium * Config.background.visualiser.rounding
                    spacing: Tokens.spacing.extraSmall * Config.background.visualiser.spacing
                    animationDuration: Tokens.anim.durations.expressiveDefaultEffects

                    Behavior on anchors.leftMargin {
                        Anim {}
                    }
                    Behavior on anchors.rightMargin {
                        Anim {}
                    }
                    Behavior on anchors.topMargin {
                        Anim {}
                    }
                    Behavior on anchors.bottomMargin {
                        Anim {}
                    }
                }
                FrameAnimation {
                    running: root.opacity > 0 && !bars.settled && (Audio.cava?.values?.length ?? 0) > 0
                    onTriggered: bars.advance(frameTime)
                }
            }
        }
    }
    Behavior on offset {
        Anim {}
    }
    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
