pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.utils

Singleton {
    id: root

    readonly property bool streamActive: PipewireStreamWatcher.streaming || Recorder.running
    property bool sharing: false

    function evaluate(): void {
        if (root.streamActive) {
            stopTimer.stop();
            if (!root.sharing)
                root.sharing = true;
        } else if (root.sharing) {
            stopTimer.restart();
        }
    }

    function rescan(): void {
        PipewireStreamWatcher.rescan();
        root.evaluate();
    }

    /// Quiet while sharing, held as its own reason so the user's switch stays theirs.
    function engageAutoDnd(): void {
        Notifs.setDndHold("stream", true);
    }

    function releaseAutoDnd(): void {
        Notifs.setDndHold("stream", false);
    }

    onStreamActiveChanged: root.evaluate()

    onSharingChanged: {
        if (!Config.utilities.toasts.dndWhileStreaming)
            return;
        if (root.sharing)
            root.engageAutoDnd();
        else
            root.releaseAutoDnd();
    }

    Component.onCompleted: root.evaluate()

    Timer {
        id: stopTimer

        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.streamActive && root.sharing)
                root.sharing = false;
        }
    }

    Connections {
        function onDndWhileStreamingChanged(): void {
            if (!Config.utilities.toasts.dndWhileStreaming)
                root.releaseAutoDnd();
            else if (root.sharing)
                root.engageAutoDnd();
        }

        target: Config.utilities.toasts
    }
}
