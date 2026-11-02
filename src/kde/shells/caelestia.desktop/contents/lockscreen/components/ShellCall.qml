import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

/// One caelestia-shell-ipc request from the greeter, which cannot reach the shell's
/// in-process models. `replied` carries stdout and fires for every reply, so a caller
/// can refresh after a command that prints nothing; `output` is empty in that case.
Plasma5Support.DataSource {
    id: root

    readonly property string ipcBin: "PATH=\"${CAELESTIA_BIN_DIR:-$HOME/.local/bin}:$PATH\" caelestia-shell-ipc"

    signal replied(string output)

    engine: "executable"
    connectedSources: []

    /// `request` is the whole IPC call, e.g. `notifs list`.
    function send(request: string): void {
        connectSource(root.ipcBin + " call " + request);
    }

    onNewData: (source, data) => {
        disconnectSource(source);
        root.replied(data["stdout"] || "");
    }
}
