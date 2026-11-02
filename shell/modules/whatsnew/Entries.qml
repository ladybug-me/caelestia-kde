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
            "description": qsTr("Added Cheaper Inference as a supported assistant provider in AI settings, allowing seamless integration with cost-effective cloud AI inference models alongside existing local and cloud providers.")
        },
        {
            "id": "accessibility_suite",
            "revision": 67,
            "icon": "accessibility_new",
            "title": qsTr("Accessibility Controls"),
            "settingsPage": "session",
            "settingsSubPage": 5,
            "description": qsTr("A dedicated Accessibility page in Nexus provides instant controls for screen magnification, colour inversion, high-contrast filters, reduced motion, and on-screen keyboard options to suit your workflow.")
        },
        {
            "id": "captive_portal_and_proxy",
            "revision": 68,
            "icon": "wifi_find",
            "title": qsTr("Captive Portal & Proxy Settings"),
            "settingsPage": "network",
            "settingsSubPage": 8,
            "description": qsTr("The shell now automatically detects public and hotel captive Wi-Fi portals with one-click sign-in prompts, alongside comprehensive system proxy configuration options in Network settings.")
        },
        {
            "id": "dock_recent_files",
            "revision": 69,
            "icon": "history",
            "title": qsTr("Dock Recent Files & Jump Lists"),
            "description": qsTr("Pinned and running applications on the dock now display their recently accessed documents and jump-list actions directly in their right-click context menus for faster resumption.")
        },
        {
            "id": "nexus_keyboard_navigation",
            "revision": 70,
            "icon": "keyboard",
            "title": qsTr("Nexus Keyboard Navigation"),
            "description": qsTr("Nexus settings now offers full keyboard accessibility: press Meta+U to open Nexus, '/' to jump immediately into search, arrow keys and Tab to navigate categories and controls, and hold-to-confirm key captures.")
        },
        {
            "id": "window_tiling_live_reload",
            "revision": 71,
            "icon": "view_quilt",
            "title": qsTr("Instant Window Tiling Reload"),
            "settingsPage": "desktop",
            "settingsSubPage": 3,
            "description": qsTr("Krohnkite window tiling settings now reload and apply dynamically in real time without requiring a session logout or restart when tweaking tiling layouts, rules, and window gaps.")
        },
        {
            "id": "toast_positioning_and_radius",
            "revision": 72,
            "icon": "flip_to_front",
            "title": qsTr("Toast Positioning & Corner Rounding"),
            "settingsPage": "displays",
            "settingsSubPage": 7,
            "description": qsTr("Toast notification banners can now be anchored to any corner of the screen (top-left, top-right, bottom-left, bottom-right) with configurable corner radii and independent surface styling rules.")
        },
        {
            "id": "startup_applications_manager",
            "revision": 73,
            "icon": "rocket_launch",
            "title": qsTr("Startup Applications Manager"),
            "settingsPage": "session",
            "settingsSubPage": 6,
            "description": qsTr("Easily manage programs that run when you log in through Nexus. View all configured autostart entries, toggle individual background services, and add new apps with the integrated application picker.")
        },
        {
            "id": "storage_management",
            "revision": 74,
            "icon": "hard_drive",
            "title": qsTr("Disk & Storage Management"),
            "settingsPage": "session",
            "settingsSubPage": 8,
            "description": qsTr("Nexus now includes a dedicated Disk & Storage settings page to inspect mounted drives, monitor filesystem capacity and partition health, and safely mount, unmount, or eject external USB media.")
        },
        {
            "id": "utilities_countdown_timers",
            "revision": 75,
            "icon": "timer",
            "title": qsTr("Countdown Timers & Quick Toggles"),
            "settingsPage": "utilities",
            "settingsSubPage": 4,
            "description": qsTr("The Utilities drawer introduces persistent countdown timers that survive shell restarts, pin active timers directly to the taskbar, and convert utilities like Keep Awake into persistent quick toggles.")
        },
        {
            "id": "tray_customization_reorder",
            "revision": 76,
            "icon": "apps",
            "title": qsTr("System Tray Ordering & Renaming"),
            "settingsPage": "panels",
            "settingsSubPage": 9,
            "description": qsTr("The taskbar system tray now provides granular per-icon control: set icons to Always Visible, Collapsible, or Hidden, drag and drop to reorder pinned tray items, and assign custom display names and tooltips.")
        },
        {
            "id": "shell_animation_presets",
            "revision": 77,
            "icon": "animation",
            "title": qsTr("Shell Animation Presets"),
            "settingsPage": "appearance",
            "settingsSubPage": 7,
            "description": qsTr("Fine-tune interface motion with new shell animation presets, allowing you to choose between expressive motion, standard timing, snappy transitions, or instant response across all panels and drawers. You can also switch animation profiles from launcher by typing > and selecting Animations.")
        },
        {
            "id": "display_hdr_management",
            "revision": 78,
            "icon": "monitor",
            "title": qsTr("Display & HDR Management"),
            "settingsPage": "displays",
            "settingsSubPage": 0,
            "description": qsTr("Manage multiple monitors seamlessly within Nexus: configure display resolutions, refresh rates, monitor rotation, fractional HiDPI scaling, and High Dynamic Range (HDR) toggles all in one place.")
        },
        {
            "id": "focus_sessions_schedule",
            "revision": 79,
            "icon": "bedtime",
            "title": qsTr("Focus Sessions & Meeting DND"),
            "settingsPage": "displays",
            "settingsSubPage": 9,
            "description": qsTr("Focus Sessions let you schedule distraction-free work periods that automatically silence notifications and dim background distractions, with optional automated start whenever calendar meetings begin.")
        },
        {
            "id": "calendar_agenda_sync",
            "revision": 80,
            "icon": "calendar_month",
            "title": qsTr("Calendar Agenda & Google Calendar Sync"),
            "settingsPage": "session",
            "settingsSubPage": 3,
            "description": qsTr("The taskbar calendar synchronizes with Google Calendar and remote ICS feeds to display upcoming meeting agendas and event schedules, with hover activation and direct link access right from the bar.")
        },
        {
            "id": "launcher_krunner_search",
            "revision": 81,
            "icon": "manage_search",
            "title": qsTr("KRunner System Search in Launcher"),
            "description": qsTr("The launcher now integrates with KDE's KRunner search service to execute math equations, locate system files and browser bookmarks, look up system settings, and configure custom web search engines. Type > to open commands and select Search everything.")
        },
        {
            "id": "nexus_three_panel_redesign",
            "revision": 82,
            "icon": "tune",
            "title": qsTr("Three-Panel Nexus Settings"),
            "settingsPage": "appearance",
            "settingsSubPage": 1,
            "description": qsTr("Nexus settings has been overhauled with a three-panel layout displaying sections, subcategories, and active settings side by side. It folds smoothly into two panels on compact screens, and introduces an integrated system font picker previewing every installed typeface.")
        },
        {
            "id": "plasma_audio_visualizer",
            "revision": 83,
            "icon": "graphic_eq",
            "title": qsTr("Plasma Audio Visualizer"),
            "settingsPage": "desktop",
            "settingsSubPage": 1,
            "description": qsTr("Desktop audio visualization is now powered by the native Plasma Audio Visualizer with multi-monitor positioning, idle auto-hiding, responsive geometry calculations, and multiple profiles.")
        },
        {
            "id": "skwd_wall_engine",
            "revision": 84,
            "icon": "wallpaper",
            "title": qsTr("New Wallpaper Engine"),
            "settingsPage": "appearance",
            "settingsSubPage": 5,
            "description": qsTr("Deep integration with the skwd-wall daemon brings high-performance animated and video wallpapers with thumbnail caching, automatic Material You smart color extraction via caelestia-color, and a new Library and Community wallpapers browser. Press Meta + X to open the new Wallpaper Switcher.")
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
