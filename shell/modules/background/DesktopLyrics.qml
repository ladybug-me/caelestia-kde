pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    property var frame: null
    property var controller: null
    property ShellScreen screen: controller?.screenData ?? null
    property Item wallpaper: controller?.wallpaper ?? null
    property real absX: (controller?.gridOrigin.x ?? 0) + (frame?.x ?? 0)
    property real absY: (controller?.gridOrigin.y ?? 0) + (frame?.y ?? 0)
    property real gridScale: frame ? Math.min(frame.width / 350, frame.height / 180) : 1
    property real lyricsScale: Math.max(0.5, gridScale)

    readonly property bool bgEnabled: Config.background.desktopLyrics.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopLyrics.background.blur && !GameMode.enabled
    readonly property bool invertColors: Config.background.desktopLyrics.invertColors
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary
    readonly property string sansFont: GlobalConfig.appearance.font.body.family
    readonly property int alignment: Config.background.desktopLyrics.alignment
    readonly property bool autoHide: Config.background.desktopLyrics.autoHide
    readonly property bool windowHidesLyrics: Kwin.windowHidesDesktopWidgets(root.screen ? root.screen.name : "", false)
    readonly property bool allWindowsFloating: !windowHidesLyrics
    readonly property bool shouldHide: autoHide && windowHidesLyrics
    readonly property bool isPlaying: Players.active?.isPlaying ?? false

    readonly property bool hasLyrics: Lyrics.hasLyrics
    property int currentLyricIndex: -1
    readonly property bool isCurrentActive: currentLyricIndex >= 0

    property var player: Players.active
    property string displayedLyric: ""
    property string previousLyricText: ""
    property string nextLyricText: ""

    property real lyricSpacing: Tokens.spacing.large * root.lyricsScale
    property real targetCenterY: lyricsContainer.height > 0 ? (lyricsContainer.height - lyricContainer.height) / 2 : 0
    property real targetPrevY: targetCenterY - prevLyricItem.height - lyricSpacing
    property real targetNextY: targetCenterY + lyricContainer.height + lyricSpacing
    property real startNextY: targetNextY + nextLyricItem.height + lyricSpacing

    function reloadTrack() {
        const p = Players.active;
        if (p) {
            Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, p.length);
        } else {
            Lyrics.clearTrack();
        }
    }

    function forceUpdate() {
        if (Lyrics.hasLyrics) {
            currentLyricIndex = Lyrics.indexForTime(Players.active?.position ?? 0);
            if (currentLyricIndex >= 0) {
                displayedLyric = (Lyrics.lyrics[currentLyricIndex] ?? "").replace(/\u00A0/g, " ");
                previousLyricText = currentLyricIndex > 0 ? (Lyrics.lyrics[currentLyricIndex - 1] ?? "").replace(/\u00A0/g, " ") : "";
                nextLyricText = currentLyricIndex < Lyrics.lyrics.length - 1 ? (Lyrics.lyrics[currentLyricIndex + 1] ?? "").replace(/\u00A0/g, " ") : "";
            } else {
                displayedLyric = "";
                previousLyricText = "";
                nextLyricText = (Lyrics.lyrics[0] ?? "").replace(/\u00A0/g, " ");
            }
            lyricSlide.running = true;
        } else {
            currentLyricIndex = -1;
            displayedLyric = "";
            previousLyricText = "";
            nextLyricText = "";
        }
    }

    onCurrentLyricIndexChanged: {
        if (Lyrics.hasLyrics) {
            if (currentLyricIndex >= 0) {
                displayedLyric = (Lyrics.lyrics[currentLyricIndex] ?? "").replace(/\u00A0/g, " ");
                previousLyricText = currentLyricIndex > 0 ? (Lyrics.lyrics[currentLyricIndex - 1] ?? "").replace(/\u00A0/g, " ") : "";
                nextLyricText = currentLyricIndex < Lyrics.lyrics.length - 1 ? (Lyrics.lyrics[currentLyricIndex + 1] ?? "").replace(/\u00A0/g, " ") : "";
            } else {
                displayedLyric = "";
                previousLyricText = "";
                nextLyricText = (Lyrics.lyrics[0] ?? "").replace(/\u00A0/g, " ");
            }
            lyricSlide.running = true;
        } else {
            displayedLyric = "";
            previousLyricText = "";
            nextLyricText = "";
        }
    }

    Component.onCompleted: {
        root.reloadTrack();
    }

    implicitWidth: 350 * root.lyricsScale
    implicitHeight: 180 * root.lyricsScale
    width: frame ? frame.width : implicitWidth
    height: frame ? frame.height : implicitHeight

    opacity: (root.isPlaying && root.hasLyrics && !root.shouldHide) ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {}
    }

    Behavior on lyricsScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on implicitWidth {
        Anim {
            type: Anim.StandardSmall
        }
    }

    SequentialAnimation {
        id: lyricSlide

        PropertyAction {
            target: prevLyricItem
            property: "y"
            value: root.targetCenterY
        }
        PropertyAction {
            target: lyricContainer
            property: "y"
            value: root.targetNextY
        }
        PropertyAction {
            target: nextLyricItem
            property: "y"
            value: root.startNextY
        }
        ParallelAnimation {
            NumberAnimation {
                target: prevLyricItem
                property: "y"
                to: root.targetPrevY
                duration: Tokens.anim.durations.expressiveDefaultEffects
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lyricContainer
                property: "y"
                to: root.targetCenterY
                duration: Tokens.anim.durations.expressiveDefaultEffects
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: nextLyricItem
                property: "y"
                to: root.targetNextY
                duration: Tokens.anim.durations.expressiveDefaultEffects
                easing.type: Easing.OutCubic
            }
        }
    }

    Timer {
        running: Players.active?.isPlaying ?? false
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            if (!Players.active)
                return;
            currentLyricIndex = Lyrics.indexForTime(Players.active.position);
            Players.active?.positionChanged();
        }
    }

    Connections {
        function onActiveChanged() {
            root.reloadTrack();
        }

        target: Players
    }

    Connections {
        function onPostTrackChanged() {
            root.reloadTrack();
        }

        // Browser track fields may arrive after the track-change notification.
        function onTrackTitleChanged() { root.reloadTrack(); }
        function onTrackArtistChanged() { root.reloadTrack(); }
        function onTrackAlbumChanged() { root.reloadTrack(); }
        function onLengthChanged() { root.reloadTrack(); }

        ignoreUnknownSignals: true

        target: Players.active
    }

    Connections {
        function onHasLyricsChanged() {
            root.forceUpdate();
        }

        // hasLyricsChanged only fires when the boolean flips, so a track with
        // lyrics replacing another one never triggered a refresh and the widget
        // kept showing the previous song until it was rebuilt. lyricsChanged
        // fires on every load, which keeps the lines in sync.
        function onLyricsChanged() {
            root.forceUpdate();
        }

        target: Lyrics
    }

    Item {
        id: lyricsContainer

        anchors.fill: parent

        layer.enabled: Config.background.desktopLyrics.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Config.background.desktopLyrics.shadow.opacity
            shadowBlur: Config.background.desktopLyrics.shadow.blur
        }

        Loader {
            id: blurLoader

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
            radius: Tokens.rounding.large * root.lyricsScale
            opacity: Config.background.desktopLyrics.background.opacity
            color: Colours.palette.m3surface

            layer.enabled: root.blurEnabled
        }

        Item {
            id: fadeContainer

            anchors.fill: parent
            clip: true
            opacity: root.hasLyrics ? 1 : 0

            layer.enabled: true
            layer.effect: Mask {
                maskSource: fadeMask
            }

            Behavior on opacity {
                Anim {
                    type: Anim.SlowEffects
                }
            }

            Rectangle {
                id: fadeMask

                layer.enabled: true
                visible: false
                implicitWidth: fadeContainer.width
                implicitHeight: fadeContainer.height

                gradient: Gradient {
                    orientation: Gradient.Vertical

                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 0
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.25
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.75
                    }
                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 1
                    }
                }
            }

            Item {
                id: prevLyricItem

                width: parent.width
                height: prevLyricLabel.implicitHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.targetPrevY
                visible: root.isCurrentActive

                StyledText {
                    id: prevLyricLabel

                    anchors.fill: parent
                    text: root.previousLyricText
                    font.family: root.sansFont
                    font.pointSize: Tokens.font.body.medium.pointSize * root.lyricsScale
                    color: root.safeSecondary
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                    horizontalAlignment: {
                        switch (root.alignment) {
                        case 0:
                            return Text.AlignLeft;
                        case 2:
                            return Text.AlignRight;
                        default:
                            return Text.AlignHCenter;
                        }
                    }
                }
            }

            Item {
                id: lyricContainer

                width: parent.width
                height: currentLyricLabel.implicitHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.targetCenterY
                visible: root.isCurrentActive

                MultiEffect {
                    id: lyricGlow

                    anchors.fill: currentLyricLabel
                    source: currentLyricLabel
                    scale: currentLyricLabel.scale
                    enabled: root.isCurrentActive

                    blurEnabled: true
                    blur: 0.4

                    shadowEnabled: true
                    shadowColor: Colours.palette.m3primary
                    shadowOpacity: 0.5
                    shadowBlur: 0.6
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0

                    autoPaddingEnabled: true
                }

                StyledText {
                    id: currentLyricLabel

                    width: parent.width
                    text: root.displayedLyric
                    font.family: root.sansFont
                    font.pointSize: Tokens.font.title.medium.pointSize * 1.3 * root.lyricsScale
                    font.weight: Font.Bold
                    color: Colours.palette.m3primary
                    wrapMode: Text.WordWrap
                    horizontalAlignment: {
                        switch (root.alignment) {
                        case 0:
                            return Text.AlignLeft;
                        case 2:
                            return Text.AlignRight;
                        default:
                            return Text.AlignHCenter;
                        }
                    }

                    Behavior on color {
                        CAnim {
                            duration: Tokens.anim.durations.expressiveFastEffects
                        }
                    }
                }
            }

            Item {
                id: nextLyricItem

                width: parent.width
                height: nextLyricLabel.implicitHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.targetNextY
                visible: root.isCurrentActive

                StyledText {
                    id: nextLyricLabel

                    anchors.fill: parent
                    text: root.nextLyricText
                    font.family: root.sansFont
                    font.pointSize: Tokens.font.body.medium.pointSize * root.lyricsScale
                    color: root.safeSecondary
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                    horizontalAlignment: {
                        switch (root.alignment) {
                        case 0:
                            return Text.AlignLeft;
                        case 2:
                            return Text.AlignRight;
                        default:
                            return Text.AlignHCenter;
                        }
                    }
                }
            }
        }
    }
}
