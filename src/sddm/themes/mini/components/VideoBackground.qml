import "../singletons"
import QtMultimedia
import QtQuick

Item {
    id: root

    property bool isActive: false
    readonly property var candidates: ["mp4", "webm", "mkv", "mov", "m4v", "avi"]
    property int probeIndex: 0

    function probeNext() {
        if (probeIndex >= candidates.length)
            return;

        var ext = candidates[probeIndex];
        probeIndex += 1;
        player.source = Qt.resolvedUrl("../assets/background." + ext);
    }

    Component.onCompleted: {
        if (Theme.toBool(Theme.getConfig("backgroundVideoEnabled"), true))
            probeNext();
    }
    onIsActiveChanged: {
        Theme.videoActive = root.isActive;
        Theme.videoItem = root.isActive ? videoSurface : null;
    }

    MediaPlayer {
        id: player

        videoOutput: videoSurface
        loops: MediaPlayer.Infinite
        // A probe failure means the next candidate extension is tried; when none
        // works the image stays visible.
        onErrorOccurred: function (error, errorString) {
            if (root.isActive)
                return;

            root.probeNext();
        }
        onMediaStatusChanged: {
            if (root.isActive)
                return;

            if (mediaStatus === MediaPlayer.LoadedMedia) {
                if (player.hasVideo) {
                    root.isActive = true;
                    player.play();
                } else {
                    root.probeNext();
                }
            }
        }
    }

    VideoOutput {
        id: videoSurface

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root.isActive
    }
}
