pragma Singleton

import QtQuick
import Caelestia.Services

QtObject {
    id: root

    readonly property var keybinds: KeybindsModel.keybinds
    readonly property bool initialized: KeybindsModel.initialized
    property Connections _conn: Connections {
        function onLoaded(): void { root.loaded(); }

        target: KeybindsModel
    }

    signal loaded

    function loadKeybinds(): void {
        if (KeybindsModel.initialized && KeybindsModel.keybinds.length > 0) {
            return;
        }
        KeybindsModel.load();
    }

    function query(searchText: string): var {
        return KeybindsModel.query(searchText, true);
    }

    Component.onCompleted: loadKeybinds()
}
