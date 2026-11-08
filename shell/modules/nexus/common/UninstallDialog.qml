pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.nexus.common

// The uninstaller decides for itself whether it can run and asks its own
// confirmation in the terminal, so this only explains what will happen and hands
// over the command when the install belongs to a package.
NexusDialog {
    id: root

    property string state: "probing"
    property string manualCommand: ""

    readonly property bool canRun: root.state === "script"

    destructive: true
    title: qsTr("Uninstall Caelestia?")
    message: {
        if (root.state === "probing")
            return qsTr("Still looking for the uninstaller. Try again in a moment.");
        if (root.state === "script")
            return qsTr("This opens the uninstaller in a terminal, where it asks for confirmation of its own. It removes the shell, its config files and its services, and can restore your pre-install configuration from a backup.");
        if (root.state === "package")
            return qsTr("This install belongs to a package, so the package manager owns its files. Remove it with:\n\n%1").arg(root.manualCommand);
        return qsTr("No uninstaller script was found and no known package manager owns this install. Remove it the same way you installed it.");
    }
    confirmText: root.canRun ? qsTr("Uninstall") : ""
}
