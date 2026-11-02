pragma ComponentBehavior: Bound

import QtQuick
import qs.services

QtObject {
    id: root

    required property bool active

    property string focusReturn: ""
    property int workspaceReturn: -1

    readonly property Timer restore: Timer {
        interval: 250
        repeat: false

        onTriggered: {
            const address = root.focusReturn;
            root.cancel();
            if (!Kwin.activeWindow?.address)
                Kwin.focusWindow(address);
        }
    }

    readonly property Connections activeWindowWatcher: Connections {
        function onActiveWindowChanged(): void {
            if (Kwin.activeWindow?.address)
                root.cancel();
        }

        target: Kwin
    }

    function cancel(): void {
        focusReturn = "";
        workspaceReturn = -1;
        restore.stop();
    }

    onActiveChanged: {
        if (active) {
            cancel();
            focusReturn = Kwin.activeWindow?.address ?? "";
            workspaceReturn = Kwin.activeWsId;
            return;
        }

        if (!focusReturn || Kwin.pendingFocusAddress || (workspaceReturn !== -1 && Kwin.activeWsId !== workspaceReturn)) {
            cancel();
            return;
        }

        restore.start();
    }
}
