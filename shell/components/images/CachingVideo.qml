import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.services

Item {
    id: root

    property string path
    property var screen
    property bool isFirstInstance: false

    property alias playing: mediaPlayer.playing
    property alias fillMode: videoOutput.fillMode
    property alias playbackState: mediaPlayer.playbackState

    function checkPauseState() {
        if (!root.screen)
            return;

        if (GlobalConfig.background.videoWallpaperPaused) {
            if (mediaPlayer.playing)
                mediaPlayer.pause();
            return;
        }

        const pauseOnAllDisplays = GlobalConfig.background.videoWallpaperPauseOnAllDisplays;
        const pauseOnFullscreen = GlobalConfig.background.videoWallpaperPauseOnFullscreen;
        const pauseOnTiled = GlobalConfig.background.videoWallpaperPauseOnTiled;

        let shouldPause = false;

        try {
const wins = Kwin.windowList || [];
// KWin serialises fullscreen as a boolean (true/false), not
// the integer levels Hyprland uses (0/1/2). Use === true so
// the check works for both truthy booleans and int > 0.
if (pauseOnAllDisplays) {
    for (let i = 0; i < wins.length; i++) {
        if (pauseOnFullscreen && wins[i].fullscreen === true)
            shouldPause = true;
        if (pauseOnTiled && !wins[i].floating && !wins[i].fullscreen)
            shouldPause = true;
    }
} else {
    const screenName = root.screen ? root.screen.name : "";
    const activeOut = Kwin.activeOutputName || "";
    if (activeOut === screenName || screenName === "") {
        for (let i = 0; i < wins.length; i++) {
            if (pauseOnFullscreen && wins[i].fullscreen === true)
                shouldPause = true;
            if (pauseOnTiled && !wins[i].floating && !wins[i].fullscreen)
                shouldPause = true;
        }
    }
}
        
        } catch (e) {
            // Ignore error on non-Hyprland (e.g. KDE)
        }

        if (shouldPause && mediaPlayer.playing) {
            mediaPlayer.pause();
        } else if (!shouldPause && !mediaPlayer.playing && root.path) {
            mediaPlayer.play();
        }
    }

    function checkMuteState() {
        const muteOnMedia = GlobalConfig.background.videoWallpaperMuteOnMedia;
        const soundEnabled = GlobalConfig.background.videoWallpaperSoundEnabled;
        const isPlaying = Players.active?.isPlaying ?? false;

        if (audioLoader.item) {
            audioLoader.item.muted = !root.isFirstInstance || !soundEnabled || (muteOnMedia && isPlaying);
        }
    }

    Component.onCompleted: {
        isFirstInstance = (VideoWallpaperPlayer.firstInstance === null);
        VideoWallpaperPlayer.firstInstance = root;
        Qt.callLater(checkPauseState);
        Qt.callLater(checkMuteState);
    }

    Component.onDestruction: {
        if (VideoWallpaperPlayer.firstInstance === root) {
            VideoWallpaperPlayer.firstInstance = null;
        }
    }

    onPathChanged: {
        mediaPlayer.source = path || "";
        if (path)
            mediaPlayer.play();
    }

    // Only create an AudioOutput when sound is actually enabled.
    // Unconditionally instantiating AudioOutput triggers PipeWire audio-format
    // negotiation on every startup. On setups with HDMI/S-PDIF outputs,
    // PipeWire advertises IEC958 and F32P-planar formats that Qt's PipeWire
    // backend cannot parse, producing `spaVisitChoice: parse error` warnings.
    // On some PipeWire versions this causes the entire audio backend to fail,
    // which in turn prevents MediaPlayer from starting video playback at all.
    // Lazily loading AudioOutput avoids the negotiation unless the user has
    // sound enabled (which is off by default).
    Loader {
        id: audioLoader

        active: GlobalConfig.background.videoWallpaperSoundEnabled

        sourceComponent: AudioOutput {
            id: audioOutputImpl

            muted: !root.isFirstInstance || (GlobalConfig.background.videoWallpaperMuteOnMedia && (Players.active?.isPlaying ?? false))

            Component.onCompleted: {
                mediaPlayer.audioOutput = audioOutputImpl;
            }

            Component.onDestruction: {
                if (mediaPlayer.audioOutput === audioOutputImpl)
                    mediaPlayer.audioOutput = null;
            }
        }
    }

    MediaPlayer {
        id: mediaPlayer

        source: path || ""
        videoOutput: videoOutput
        loops: MediaPlayer.Infinite
        autoPlay: true
        // audioOutput is wired dynamically by the Loader above so that the
        // PipeWire backend is only initialised when the user has enabled sound.

        onErrorOccurred: function(error, errorString) {
            // If the player enters an error state (e.g. audio backend failure),
            // detach the audio output and retry video-only so the wallpaper
            // still plays without sound rather than being completely blank.
            if (mediaPlayer.audioOutput !== null) {
                console.warn("[CachingVideo] MediaPlayer error (audio?), retrying video-only:", errorString);
                mediaPlayer.audioOutput = null;
                if (root.path)
                    Qt.callLater(() => mediaPlayer.play());
            }
        }
    }

    VideoOutput {
        id: videoOutput

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop

        Component.onDestruction: {
            mediaPlayer.stop();
        }
    }

    Timer {
        id: mediaCheckTimer

        interval: 500
        running: GlobalConfig.background.videoWallpaperMuteOnMedia && audioLoader.active
        repeat: true

        onTriggered: checkMuteState()
    }

    Timer {
        id: checkTimer

        interval: 100
        running: true
        repeat: true

        onTriggered: {
            checkPauseState();
            checkMuteState();
        }
    }

    Connections {
        function onVideoWallpaperPausedChanged() {
            checkPauseState();
        }

        function onVideoWallpaperPauseOnAllDisplaysChanged() {
            checkPauseState();
        }

        function onVideoWallpaperPauseOnFullscreenChanged() {
            checkPauseState();
        }

        function onVideoWallpaperPauseOnTiledChanged() {
            checkPauseState();
        }

        function onVideoWallpaperMuteOnMediaChanged() {
            checkMuteState();
        }

        function onVideoWallpaperSoundEnabledChanged() {
            checkMuteState();
        }

        target: GlobalConfig.background
    }
}
