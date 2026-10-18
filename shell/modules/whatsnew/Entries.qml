import QtQuick
import Quickshell

QtObject {
    readonly property string assetDir: "../../assets/whatsnew/"

    readonly property var list: [
        {
            "id": "streaming_auto_dnd",
            "revision": 55,
            "icon": "notifications_off",
            "title": qsTr("Auto DND While Streaming"),
            "settingsPage": "notifications",
            "settingsSubPage": 1,
            "description": qsTr("Do Not Disturb now activates automatically when sharing your screen or streaming via OBS, keeping unwanted notification banners and sounds off your broadcast.")
        },
        {
            "id": "global_animation_switch",
            "revision": 56,
            "icon": "animation",
            "title": qsTr("Master Animation Switch"),
            "settingsPage": "appearance",
            "settingsSubPage": 8,
            "description": qsTr("A single toggle in Appearance settings now allows you to completely disable all shell animations and transitions for instant responsiveness.")
        },
        {
            "id": "music_ambient_glow",
            "revision": 57,
            "icon": "music_note",
            "title": qsTr("Music Ambient Glow"),
            "settingsPage": "panels",
            "settingsSubPage": 1,
            "description": qsTr("The Dashboard Music tab now features a dynamic ambient glow effect reflecting the colors of your currently playing media's album artwork.")
        },
        {
            "id": "visualizer_quick_toggle",
            "revision": 58,
            "icon": "graphic_eq",
            "title": qsTr("Audio Visualizer Toggle"),
            "settingsPage": "utilities",
            "settingsSubPage": 6,
            "description": qsTr("A dedicated Audio Visualizer toggle has been added to Quick Toggles, allowing you to instantly show or hide the desktop visualizer on demand.")
        },
        {
            "id": "taskbar_widgets_suite",
            "revision": 59,
            "icon": "widgets",
            "title": qsTr("New Taskbar Widgets"),
            "settingsPage": "panels",
            "settingsSubPage": 6,
            "description": qsTr("The taskbar now includes dedicated widgets for Notes, Weather, Performance stats, Shortcuts, Screen Capture, and Keep Awake, complete with hover popouts and inline settings.")
        },
        {
            "id": "background_worker_performance",
            "revision": 60,
            "icon": "speed",
            "title": qsTr("Background Worker Thread"),
            "description": qsTr("Ticking background services are now offloaded to a dedicated worker thread with queued connections, reducing shell latency and eliminating unnecessary desktop redraws.")
        },
        {
            "id": "notification_markup_links",
            "revision": 61,
            "icon": "chat",
            "title": qsTr("Rich Notification Formatting"),
            "description": qsTr("Notifications in both popups and the sidebar now cleanly sanitize FreeDesktop markup, auto-link web URLs, and preserve paragraph formatting.")
        },
        {
            "id": "shimeji-cat",
            "revision": 62,
            "icon": "pets",
            "title": qsTr("Shimeji Cat update"),
            "settingsPage": "plugins",
            "settingsSubPage": 1,
            "description": qsTr("Multiple Shimeji Cats can now be summoned at once. Also a fix regarding the cat hiding when clicking desktop has been pushed.")
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
