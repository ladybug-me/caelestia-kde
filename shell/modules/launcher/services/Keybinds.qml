pragma Singleton

import QtQuick
import Caelestia.Services

QtObject {
    id: root

    readonly property var keybinds: KeybindsModel.keybinds
    readonly property bool initialized: KeybindsModel.initialized
    property Connections _conn: Connections {
        target: KeybindsModel

        function onLoaded(): void { root.loaded(); }
    }

    signal loaded

    function loadKeybinds() {
        if (KeybindsModel.initialized && KeybindsModel.keybinds.length > 0) {
            return;
        }
        KeybindsModel.load();
    }

    function query(searchText) {
        return KeybindsModel.query(searchText);
    }

    Component.onCompleted: loadKeybinds()
}