pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.nexus.common

// Reverting is the one update action that moves the install backwards, so it asks
// first and says what it will do: which version it leaves, which one it returns to,
// that the settings are backed up, and that the shell restarts.
NexusDialog {
    id: root

    property string fromVersion: ""
    property string toVersion: ""

    destructive: true
    title: qsTr("Restore %1?").arg(root.toVersion)
    message: {
        if (root.fromVersion === "")
            return qsTr("This reinstalls an older version over the one installed now. Your settings are backed up first, and the shell restarts when it finishes.");
        return qsTr("This replaces %1 with %2. Your settings are backed up first, and the shell restarts when it finishes.").arg(root.fromVersion).arg(root.toVersion);
    }
    confirmText: qsTr("Restore")
}
