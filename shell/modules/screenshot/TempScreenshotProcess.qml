import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Process {
    id: screenshotProc

    running: true

    property string screenshotDir: Paths.runtimeTemp("screenshot")

    required property ShellScreen screen

    property string screenshotPath: `${screenshotDir}/image-${screen.name}.png`

    readonly property string _safeDir: screenshotDir.split("'").join("'\\''")

    readonly property string _safePath: screenshotPath.split("'").join("'\\''")

    property int timeoutSeconds: 15

    command: ["bash", "-c", `mkdir -p '${_safeDir}' && exec timeout --kill-after=5 ${timeoutSeconds} spectacle -b -n -m -o '${_safePath}'`]
}
