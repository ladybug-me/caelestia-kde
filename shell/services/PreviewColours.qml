import QtQuick
import Quickshell.Io
import qs.services

// The colour preview of the wallpaper picker. It owns the matugen process and decides when its
// result may cover the applied scheme:
//   show(source)  preview an image; a call made while a preview runs reruns it for the latest source
//   hold()        keep the preview on screen until release(), while the chosen scheme loads
//   release()     the chosen scheme has landed; a stop() that waited for it takes effect
//   stop()        the preview is over; a result that arrives later is dropped
Item {
    id: root

    property list<string> extraArgs: []

    property bool active
    property bool held
    property bool clearOnRelease
    property string wanted
    property string running

    function show(source: string): void {
        if (source === "")
            return;
        active = true;
        wanted = source;
        if (!proc.running)
            start();
    }

    function hold(): void {
        held = true;
    }

    function release(): void {
        held = false;
        if (clearOnRelease)
            clear();
    }

    function stop(): void {
        active = false;
        wanted = "";
        if (held)
            clearOnRelease = true;
        else
            clear();
    }

    function start(): void {
        running = wanted;
        proc.running = true;
    }

    function clear(): void {
        clearOnRelease = false;
        Colours.showPreview = false;
    }

    Process {
        id: proc

        command: ["caelestia", "wallpaper", "-p", root.running, ...root.extraArgs]
        stdout: StdioCollector {
            onStreamFinished: {
                // Nothing wants a preview any more and no chosen scheme is waiting on one.
                if (!root.active && !root.held)
                    return;
                // The highlight moved while this ran, so the result belongs to an earlier one.
                if (root.active && root.wanted !== root.running) {
                    Qt.callLater(root.start);
                    return;
                }
                if (Colours.load(text, true))
                    Colours.showPreview = true;
            }
        }
    }
}
