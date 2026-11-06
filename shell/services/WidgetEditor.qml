pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop's widget editor: whether the mode is on, and what a copy holds.
// It owns the mode instead of the layout store, because nothing here is saved —
// the layout file only records where the widgets ended up.
Singleton {
    id: root

    property bool active: false

    // Widget specs copied with Ctrl+C: { type, size, config }, with no id. Shared
    // rather than kept per screen, so a copy can be pasted on another monitor.
    property var clipboard: []

    function setActive(on: bool): void {
        if (active === on)
            return;
        // The two edit modes hide each other's desktop, so the desktop can only be
        // in one of them. Every way in goes through here.
        if (on)
            ContextMenuStore.editMode = false;
        active = on;
    }

    function toggle(): void {
        setActive(!active);
    }

    function close(): void {
        setActive(false);
    }

    IpcHandler {
        function editWidgets(): void {
            root.setActive(true);
        }

        function exitWidgetEdit(): void {
            root.close();
        }

        function toggleWidgetEdit(): void {
            root.toggle();
        }

        target: "desktop"
    }
}
