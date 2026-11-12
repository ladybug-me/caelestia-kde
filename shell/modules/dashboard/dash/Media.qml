pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.widgets
import qs.services
import qs.utils

Item {
    id: root

    // The player to control. Defaults to the active player, so the
    // dashboard renders exactly as before; embedders (e.g. the bar
    // popout) pass their filtered player instead.
    property MprisPlayer player: Players.active

    property real playerProgress: {
        const active = root.player;
        return active?.length ? (active.position % active.length) / active.length : 0;
    }

    readonly property real arcCoverGap: Tokens.spacing.extraSmall

    // Lets embedders (e.g. the bar popout) show extra controls in the
    // built-in row. Defaults to false, so the dashboard renders exactly
    // as before.
    property bool extraButtons: false

    // Lets embedders hide the gif block to compact the player.
    // Defaults to true, so the dashboard renders exactly as before.
    property bool showGif: true

    anchors.top: parent ? parent.top : undefined
    anchors.bottom: (root.showGif && parent) ? parent.bottom : undefined
    height: root.showGif ? undefined : implicitHeight
    implicitWidth: Tokens.sizes.dashboard.mediaWidth
    implicitHeight: Math.max(355, controls.y + controls.implicitHeight + Tokens.padding.large)

    Behavior on playerProgress {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Timer {
        running: root.visible && (root.player?.isPlaying ?? false)
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    Loader {
        active: root.visible && (root.player?.isPlaying ?? false)
        sourceComponent: ServiceRef {
            service: Audio.beatTracker
        }
    }

    CircularProgress {
        id: prog

        anchors.centerIn: cover
        implicitSize: cover.width + root.arcCoverGap + thickness * 2

        fgColour: Colours.palette.m3primary
        strokeWidth: Tokens.sizes.dashboard.mediaProgressThickness
        startAngle: -90 - sweepAngle / 2
        sweepAngle: Tokens.sizes.dashboard.mediaProgressSweep
        value: root.playerProgress

        wavy: true
        waveFrequency: 8
        waveDuration: 2000
        wavePaused: !root.player?.isPlaying
    }

    CoverArt {
        id: cover

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.medium + root.arcCoverGap + prog.thickness
        implicitHeight: width
    }

    Column {
        id: trackInfo

        anchors.top: cover.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.medium
        spacing: Tokens.spacing.small

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter

            animate: true
            horizontalAlignment: Text.AlignHCenter
            text: (root.player?.trackTitle ?? qsTr("No media")) || qsTr("Unknown title")
            color: Colours.palette.m3primary
            font: Tokens.font.title.small

            width: root.implicitWidth - Tokens.padding.extraLargeIncreased
            elide: Text.ElideRight
        }

        StyledText {
            visible: !!root.player && text !== ""
            anchors.horizontalCenter: parent.horizontalCenter

            animate: true
            horizontalAlignment: Text.AlignHCenter
            text: root.player?.trackAlbum || qsTr("Unknown album")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small

            width: root.implicitWidth - Tokens.padding.extraLargeIncreased
            elide: Text.ElideRight
        }

        StyledText {
            visible: !!root.player && text !== ""
            anchors.horizontalCenter: parent.horizontalCenter

            animate: true
            horizontalAlignment: Text.AlignHCenter
            text: root.player?.trackArtist || qsTr("Unknown artist")
            color: Colours.palette.m3secondary

            width: root.implicitWidth - Tokens.padding.extraLargeIncreased
            elide: Text.ElideRight
        }
    }

    ButtonRow {
        id: controls

        anchors.top: trackInfo.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.medium
        anchors.margins: Tokens.padding.large
        anchors.leftMargin: root.extraButtons ? Tokens.padding.small : Tokens.padding.large
        anchors.rightMargin: root.extraButtons ? Tokens.padding.small : Tokens.padding.large

        spacing: Tokens.spacing.extraSmall

        IconButton {
            visible: root.extraButtons
            type: IconButton.Tonal
            icon: "shuffle"
            isRound: true
            shapeMorph: true
            checked: root.player?.shuffle ?? false
            font: Tokens.font.icon.small
            disabled: !root.player?.shuffleSupported
            onClicked: root.player.shuffle = !root.player?.shuffle
            implicitWidth: Math.round(implicitHeight * 0.9)
        }

        IconButton {
            type: IconButton.Tonal
            icon: "skip_previous"
            isRound: true
            shapeMorph: true
            disabled: !root.player?.canGoPrevious
            onClicked: root.player?.previous()
        }

        IconButton {
            fillWidth: true
            icon: root.player?.isPlaying ? "pause" : "play_arrow"
            animateIcon: true
            isRound: true
            shapeMorph: true
            checked: root.player?.isPlaying ?? false
            disabled: !root.player?.canTogglePlaying
            onClicked: root.player?.togglePlaying()
        }

        IconButton {
            type: IconButton.Tonal
            icon: "skip_next"
            isRound: true
            shapeMorph: true
            disabled: !root.player?.canGoNext
            onClicked: root.player?.next()
        }

        IconButton {
            visible: root.extraButtons
            type: IconButton.Tonal
            icon: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
            isRound: true
            shapeMorph: true
            checked: root.player?.loopState === MprisLoopState.Track || root.player?.loopState === MprisLoopState.Playlist
            font: Tokens.font.icon.small
            disabled: !root.player?.loopSupported
            onClicked: {
                const state = root.player.loopState;
                if (state === MprisLoopState.None)
                    root.player.loopState = MprisLoopState.Track;
                else if (state === MprisLoopState.Track)
                    root.player.loopState = MprisLoopState.Playlist;
                else
                    root.player.loopState = MprisLoopState.None;
            }
            implicitWidth: Math.round(implicitHeight * 0.9)
        }
    }

    Item {
        id: bongocat

        visible: root.showGif
        anchors.top: controls.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.small
        anchors.bottomMargin: Tokens.padding.large
        anchors.margins: Tokens.padding.extraLargeIncreased

        AnimatedImage {
            id: gif

            anchors.fill: parent

            playing: root.player?.isPlaying ?? false
            speed: Audio.beatTracker.bpm / Config.general.mediaGifSpeedAdjustment // qmllint disable unresolved-type
            source: Paths.absolutePath(Config.paths.mediaGif)
            asynchronous: true
            fillMode: AnimatedImage.PreserveAspectFit
            visible: !Config.dashboard.useMediaShapes
        }

        MultiEffect {
            anchors.fill: gif
            source: gif

            visible: Config.dashboard.colorizeMediaGif && !Config.dashboard.useMediaShapes
            colorization: 1
            colorizationColor: Colours.palette.m3primary
        }

        MediaShapes {
            anchors.fill: parent
            visible: Config.dashboard.useMediaShapes
            active: Config.dashboard.useMediaShapes
        }
    }
}
