pragma Singleton

import QtQuick

QtObject {
    id: apiRoot

    readonly property PluginsApi plugins: PluginsApi {}
}
