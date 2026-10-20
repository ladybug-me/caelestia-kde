pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

QtObject {
    readonly property string assetDir: "../../assets/whatsnew/"

    readonly property var list: [
        {
            "id": "shimeji-cat",
            "revision": 62,
            "icon": "pets",
            "title": qsTr("Shimeji Cat update"),
            "settingsPage": "plugins",
            "settingsSubPage": 1,
            "description": qsTr("Multiple Shimeji Cats can now be summoned at once. Also a fix regarding the cat hiding when clicking desktop has been pushed. Update from plugin store to access new features!")
        },
        {
            "id": "desktop_multimonitor",
            "revision": 63,
            "icon": "desktop_windows",
            "title": qsTr("Multi-Monitor Desktop Support"),
            "description": qsTr("Desktop icons and widgets now fully support multi-monitor setups with screen-aware positioning. Each connected display maintains its own grid layout and arrangement independently, ensuring widgets and icons stay pinned to their designated monitor across display reconnections and resolution changes without overlapping or shifting between screens.")
        },
        {
            "id": "desktop_widget_locking",
            "revision": 64,
            "icon": "lock",
            "title": qsTr("Widget Locking & Outlines"),
            "description": qsTr("Desktop widgets can now be locked individually or altogether directly from their context menus, preventing accidental dragging or resizing while interacting with them. In addition, a new widget outlines toggle highlights widget boundaries on your wallpaper, making it effortless to locate empty or conditionally hidden widgets across your desktop.")
        }
    ]

    function mediaSource(entry: var): url {
        if (!entry || !entry.mediaUrl)
            return "";
        if (entry.mediaUrl.startsWith("root:"))
            return Qt.resolvedUrl(`${Quickshell.shellDir}${entry.mediaUrl.slice("root:".length)}`);
        return Qt.resolvedUrl(`${assetDir}${entry.mediaUrl}`);
    }
}
