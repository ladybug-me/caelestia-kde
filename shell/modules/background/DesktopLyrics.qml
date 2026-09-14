pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property Item wallpaper
    required property real absX
    required property real absY

    property real lyricsScale: Config.background.desktopLyrics.scale
    readonly property bool bgEnabled: Config.background.desktopLyrics.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopLyrics.background.blur && !GameMode.enabled
    readonly property bool invertColors: Config.background.desktopLyrics.invertColors
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary
    readonly property string sansFont: GlobalConfig.appearance.font.body.family || "Sans Serif"
    readonly property int alignment: Config.background.desktopLyrics.alignment
    readonly property bool autoHide: Config.background.desktopLyrics.autoHide
    readonly property bool windowHidesLyrics: {
const wins = Kwin.windowList || [];
const hideOnAll = Config.background.visualiser.hideOnAllMonitors;
const currentScreenName = root.screen ? root.screen.name : "";
const byOutput = Kwin.activeByOutput;
const globalActiveWs = Kwin.activeWsId;

const getActiveWs = outName => {
    if (byOutput && byOutput[outName] !== undefined)
        return byOutput[outName];
    return globalActiveWs;
};

const isWindowMaximizedOnWs = (win, outName) => {
    if (win.minimized === true)
        return false;
    if (!win.maximized && !win.fullscreen)
        return false;
    const winWs = win.workspace?.id ?? -1;
    const activeWs = getActiveWs(outName);
    return activeWs === -1 || winWs === -1 || winWs === activeWs;
};

if (hideOnAll) {
    return wins.some(w => isWindowMaximizedOnWs(w, w.output || currentScreenName));
} else {
    return wins.some(w => (currentScreenName === "" || w.output === currentScreenName) && isWindowMaximizedOnWs(w, currentScreenName));
}
    }
    readonly property bool allWindowsFloating: !windowHidesLyrics
    readonly property bool shouldHide: autoHide && windowHidesLyrics

    property bool hasLyrics: Lyrics.hasLyrics
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

    opacity: ((root.hasLyrics || Lyrics.loading) && !root.shouldHide) ? 1 : 0
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

        ignoreUnknownSignals: true

        target: Players.active
    }

    Connections {
        function onHasLyricsChanged() {
            root.hasLyrics = Lyrics.hasLyrics;
            root.forceUpdate();
        }

        target: Lyrics
    }

    Item {
        id: lyricsContainer

        anchors.fill: parent
        // Removed clip: true from here so the shadow doesn't get cut off

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

        Loader {
            id: loadingIndicator

            anchors.centerIn: parent
            asynchronous: true
            active: opacity > 0
            opacity: Lyrics.loading && !root.hasLyrics ? 1 : 0

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.large * root.lyricsScale

                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: shape.implicitSize + Tokens.padding.medium * 2 * root.lyricsScale
                    implicitHeight: shape.implicitSize + Tokens.padding.medium * 2 * root.lyricsScale
                    color: Colours.palette.m3primaryContainer
                    radius: Tokens.rounding.full

                    LoadingIndicator {
                        id: shape

                        anchors.centerIn: parent
                        implicitSize: Math.round(Tokens.sizes.dashboard.mediaSectionWidth / 5 * root.lyricsScale)
                        containsIcon: true
                        color: Colours.palette.m3primary
                    }
                }

                StyledText {
                    text: qsTr("Loading lyrics...")
                    color: root.safeSecondary
                    font.pointSize: Tokens.font.title.medium.pointSize * root.lyricsScale
                    font.family: Tokens.font.title.medium.family
                    font.weight: Tokens.font.title.medium.weight
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // --- NEW INNER CONTAINER FOR FADE MASK ---
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
                        position: 0.25 // fadeMargin
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.75 // 1 - fadeMargin
                    }
                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 1
                    }
                }
            }

            // --- Previous Lyric ---
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

            // --- Current Lyric ---
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
