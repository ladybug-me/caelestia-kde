import QtQuick

/// The notification dock's data, kept out of the lock screen page itself.
///
/// The shell owns the live list: `notifs.json` is only its debounced persistence copy,
/// so reading that file makes this dock lag seconds behind the notification page. Ask
/// the shell for the live snapshot instead. Do-not-disturb is the shell's too — the
/// dino game asks for quiet while it runs, and the shell holds that reason separately
/// from the user's own switch, so nothing here has to remember what it was before.
Item {
    id: root

    /// Polling is pointless while the dock is hidden behind a maximised window.
    property bool active: true
    /// The notifications the shell is showing, as plain objects.
    property var items: []
    /// Quiet for any reason, the user's switch or a holder's.
    property bool quiet: false

    function refresh(): void {
        list.send("notifs list");
    }

    function clearAll(): void {
        // The snapshot is authoritative, so drop the local copy for instant feedback
        // and let the next poll confirm it.
        root.items = [];
        clear.send("notifs clear");
    }

    function setGameQuiet(held: bool): void {
        hold.send("notifs setDndHold lockGame " + (held ? "true" : "false"));
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onRunningChanged: if (running) root.refresh()
        onTriggered: root.refresh()
    }

    ShellCall {
        id: list

        onReplied: output => {
            try {
                const snapshot = JSON.parse(output);
                if (!snapshot || !Array.isArray(snapshot.items))
                    return;

                root.items = snapshot.items;
                root.quiet = snapshot.quiet === true;
            } catch (e) {}
        }
    }

    ShellCall {
        id: clear

        onReplied: root.refresh()
    }

    ShellCall {
        id: hold

        onReplied: root.refresh()
    }
}
