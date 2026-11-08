pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

QtObject {
    readonly property string assetDir: "../../assets/whatsnew/"

    readonly property var list: [
        {
            "id": "floating_osd_styles",
            "revision": 85,
            "icon": "picture_in_picture_alt",
            "title": qsTr("Floating OSD Styles"),
            "settingsPage": "panels",
            "settingsSubPage": 24,
            "description": qsTr("Pick a volume and brightness OSD: pill, compact, radial, card, or the edge drawer.")
        },
        {
            "id": "desktop_widgets",
            "revision": 86,
            "icon": "widgets",
            "title": qsTr("Desktop Widgets"),
            "description": qsTr("Add clocks, calendars, notes, weather, media and folders to the desktop, then resize or configure each one.")
        },
        {
            "id": "notification_click",
            "revision": 87,
            "icon": "open_in_new",
            "title": qsTr("Open From a Notification"),
            "description": qsTr("Click a notification to open the app that sent it.")
        },
        {
            "id": "notification_sounds",
            "revision": 88,
            "icon": "volume_up",
            "title": qsTr("Notification Sounds"),
            "settingsPage": "audio",
            "settingsSubPage": 4,
            "description": qsTr("Choose the notification sound and volume, and preview it in Sound Effects.")
        },
        {
            "id": "quickshare_pairing_code",
            "revision": 89,
            "icon": "verified_user",
            "title": qsTr("Quick Share Pairing Code"),
            "description": qsTr("Both devices show a four-digit code. Compare them before a file is sent.")
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
