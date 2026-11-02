pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/// A script in `scripts/` whose answer is JSON, with its failure kept as a failure.
///
/// Every service that reads one otherwise repeats the same steps — build the command,
/// collect stdout, survive a parse that throws, and decide what "nothing" means — and each
/// of them ends up reporting "nothing" for "it broke", which the view then shows as a fact.
/// Written once: the answer and the failure are settled together, from whatever the process
/// and its two streams ended up saying.
Process {
    id: root

    required property string script
    property list<string> args: []
    property var result: null
    property string error: ""
    property bool loaded: false

    property int exitStatus: 0
    property bool exited: false
    property bool unreadable: false

    /// Runs the script again. A run already in flight is abandoned rather than queued:
    /// the newer arguments are the ones the caller is waiting for an answer about.
    function start(): void {
        root.result = null;
        root.error = "";
        root.loaded = false;
        root.exited = false;
        root.unreadable = false;
        if (running)
            running = false;
        running = true;
    }

    /// The one place the outcome is decided. It recomputes from the state instead of
    /// editing it, because the streams and the exit arrive in whichever order they like:
    /// whichever is last settles the same answer, and a late stream can still correct an
    /// early "printed nothing".
    function settle(): void {
        if (!root.exited)
            return;
        const detail = stderrOutput.text.trim();
        if (root.exitStatus !== 0)
            root.error = detail || qsTr("The script failed with exit code %1.").arg(root.exitStatus);
        else if (root.unreadable)
            root.error = qsTr("The script printed something that is not JSON.");
        else if (root.result === null)
            root.error = detail || qsTr("The script printed nothing.");
        else
            root.error = "";
        root.loaded = true;
    }

    command: ["python3", Quickshell.shellPath(root.script), ...root.args]

    stdout: StdioCollector {
        id: output

        onStreamFinished: {
            const text = output.text.trim();
            root.result = null;
            root.unreadable = false;
            if (text !== "") {
                try {
                    root.result = JSON.parse(text);
                } catch (exception) {
                    root.unreadable = true;
                }
            }
            root.settle();
        }
    }

    stderr: StdioCollector {
        id: stderrOutput
    }

    onExited: exitCode => {
        root.exitStatus = exitCode;
        root.exited = true;
        root.settle();
    }
}
