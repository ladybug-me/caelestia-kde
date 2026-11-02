pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Services
import qs.services

// Who is capturing the microphone or the screen right now, as application names. Both
// kinds of stream node exist only while an application is capturing, so their presence
// is the whole signal: playback streams are not private and are ignored, and the shell's
// own recorder is left to the screen capture widget that already reports it.
Singleton {
    id: root

    // One name per application, never the shell's own capture: the indicator answers
    // "is somebody else listening".
    readonly property var microphoneApps: {
        const names = [];
        for (const stream of Audio.captureStreams) {
            const name = Audio.getStreamName(stream);
            if (name !== Audio.selfAppName && !names.includes(name))
                names.push(name);
        }
        return names;
    }

    readonly property var videoApps: PipewireStreamWatcher.activeStreams

    readonly property bool inUse: root.microphoneApps.length > 0 || root.videoApps.length > 0
}