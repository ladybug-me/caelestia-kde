pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

QtObject {
    readonly property string assetDir: "../../assets/whatsnew/"

    readonly property var list: [
        {
            "id": "cheaper_inference_ai",
            "revision": 66,
            "icon": "smart_toy",
            "title": qsTr("Cheaper Inference AI Provider"),
            "settingsPage": "utilities",
            "settingsSubPage": 7,
            "description": qsTr("A new assistant provider in AI settings, on an OpenAI-compatible gateway.")
        },
        {
            "id": "accessibility_suite",
            "revision": 67,
            "icon": "accessibility_new",
            "title": qsTr("Accessibility Controls"),
            "settingsPage": "session",
            "settingsSubPage": 5,
            "description": qsTr("Magnifier, color inversion, contrast filters and on-screen keyboard in Nexus.")
        },
        {
            "id": "captive_portal_and_proxy",
            "revision": 68,
            "icon": "wifi_find",
            "title": qsTr("Captive Portal & Proxy Settings"),
            "settingsPage": "network",
            "settingsSubPage": 8,
            "description": qsTr("Wi-Fi sign-in prompts, plus a system proxy field in Nexus → Network.")
        },
        {
            "id": "dock_recent_files",
            "revision": 69,
            "icon": "history",
            "title": qsTr("Dock Recent Files & Jump Lists"),
            "description": qsTr("Right-click a dock icon for its recent files and jump-list actions.")
        },
        {
            "id": "nexus_keyboard_navigation",
            "revision": 70,
            "icon": "keyboard",
            "title": qsTr("Nexus Keyboard Navigation"),
            "description": qsTr("Meta+U opens Nexus; / jumps to search; arrows and Tab move between controls.")
        },
        {
            "id": "window_tiling_live_reload",
            "revision": 71,
            "icon": "view_quilt",
            "title": qsTr("Instant Window Tiling Reload"),
            "settingsPage": "desktop",
            "settingsSubPage": 3,
            "description": qsTr("Krohnkite tiling changes apply as you edit them, with no re-login.")
        },
        {
            "id": "toast_positioning_and_radius",
            "revision": 72,
            "icon": "flip_to_front",
            "title": qsTr("Toast Positioning & Corner Rounding"),
            "settingsPage": "displays",
            "settingsSubPage": 7,
            "description": qsTr("Toasts can sit in any corner, with their own radius and surface styling.")
        },
        {
            "id": "startup_applications_manager",
            "revision": 73,
            "icon": "rocket_launch",
            "title": qsTr("Startup Applications Manager"),
            "settingsPage": "session",
            "settingsSubPage": 6,
            "description": qsTr("Turn autostart entries on or off, or add an app, in Nexus → Session.")
        },
        {
            "id": "storage_management",
            "revision": 74,
            "icon": "hard_drive",
            "title": qsTr("Disk & Storage Management"),
            "settingsPage": "session",
            "settingsSubPage": 8,
            "description": qsTr("Mount, unmount and eject drives, and watch capacity, in Nexus → Session.")
        },
        {
            "id": "utilities_countdown_timers",
            "revision": 75,
            "icon": "timer",
            "title": qsTr("Countdown Timers & Quick Toggles"),
            "settingsPage": "utilities",
            "settingsSubPage": 4,
            "description": qsTr("Countdown timers that survive a restart, pinnable to the taskbar.")
        },
        {
            "id": "tray_customization_reorder",
            "revision": 76,
            "icon": "apps",
            "title": qsTr("System Tray Ordering & Renaming"),
            "settingsPage": "panels",
            "settingsSubPage": 9,
            "description": qsTr("Drag tray icons to reorder, and set each to always visible, collapsible or hidden.")
        },
        {
            "id": "shell_animation_presets",
            "revision": 77,
            "icon": "animation",
            "title": qsTr("Shell Animation Presets"),
            "settingsPage": "appearance",
            "settingsSubPage": 7,
            "description": qsTr("Motion presets under Nexus → Appearance; type > and pick Animations in the launcher.")
        },
        {
            "id": "display_hdr_management",
            "revision": 78,
            "icon": "monitor",
            "title": qsTr("Display & HDR Management"),
            "settingsPage": "displays",
            "settingsSubPage": 0,
            "description": qsTr("Resolution, refresh rate, rotation, scaling and HDR per monitor in Nexus.")
        },
        {
            "id": "focus_sessions_schedule",
            "revision": 79,
            "icon": "bedtime",
            "title": qsTr("Focus Sessions & Meeting DND"),
            "settingsPage": "displays",
            "settingsSubPage": 9,
            "description": qsTr("Schedule quiet hours, or let calendar meetings start a focus session.")
        },
        {
            "id": "calendar_agenda_sync",
            "revision": 80,
            "icon": "calendar_month",
            "title": qsTr("Calendar Agenda & Google Calendar Sync"),
            "settingsPage": "session",
            "settingsSubPage": 3,
            "description": qsTr("The bar calendar reads Google Calendar and ICS feeds; hover for the agenda.")
        },
        {
            "id": "launcher_krunner_search",
            "revision": 81,
            "icon": "manage_search",
            "title": qsTr("KRunner System Search in Launcher"),
            "description": qsTr("Type > and pick Search everything to run launcher searches through KRunner.")
        },
        {
            "id": "nexus_three_panel_redesign",
            "revision": 82,
            "icon": "tune",
            "title": qsTr("Three-Panel Nexus Settings"),
            "settingsPage": "appearance",
            "settingsSubPage": 1,
            "description": qsTr("Sections, subcategories and settings sit side by side, folding to two panels.")
        },
        {
            "id": "plasma_audio_visualizer",
            "revision": 83,
            "icon": "graphic_eq",
            "title": qsTr("Plasma Audio Visualizer"),
            "settingsPage": "desktop",
            "settingsSubPage": 1,
            "description": qsTr("The desktop audio visualiser runs on Plasma's native visualiser.")
        },
        {
            "id": "skwd_wall_engine",
            "revision": 84,
            "icon": "wallpaper",
            "title": qsTr("New Wallpaper Engine"),
            "settingsPage": "appearance",
            "settingsSubPage": 5,
            "description": qsTr("Animated and video wallpapers come from skwd-wall; Meta+X opens the switcher.")
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
