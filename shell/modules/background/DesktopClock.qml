pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property var frame: null
    property var controller: null
    property Item wallpaper: controller?.wallpaper ?? null
    property real absX: (controller?.gridOrigin.x ?? 0) + (frame?.x ?? 0)
    property real absY: (controller?.gridOrigin.y ?? 0) + (frame?.y ?? 0)

    readonly property real containerW: frame ? frame.width : width
    readonly property real containerH: frame ? frame.height : height
    readonly property real availableWidth: Math.max(0, containerW - Tokens.padding.large * 2)
    readonly property real availableHeight: Math.max(0, containerH - Tokens.padding.medium * 2)
    readonly property real aspect: containerH > 0 ? (containerW / containerH) : 1.0

    readonly property int layoutMode: aspect < 1.25 ? 2 : (containerW < 340 || aspect < 1.55 ? 1 : 0)

    readonly property real wideScale: Math.max(0.3, Math.min(2.0, Math.min(availableWidth / 560, availableHeight / 140)))
    readonly property real compactScale: Math.max(0.35, Math.min(1.8, Math.min(availableWidth / 300, availableHeight / 140)))
    readonly property real stackedScale: Math.max(0.3, Math.min(1.8, Math.min(availableWidth / 180, availableHeight / 240)))

    readonly property bool bgEnabled: Config.background.desktopClock.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopClock.background.blur && !GameMode.enabled
    readonly property bool invertColors: Config.background.desktopClock.invertColors
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary
    readonly property string clockFont: GlobalConfig.appearance.font.clock
    readonly property string sansFont: GlobalConfig.appearance.font.body.family

    implicitWidth: layoutMode === 0 ? (wideLayout.implicitWidth + Tokens.padding.large * 2) : (layoutMode === 1 ? (compactLayout.implicitWidth + Tokens.padding.large * 2) : (stackedLayout.implicitWidth + Tokens.padding.large * 2))
    implicitHeight: layoutMode === 0 ? (wideLayout.implicitHeight + Tokens.padding.medium * 2) : (layoutMode === 1 ? (compactLayout.implicitHeight + Tokens.padding.medium * 2) : (stackedLayout.implicitHeight + Tokens.padding.medium * 2))

    Item {
        id: clockContainer

        anchors.fill: parent
        clip: true

        layer.enabled: Config.background.desktopClock.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Config.background.desktopClock.shadow.opacity
            shadowBlur: Config.background.desktopClock.shadow.blur
        }

        Loader {
            asynchronous: true
            anchors.fill: parent
            active: root.blurEnabled

            sourceComponent: MultiEffect {
                source: ShaderEffectSource {
                    sourceItem: root.wallpaper
                    sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
                }
                maskSource: backgroundPlate
                maskEnabled: true
                blurEnabled: true
                blur: 1
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        StyledRect {
            id: backgroundPlate

            visible: root.bgEnabled
            anchors.fill: parent
            radius: root.layoutMode === 2 ? Math.min(root.containerW, root.containerH) * 0.24 : Tokens.rounding.extraLarge
            opacity: Config.background.desktopClock.background.opacity
            color: Colours.palette.m3surface

            layer.enabled: root.blurEnabled

            Behavior on radius {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }

        RowLayout {
            id: wideLayout

            anchors.centerIn: parent
            spacing: Tokens.spacing.large * root.wideScale
            visible: opacity > 0
            opacity: root.layoutMode === 0 ? 1 : 0
            scale: root.layoutMode === 0 ? 1 : 0.92

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            RowLayout {
                spacing: Tokens.spacing.small * root.wideScale

                StyledText {
                    text: Time.hourStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.8 * root.wideScale).weight(Font.Bold).family(root.clockFont).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: ":"
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.8 * root.wideScale).family(root.clockFont).build()
                    color: root.safeTertiary
                    opacity: 0.8
                    Layout.topMargin: -Tokens.padding.large * 1.5 * root.wideScale
                }

                StyledText {
                    text: Time.minuteStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.8 * root.wideScale).weight(Font.Bold).family(root.clockFont).build()
                    color: root.safeSecondary
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.padding.large * 1.4 * root.wideScale

                    active: Units.twelveHourClock
                    visible: active

                    sourceComponent: StyledText {
                        text: Time.amPmStr
                        font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.wideScale).family(root.sansFont).build()
                        color: root.safeSecondary
                    }
                }
            }

            StyledRect {
                Layout.fillHeight: true
                Layout.preferredWidth: 4 * root.wideScale
                Layout.topMargin: Tokens.spacing.medium * root.wideScale
                Layout.bottomMargin: Tokens.spacing.medium * root.wideScale
                radius: Tokens.rounding.full
                color: root.safePrimary
                opacity: 0.7
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: Time.format("MMMM").toUpperCase()
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.wideScale).letterSpacing(4).weight(Font.Bold).family(root.sansFont).build()
                    color: root.safeSecondary
                }

                StyledText {
                    text: Time.format("dd")
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * root.wideScale).letterSpacing(2).weight(Font.Medium).family(root.sansFont).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: Time.format("dddd")
                    font: Tokens.font.clock.size(Tokens.font.body.large.pointSize * root.wideScale).letterSpacing(2).family(root.sansFont).build()
                    color: root.safeSecondary
                    opacity: 0.9
                }
            }
        }

        ColumnLayout {
            id: compactLayout

            anchors.centerIn: parent
            spacing: Tokens.spacing.medium * root.compactScale
            visible: opacity > 0
            opacity: root.layoutMode === 1 ? 1 : 0
            scale: root.layoutMode === 1 ? 1 : 0.92

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.extraSmall * root.compactScale

                StyledText {
                    text: Time.hourStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.2 * root.compactScale).weight(Font.Bold).family(root.clockFont).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: ":"
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.2 * root.compactScale).family(root.clockFont).build()
                    color: root.safeTertiary
                    opacity: 0.8
                    Layout.topMargin: -Tokens.padding.medium * root.compactScale
                }

                StyledText {
                    text: Time.minuteStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.2 * root.compactScale).weight(Font.Bold).family(root.clockFont).build()
                    color: root.safeSecondary
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.padding.medium * root.compactScale

                    active: Units.twelveHourClock
                    visible: active

                    sourceComponent: StyledText {
                        text: Time.amPmStr
                        font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.compactScale).weight(Font.Medium).family(root.sansFont).build()
                        color: root.safeSecondary
                        opacity: 0.85
                    }
                }
            }

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: dateTextCompact.implicitHeight + Tokens.padding.small * root.compactScale * 1.4
                Layout.preferredWidth: dateTextCompact.implicitWidth + Tokens.padding.large * root.compactScale * 1.8
                radius: Tokens.rounding.full
                color: Qt.alpha(root.safeSecondary, 0.12)
                border.width: 1
                border.color: Qt.alpha(root.safeSecondary, 0.22)

                StyledText {
                    id: dateTextCompact

                    anchors.centerIn: parent
                    text: Time.format("dddd, MMMM d")
                    font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.compactScale).letterSpacing(1).weight(Font.Medium).family(root.sansFont).build()
                    color: root.safeSecondary
                }
            }
        }

        ColumnLayout {
            id: stackedLayout

            anchors.centerIn: parent
            spacing: -Tokens.spacing.small * root.stackedScale
            visible: opacity > 0
            opacity: root.layoutMode === 2 ? 1 : 0
            scale: root.layoutMode === 2 ? 1 : 0.92

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Time.hourStr
                font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.1 * root.stackedScale).weight(Font.Black).family(root.clockFont).build()
                color: root.safePrimary
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.extraSmall * root.stackedScale

                StyledText {
                    text: Time.minuteStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 2.1 * root.stackedScale).weight(Font.Black).family(root.clockFont).build()
                    color: root.safeSecondary
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Tokens.padding.small * root.stackedScale

                    active: Units.twelveHourClock
                    visible: active

                    sourceComponent: StyledText {
                        text: Time.amPmStr
                        font: Tokens.font.clock.size(Tokens.font.label.medium.pointSize * root.stackedScale).weight(Font.Bold).family(root.sansFont).build()
                        color: root.safeSecondary
                        opacity: 0.8
                    }
                }
            }

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small * root.stackedScale
                Layout.preferredHeight: dateTextStacked.implicitHeight + Tokens.padding.extraSmall * root.stackedScale * 1.6
                Layout.preferredWidth: dateTextStacked.implicitWidth + Tokens.padding.medium * root.stackedScale * 1.8
                radius: Tokens.rounding.full
                color: Qt.alpha(root.safePrimary, 0.14)
                border.width: 1
                border.color: Qt.alpha(root.safePrimary, 0.25)

                StyledText {
                    id: dateTextStacked

                    anchors.centerIn: parent
                    text: Time.format("ddd, MMM d").toUpperCase()
                    font: Tokens.font.clock.size(Tokens.font.label.large.pointSize * root.stackedScale).letterSpacing(2).weight(Font.Bold).family(root.sansFont).build()
                    color: root.safePrimary
                }
            }
        }
    }
}
