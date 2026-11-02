pragma Singleton

import QtQuick
import qs.utils

QtObject {
    readonly property list<var> pages: [
        {
            label: qsTr("Appearance"),
            key: "appearance",
            icon: "palette",
            description: qsTr("Wallpapers, colors, themes"),
            category: "personalization",
            settings: [
                { label: qsTr("Theme & Effects"), pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 },
                { label: qsTr("Font"), keywords: ["font", "typeface", "family", "text"], pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 },
                { label: qsTr("Monospace font"), keywords: ["monospace", "font", "code", "terminal"], pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 },
                { label: qsTr("Font scale"), keywords: ["font", "scale", "size", "text"], pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 },
                { label: qsTr("Colors"), keywords: ["accent", "palette", "scheme", "theme", "color"], pagePath: "wallandstyle/ColourSelect.qml", subPageIdx: 3 },
                { label: qsTr("Advanced color settings"), keywords: ["advanced", "colors", "palette", "saturation", "contrast", "matugen"], pagePath: "wallandstyle/AdvancedColorsPage.qml", subPageIdx: 9 },
                { label: qsTr("Color intensity"), keywords: ["intensity", "chroma", "vibrant", "vibrancy"], pagePath: "wallandstyle/AdvancedColorsPage.qml", subPageIdx: 9 },
                { label: qsTr("Blur & Opacity"), pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 },
                { label: qsTr("Corner Radius"), keywords: ["rounding", "radius"], pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 },
                { label: qsTr("Wallpapers"), pagePath: "wallandstyle/WallpaperSelect.qml", subPageIdx: 1 },
                { label: qsTr("Wallhaven"), keywords: ["wallhaven", "download", "online", "search"], pagePath: "wallandstyle/WallhavenPage.qml", subPageIdx: 4 },
                { label: qsTr("Wallpaper settings"), keywords: ["filters", "thumbnails", "wallpaper"], pagePath: "wallandstyle/WallpaperSettingsPage.qml", subPageIdx: 5 },
                { label: qsTr("Library & Components"), keywords: ["library", "community", "wallhaven", "online", "tags"], pagePath: "wallandstyle/LibraryAndCommunityPage.qml", subPageIdx: 6 },
                { label: qsTr("Lock Screen"), keywords: ["lock", "wallpaper sync", "screen lock"], pagePath: "wallandstyle/LockScreenPage.qml", subPageIdx: 8 },
                { label: qsTr("Fingerprint"), keywords: ["fingerprint", "unlock", "attempts", "tries", "howdy", "biometric"], pagePath: "wallandstyle/LockScreenPage.qml", subPageIdx: 8 },
                { label: qsTr("Bezel mode"), keywords: ["pitch black", "bezels", "black", "theme and effects"], pagePath: "wallandstyle/AppearancePage.qml", subPageIdx: 7 }
            ]
        },
        {
            label: qsTr("Desktop & Tiling"),
            key: "desktop",
            icon: "desktop_windows",
            description: qsTr("Desktop, addons, tiling"),
            category: "personalization",
            settings: [
                { label: qsTr("Desktop"), pagePath: "desktop/DesktopSettingsPage.qml", keywords: ["plasma", "icons", "desktop", "integration"], subPageIdx: 4 },
                { label: qsTr("Desktop Addons"), pagePath: "desktop/DesktopAddonsPage.qml", subPageIdx: 1 },
                { label: qsTr("Right Click Menu"), pagePath: "desktop/ContextMenuPage.qml", subPageIdx: 2 },
                { label: qsTr("Window Tiling"), pagePath: "desktop/KrohnkitePage.qml", keywords: ["krohnkite", "tiling", "layouts"], subPageIdx: 3 },
                { label: qsTr("Floating windows"), keywords: ["floating", "float", "krohnkite"], pagePath: "desktop/KrohnkitePage.qml", subPageIdx: 3 },
                { label: qsTr("Virtual Workspaces"), keywords: ["desktops", "virtual", "switcher"] }
            ]
        },
        {
            label: qsTr("Panels & Interface"),
            key: "panels",
            icon: "dock_to_bottom",
            description: qsTr("Dashboard, taskbar, launcher"),
            category: "personalization",
            settings: [
                { label: qsTr("Taskbar"), pagePath: "panels/TaskbarPanel.qml", keywords: ["per-monitor", "position", "screen"], subPageIdx: 2 },
                { label: qsTr("Dashboard"), pagePath: "panels/DashboardPanel.qml", subPageIdx: 1 },
                { label: qsTr("Launcher"), pagePath: "panels/LauncherPanel.qml", subPageIdx: 3 },
                { label: qsTr("App browser layout"), keywords: ["launcher", "layout", "simple", "compact", "categories", "favourites"], pagePath: "panels/LauncherPanel.qml", subPageIdx: 3 },
                { label: qsTr("Truncated app names"), keywords: ["launcher", "name", "truncated", "long", "tooltip", "shrink", "flip"], pagePath: "panels/LauncherPanel.qml", subPageIdx: 3 },
                { label: qsTr("Clipboard"), keywords: ["history", "copied", "paste", "maximum entries", "history size", "confirm clear"], pagePath: "panels/LauncherPanel.qml", subPageIdx: 3 },
                { label: qsTr("Sidebar"), pagePath: "panels/SidebarPanel.qml", subPageIdx: 4 },
                { label: qsTr("Quick Toggles Panel"), pagePath: "panels/UtilitiesPanel.qml", subPageIdx: 5 },
                { label: qsTr("Overview"), pagePath: "panels/OverviewPanel.qml", keywords: ["overview", "animations", "blur"], subPageIdx: 16 },
                { label: qsTr("Toggle & Rearrange"), keywords: ["widgets", "components", "reorder", "add"], pagePath: "panels/taskbar/BarComponents.qml", subPageIdx: 6 },
                { label: qsTr("Workspaces indicator"), keywords: ["workspaces", "indicators", "window icons"], pagePath: "panels/taskbar/BarWorkspaces.qml", subPageIdx: 7 },
                { label: qsTr("Unoccupied workspaces"), keywords: ["workspaces", "empty", "inactive", "hide"], pagePath: "panels/taskbar/BarWorkspaces.qml", subPageIdx: 7 },
                { label: qsTr("Greeter"), keywords: ["greeting", "popout"], pagePath: "panels/taskbar/BarGreeter.qml", subPageIdx: 8 },
                { label: qsTr("Greeter slideshow"), keywords: ["slideshow", "folders", "media", "greeting", "timing", "order"], pagePath: "panels/taskbar/BarGreeter.qml", subPageIdx: 8 },
                { label: qsTr("Tray"), keywords: ["system tray", "icons", "always visible", "collapse", "hidden", "overflow", "pin"], pagePath: "panels/taskbar/BarTray.qml", subPageIdx: 9 },
                { label: qsTr("Status icons"), keywords: ["indicators", "bar"], pagePath: "panels/taskbar/BarStatusIcons.qml", subPageIdx: 10 },
                { label: qsTr("Clock"), keywords: ["date", "time"], pagePath: "panels/taskbar/BarClock.qml", subPageIdx: 11 },
                { label: qsTr("Clock seconds"), keywords: ["clock", "time", "seconds", "show seconds"], pagePath: "panels/taskbar/BarClock.qml", subPageIdx: 11 },
                { label: qsTr("Dock"), keywords: ["dock", "pinned", "apps", "grouping", "ungroup", "combine"], pagePath: "panels/taskbar/BarDock.qml", subPageIdx: 12 },
                { label: qsTr("GitHub"), keywords: ["github", "contributions", "token"], pagePath: "panels/taskbar/BarGithub.qml", subPageIdx: 13 },
                { label: qsTr("Media"), keywords: ["media", "music", "player", "spotify", "youtube", "now playing", "volume", "visualiser"], pagePath: "panels/taskbar/BarMedia.qml", subPageIdx: 19 },
                { label: qsTr("Weather"), keywords: ["weather", "temperature", "units", "celsius", "fahrenheit", "city"], pagePath: "panels/taskbar/BarWeather.qml", subPageIdx: 20 },
                { label: qsTr("Performance"), keywords: ["performance", "cpu", "gpu", "ram", "memory", "storage", "network", "battery", "pills", "stats"], pagePath: "panels/taskbar/BarPerformance.qml", subPageIdx: 21 },
                { label: qsTr("Screen Capture"), keywords: ["screenshot", "recording", "region", "spectacle", "gif"], pagePath: "panels/taskbar/BarScreenCapture.qml", subPageIdx: 22 },
                { label: qsTr("Keep Awake"), keywords: ["idle", "inhibit", "sleep", "caffeine", "coffee"], pagePath: "panels/taskbar/BarKeepAwake.qml", subPageIdx: 23 },
                { label: qsTr("Per-element scaling offsets"), keywords: ["scale", "font scale", "preview"], pagePath: "panels/taskbar/BarPreviewScales.qml", subPageIdx: 14 },
                { label: qsTr("Elements & Modules"), keywords: ["workspaces", "tray", "clock", "modules"], pagePath: "panels/taskbar/TaskbarElements.qml", subPageIdx: 15 },
                { label: qsTr("Update indicator"), keywords: ["updates", "indicator"], pagePath: "panels/taskbar/BarUpdates.qml", subPageIdx: 17 },
                { label: qsTr("Preview scale"), keywords: ["preview", "thumbnails", "scale"], pagePath: "panels/TaskbarPanel.qml", subPageIdx: 2 },
                { label: qsTr("Performance"), keywords: ["performance widgets", "dashboard", "randomize shape colors", "cpu", "memory", "storage"], pagePath: "panels/DashboardPanel.qml", subPageIdx: 1 },
                { label: qsTr("Dashboard clock seconds"), keywords: ["clock", "seconds", "dashboard", "time"], pagePath: "panels/DashboardPanel.qml", subPageIdx: 1 },
                { label: qsTr("Fuzzy search"), keywords: ["launcher", "search", "fuzzy"], pagePath: "panels/LauncherPanel.qml", subPageIdx: 3 },
                { label: qsTr("Activation"), keywords: ["hot corner", "bottom left corner", "bottom right corner", "gestures", "overview"], pagePath: "panels/OverviewPanel.qml", subPageIdx: 16 },
                { label: qsTr("Window Switcher"), keywords: ["tab switcher", "alt+tab", "task switcher", "desktop", "preview", "filter", "windows"], pagePath: "panels/TabSwitcherPanel.qml", subPageIdx: 18 }
            ]
        },
        {
            label: qsTr("Network & Connectivity"),
            key: "network",
            icon: "wifi",
            description: qsTr("Wi-Fi, Bluetooth, network"),
            category: "connectivity",
            settings: [
                { label: qsTr("Wi-Fi & Connection"), keywords: ["wireless", "internet", "connections", "network"], pagePath: "network/NetworkPage.qml", subPageIdx: 0 },
                { label: qsTr("VPN"), keywords: ["vpn", "tunnel", "secure"], subPageIdx: 0 },
                { label: qsTr("IPv4"), keywords: ["ethernet", "ip address", "dhcp", "gateway"], subPageIdx: 0 },
                { label: qsTr("All networks"), keywords: ["list", "available", "scan"], pagePath: "network/AllNetworksPage.qml", subPageIdx: 5 },
                { label: qsTr("Saved networks"), keywords: ["remembered", "forget", "profiles"], pagePath: "network/SavedNetworksPage.qml", subPageIdx: 6 },
                { label: qsTr("Hotspot"), keywords: ["hotspot", "tethering", "access point", "share connection"], pagePath: "network/HotspotPage.qml", subPageIdx: 7 },
                { label: qsTr("Captive portal"), keywords: ["captive", "portal", "sign in", "login", "hotel", "airport", "wifi"], subPageIdx: 0 },
                { label: qsTr("Proxy"), keywords: ["proxy", "http", "socks", "pac", "kioslaverc"], pagePath: "network/ProxyPage.qml", subPageIdx: 8 },
                { label: qsTr("Bluetooth"), keywords: ["wireless", "devices", "accessories", "bluetooth"], pagePath: "BluetoothPage.qml", subPageIdx: 10 },
                { label: qsTr("Discoverable"), keywords: ["discoverable", "visibility", "bluetooth"], pagePath: "BluetoothPage.qml", subPageIdx: 10 },
                { label: qsTr("Pairable"), keywords: ["pairable", "bluetooth"], pagePath: "BluetoothPage.qml", subPageIdx: 10 },
                { label: qsTr("Pair New Device"), keywords: ["pairing", "pair", "search", "bluetooth"], pagePath: "bluetooth/BluetoothPairing.qml", subPageIdx: 12 }
            ]
        },
        {
            label: qsTr("Display & Sound"),
            key: "displays",
            icon: "monitor",
            description: qsTr("Displays, audio, notifications"),
            category: "connectivity",
            settings: [
                { label: qsTr("Layout & Scale"), keywords: ["displays", "scale", "fractional", "zoom", "hidpi", "screen"], pagePath: "display/DisplayPage.qml", subPageIdx: 0 },
                { label: qsTr("Resolution"), keywords: ["mode", "refresh rate", "hz", "screen", "monitor"], pagePath: "display/DisplayModesPage.qml", subPageIdx: 1 },
                { label: qsTr("Refresh rate"), keywords: ["hz", "mode", "screen", "monitor"], pagePath: "display/DisplayModesPage.qml", subPageIdx: 1 },
                { label: qsTr("Rotation"), keywords: ["rotate", "orientation", "portrait", "screen"], pagePath: "display/DisplayPage.qml", subPageIdx: 0 },
                { label: qsTr("HDR"), keywords: ["hdr", "dynamic range", "screen"], pagePath: "display/DisplayPage.qml", subPageIdx: 0 },
                { label: qsTr("Output & Input"), keywords: ["speakers", "output", "volume", "playback", "sink", "microphone", "recording", "source"], pagePath: "audio/AudioPage.qml", subPageIdx: 2 },
                { label: qsTr("App Volumes"), keywords: ["app", "volume", "stream", "per-app"], pagePath: "audio/AppVolumes.qml", subPageIdx: 3 },
                { label: qsTr("Sound Effects"), keywords: ["sfx", "feedback", "camera", "screen lock", "sounds"], pagePath: "audio/SoundEffectsPage.qml", subPageIdx: 4 },
                { label: qsTr("Notification Silence"), keywords: ["silence", "mute", "muted", "turn off notifications", "hide notifications", "notification sound", "do not disturb"], pagePath: "audio/NotificationSilencingPage.qml", subPageIdx: 5 },
                { label: qsTr("Preferences"), keywords: ["notifications", "fullscreen", "position", "timeout", "taskbar"], pagePath: "services/NotificationPreferencesPage.qml", subPageIdx: 6 },
                { label: qsTr("Toasts"), keywords: ["popup", "banner", "sound", "volume"], pagePath: "services/ToastPreferencesPage.qml", subPageIdx: 7 },
                { label: qsTr("Toast events"), keywords: ["charging", "clipboard", "vpn", "keyboard", "audio"], pagePath: "services/ToastEventsPage.qml", subPageIdx: 8 },
                { label: qsTr("Focus sessions"), keywords: ["do not disturb", "dnd", "schedule", "focus", "quiet"], pagePath: "services/FocusPage.qml", subPageIdx: 9 }
            ]
        },
        {
            label: qsTr("Utilities & Tools"),
            key: "utilities",
            icon: "build",
            description: qsTr("Sliders, game mode, AI"),
            category: "controls",
            settings: [
                { label: qsTr("On-screen slider"), keywords: ["volume", "microphone", "brightness", "osd", "slider"], pagePath: "utilities/OsdPage.qml", subPageIdx: 3 },
                { label: qsTr("Utilities panel"), keywords: ["keep awake", "screenshot", "record", "utilities"], pagePath: "utilities/UtilitiesPanelPage.qml", subPageIdx: 4 },
                { label: qsTr("Quick toggles"), keywords: ["toggles", "dashboard", "switches"], pagePath: "utilities/QuickTogglesPage.qml", subPageIdx: 5 },
                { label: qsTr("Game Mode"), keywords: ["hyprland overrides", "performance", "games", "game mode"], pagePath: "services/GameModePage.qml", subPageIdx: 1 },
                { label: qsTr("Auto-enable rules"), keywords: ["game mode", "rules", "target windows"], pagePath: "services/GameModeTargetsPage.qml", subPageIdx: 2 },
                { label: qsTr("Quick share"), keywords: ["bluetooth", "nearby", "file sharing", "send file", "receive file", "android"], pagePath: "services/QuickSharePage.qml", subPageIdx: 6 },
                { label: qsTr("AI Configuration"), keywords: ["claude", "ai", "llm", "cli", "assistant", "accounts", "providers", "ollama", "openai"], pagePath: "AiSettingsPage.qml", subPageIdx: 7 }
            ]
        },
        {
            label: qsTr("Applications & Shortcuts"),
            key: "apps",
            icon: "apps",
            description: qsTr("Default apps, shortcuts"),
            category: "shell",
            settings: [
                { label: qsTr("Default Applications"), keywords: ["browser", "email", "default", "open with"], pagePath: "AppsPage.qml", subPageIdx: 0 },
                { label: qsTr("File Types"), keywords: ["associations", "extensions", "open with"], pagePath: "AppsPage.qml", subPageIdx: 0 },
                { label: qsTr("Installed Applications"), keywords: ["installed", "list", "all apps", "uninstall"], pagePath: "apps/AllApps.qml", subPageIdx: 1 },
                { label: qsTr("Favorites & Hidden"), keywords: ["pinned", "dock", "launcher", "ignore"], pagePath: "apps/AllApps.qml", subPageIdx: 1 },
                { label: qsTr("Keyboard Shortcuts"), keywords: ["global", "keys", "hotkeys", "keybinds", "shortcuts"], pagePath: "ShortcutManagerPage.qml", subPageIdx: 3 },
                { label: qsTr("Custom Keybinds"), keywords: ["scripts", "commands", "actions"], pagePath: "ShortcutManagerPage.qml", subPageIdx: 3 }
            ]
        },
        {
            label: qsTr("System & Services"),
            key: "services",
            icon: "settings_suggest",
            description: qsTr("Session, services, storage, about"),
            category: "system",
            settings: [
                { label: qsTr("Session settings"), keywords: ["power", "shutdown", "logout", "reboot", "hibernate"], pagePath: "SessionPage.qml", subPageIdx: 0 },
                { label: qsTr("System Services"), keywords: ["daemons", "systemd", "tuning", "visualiser", "microphone", "cava"], pagePath: "ServicesPage.qml", subPageIdx: 1 },
                { label: qsTr("Remote IPC"), keywords: ["discord", "steamgriddb", "activity", "arpc", "rpc"], pagePath: "services/ArpcPage.qml", subPageIdx: 2 },
                { label: qsTr("Calendar Integration"), keywords: ["agenda", "events", "ics", "ical", "google", "nextcloud", "reminder"], pagePath: "services/CalendarPage.qml", subPageIdx: 3 },
                { label: qsTr("Language & Format"), keywords: ["locale", "translation", "ui", "clock", "timezone", "format"], pagePath: "LanguageAndRegion.qml", subPageIdx: 4 },
                { label: qsTr("Accessibility"), keywords: ["font scale", "reduce motion", "magnifier", "invert colours", "colour filters", "screen reader", "a11y"], pagePath: "services/AccessibilityPage.qml", subPageIdx: 5 },
                { label: qsTr("Startup Applications"), keywords: ["login", "startup", "autostart", "boot", "session"], pagePath: "startup/AutostartPage.qml", subPageIdx: 6 },
                { label: qsTr("Add to startup"), keywords: ["add", "application", "login"], pagePath: "startup/AutostartAppPicker.qml", subPageIdx: 7 },
                { label: qsTr("Disk & Storage"), keywords: ["mount", "usb", "disk", "partition", "filesystem", "drive", "unmount", "eject"], pagePath: "StoragePage.qml", subPageIdx: 8 },
                { label: qsTr("Caelestia Plugins"), keywords: ["extensions", "addons", "plugins"], pagePath: "PluginsPage.qml", subPageIdx: 9 },
                { label: qsTr("Updates"), keywords: ["upgrade", "packages", "pacman", "dnf", "apt", "firmware"], pagePath: "UpdatesPage.qml", subPageIdx: 10 },
                { label: qsTr("About System"), keywords: ["hardware", "specs", "cpu", "ram", "caelestia", "quickshell", "release", "uninstall"], pagePath: "AboutPage.qml", subPageIdx: 11 }
            ]
        }
    ]

    readonly property var keyAliases: ({
        "appearance": 0,
        "desktop": 1,
        "panels": 2,
        "network": 3,
        "bluetooth": 3,
        "displays": 4,
        "display": 4,
        "audio": 4,
        "notifications": 4,
        "utilities": 5,
        "ai": 5,
        "apps": 6,
        "shortcuts": 6,
        "session": 7,
        "services": 7,
        "language": 7,
        "accessibility": 7,
        "startup": 7,
        "storage": 7,
        "plugins": 7,
        "updates": 7,
        "about": 7,
        "system": 7
    })

    readonly property var defaultSubPages: ({
        "appearance": 1,
        "desktop": 4,
        "panels": 1,
        "network": 0,
        "bluetooth": 10,
        "displays": 0,
        "display": 0,
        "audio": 2,
        "notifications": 6,
        "utilities": 3,
        "ai": 7,
        "apps": 0,
        "shortcuts": 3,
        "session": 0,
        "services": 1,
        "arpc": 2,
        "calendar": 3,
        "language": 4,
        "accessibility": 5,
        "startup": 6,
        "storage": 8,
        "plugins": 9,
        "updates": 10,
        "about": 11,
        "system": 0,
        "startupAppPicker": 7,
        "btDeviceInfo": 11,
        "bluetoothPairing": 12,
        "appVolumes": 3,
        "soundEffects": 4,
        "notificationSilencing": 5,
        "notificationPreferences": 6,
        "toastPreferences": 7,
        "toastEvents": 8,
        "focus": 9,
        "quickToggles": 5
    })

    function defaultSubPageForKey(key: string): int {
        return defaultSubPages[key] !== undefined ? defaultSubPages[key] : -1;
    }

    /// Index of the page with this key, so shortcuts do not have to remember a position
    /// that shifts whenever a page is added.
    function pageIdxFor(key: string): int {
        if (keyAliases[key] !== undefined)
            return keyAliases[key];
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].key === key)
                return i;
        }
        return -1;
    }

    // Sub page index of the first entry pointing at the given page, or -1 when
    // no entry does. Callers that jump to a sub page should look it up instead
    // of hardcoding the number: inserting a sub page anywhere in the registry
    // shifts every index after it, which silently repoints shortcuts.
    function subPageIdxFor(pagePath: string): int {
        for (let i = 0; i < pages.length; i++) {
            const settings = pages[i].settings || [];
            for (let j = 0; j < settings.length; j++) {
                if (settings[j].pagePath === pagePath)
                    return settings[j].subPageIdx;
            }
        }
        return -1;
    }
}
