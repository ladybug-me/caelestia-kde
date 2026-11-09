pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages
import qs.modules.nexus.pages.apps
import qs.modules.nexus.pages.audio
import qs.modules.nexus.pages.bluetooth
import qs.modules.nexus.pages.desktop
import qs.modules.nexus.pages.display
import qs.modules.nexus.pages.network
import qs.modules.nexus.pages.panels
import qs.modules.nexus.pages.services
import qs.modules.nexus.pages.startup
import qs.modules.nexus.pages.utilities
import qs.modules.nexus.pages.wallandstyle
import qs.modules.nexus.pages.panels.taskbar

QtObject {
    id: root

    readonly property Component hubPageComp: Component {
        CategoryHubPage {}
    }

    readonly property SubPage hubSubPage: SubPage {
        slot: 0
        key: "hub"
        component: root.hubPageComp
    }

    readonly property Component placeholderComp: Component {
        PlaceholderComp {}
    }

    readonly property list<Category> categories: [
        Category {
            categoryIdx: 0
            key: "appearance"
            label: qsTr("Appearance")
            icon: "palette"
            description: qsTr("Wallpapers, colors, themes")
            defaultSlot: 1

            Page {
                slot: 1
                key: "wallpaperSelect"
                label: qsTr("Wallpapers")
                icon: "wallpaper"
                section: qsTr("Wallpaper")
                status: qsTr("Browse and select wallpapers")
                description: qsTr("Browse local wallpapers, online sources, and collections")
                keywords: ["wallpaper", "background", "image", "photo"]
                component: Component { WallpaperSelect {} }

                SubPage {
                    slot: 2
                    key: "wallpaperCategory"
                    label: qsTr("Wallpaper Category")
                    keywords: ["category", "collection", "tags"]
                    component: Component { WallpaperCategory {} }
                }
                SubPage {
                    slot: 4
                    key: "wallhaven"
                    label: qsTr("Wallhaven")
                    keywords: ["wallhaven", "download", "online", "search"]
                    component: Component { WallhavenPage {} }
                }
            }

            Page {
                slot: 6
                key: "libraryAndCommunity"
                label: qsTr("Library & Components")
                icon: "cloud_download"
                section: qsTr("Wallpaper")
                status: qsTr("Wallhaven, online wallpapers, tags and filters")
                description: qsTr("Community wallpaper sources, tag filters, and downloads")
                keywords: ["library", "community", "wallhaven", "online", "tags"]
                component: Component { LibraryAndCommunityPage {} }
            }

            Page {
                slot: 5
                key: "wallpaperSettings"
                label: qsTr("Wallpaper Settings")
                icon: "settings_suggest"
                section: qsTr("Wallpaper")
                status: Wallpapers.hasSkwd ? qsTr("Configure wallpaper engine, mixer, and effects") : qsTr("Configure scaling, recoloring, video playback, and slideshows")
                description: qsTr("Configure wallpaper engine, scaling, slideshow timing, and video playback")
                keywords: ["filters", "thumbnails", "scaling", "video", "slideshow"]
                component: Component { WallpaperSettingsPage {} }
            }

            Page {
                slot: 8
                key: "lockScreen"
                label: qsTr("Lock Screen")
                icon: "lock"
                section: qsTr("Lock Screen")
                status: qsTr("Wallpaper sync and lock screen settings")
                description: qsTr("Configure lock screen wallpaper sync and biometric fingerprint unlocking")
                keywords: ["lock", "wallpaper sync", "screen lock", "fingerprint", "biometric"]
                component: Component { LockScreenPage {} }
            }

            Page {
                slot: 3
                key: "colourSelect"
                label: qsTr("Colors")
                icon: "palette"
                section: qsTr("Colors")
                status: qsTr("Caelestia owns color management and not skwd-wall.")
                description: qsTr("Material You color palette, scheme styles, and accent colors")
                keywords: ["accent", "palette", "scheme", "theme", "color"]
                component: Component { ColourSelect {} }

                SubPage {
                    slot: 9
                    key: "advancedColors"
                    label: qsTr("Advanced Colors")
                    keywords: ["advanced", "contrast", "saturation", "matugen", "intensity"]
                    component: Component { AdvancedColorsPage {} }
                }
            }

            Page {
                slot: 7
                key: "appearance"
                label: qsTr("Theme & Effects")
                icon: "style"
                section: qsTr("Theme")
                status: qsTr("Islands, Pitch Black, Transparency")
                description: qsTr("UI blur, opacity, pitch black bezel mode, fonts, and corner radius")
                keywords: ["theme", "effects", "blur", "opacity", "corner radius", "font", "monospace", "bezel"]
                component: Component { AppearancePage {} }
            }

            Page {
                slot: 10
                key: "nexusSettings"
                label: qsTr("Nexus settings")
                icon: "tune"
                section: qsTr("Nexus")
                status: GlobalConfig.nexus.sidePane ? qsTr("3-pane layout") : qsTr("2-pane layout")
                description: qsTr("Nexus window layout and subcategory side pane")
                keywords: ["nexus", "layout", "sidepane", "subpanel", "side pane", "settings window"]
                component: Component { NexusSettingsPage {} }
            }
        },

        Category {
            categoryIdx: 1
            key: "desktop"
            label: qsTr("Desktop & Tiling")
            icon: "desktop_windows"
            description: qsTr("Desktop, addons, tiling")
            defaultSlot: 4

            Page {
                slot: 4
                key: "desktop"
                label: qsTr("Desktop")
                icon: "desktop_windows"
                status: Config.background.disableQuickshellDesktop ? qsTr("Disabled (Plasma)") : (Config.background.desktopIconsEnabled ? qsTr("Icons enabled") : qsTr("Icons disabled"))
                description: qsTr("Plasma desktop integration, desktop icons, and widget layout")
                keywords: ["plasma", "icons", "desktop", "integration"]
                component: Component { DesktopSettingsPage {} }
            }

            Page {
                slot: 1
                key: "desktopAddons"
                label: qsTr("Desktop Addons")
                icon: "extension"
                status: qsTr("Visualiser, auto-hide, styling")
                description: qsTr("Audio visualizer, wallpaper clock, auto-hide, and desktop widgets")
                enabled: !Config.background.disableQuickshellDesktop
                keywords: ["visualiser", "addons", "widgets", "clock"]
                component: Component { DesktopAddonsPage {} }
            }

            Page {
                slot: 2
                key: "contextMenu"
                label: qsTr("Right Click Menu")
                icon: "menu_open"
                status: qsTr("Configure desktop right click menu")
                description: qsTr("Customize desktop context menu entries, actions, and tools")
                enabled: !Config.background.disableQuickshellDesktop
                keywords: ["menu", "context", "right click", "desktop actions"]
                component: Component { ContextMenuPage {} }
            }

            Page {
                slot: 3
                key: "krohnkite"
                label: qsTr("Window Tiling")
                icon: "view_quilt"
                status: Config.general.krohnkiteEnabled ? qsTr("Enabled (Krohnkite)") : qsTr("Disabled")
                description: qsTr("Automatic window tiling, Krohnkite layout rules, and floating exceptions")
                keywords: ["krohnkite", "tiling", "layouts", "floating", "windows"]
                component: Component { KrohnkitePage {} }
            }
        },

        Category {
            categoryIdx: 2
            key: "panels"
            label: qsTr("Panels & Interface")
            icon: "dock_to_bottom"
            description: qsTr("Dashboard, taskbar, launcher")
            defaultSlot: 1

            Page {
                slot: 1
                key: "dashboard"
                label: qsTr("Dashboard")
                icon: "dashboard"
                status: Config.dashboard.enabled ? qsTr("Enabled") : qsTr("Disabled")
                description: qsTr("Performance monitor, media visualizer, and dashboard clock widgets")
                keywords: ["dashboard", "performance widgets", "stats", "clock"]
                component: Component { DashboardPanel {} }
            }

            Page {
                slot: 2
                key: "taskbar"
                label: qsTr("Taskbar")
                icon: "dock_to_bottom"
                status: Config.bar.persistent ? qsTr("Always visible") : Config.bar.showOnHover ? qsTr("Reveal on hover") : qsTr("Reveal on drag")
                description: qsTr("Bar position, visibility behavior, workspaces, tray, and dock modules")
                keywords: ["taskbar", "bar", "dock", "tray", "workspaces", "position"]
                component: Component { TaskbarPanel {} }

                SubPage { slot: 6; key: "barComponents"; label: qsTr("Components"); keywords: ["widgets", "components", "reorder"]; Component { BarComponents {} } }
                SubPage { slot: 7; key: "barWorkspaces"; label: qsTr("Workspaces"); keywords: ["workspaces", "indicators"]; Component { BarWorkspaces {} } }
                SubPage { slot: 8; key: "barGreeter"; label: qsTr("Greeter"); keywords: ["greeting", "popout", "slideshow"]; Component { BarGreeter {} } }
                SubPage { slot: 9; key: "barTray"; label: qsTr("Tray"); keywords: ["system tray", "icons", "pin"]; Component { BarTray {} } }
                SubPage { slot: 10; key: "barStatusIcons"; label: qsTr("Status Icons"); keywords: ["indicators", "bar"]; Component { BarStatusIcons {} } }
                SubPage { slot: 11; key: "barClock"; label: qsTr("Clock"); keywords: ["date", "time", "seconds"]; Component { BarClock {} } }
                SubPage { slot: 12; key: "barDock"; label: qsTr("Dock"); keywords: ["dock", "pinned", "apps", "grouping"]; Component { BarDock {} } }
                SubPage { slot: 13; key: "barGithub"; label: qsTr("GitHub"); keywords: ["github", "contributions", "token"]; Component { BarGithub {} } }
                SubPage { slot: 14; key: "barPreviewScales"; label: qsTr("Preview Scales"); keywords: ["scale", "offsets"]; Component { BarPreviewScales {} } }
                SubPage { slot: 15; key: "taskbarElements"; label: qsTr("Elements & Modules"); keywords: ["modules", "elements"]; Component { TaskbarElements {} } }
                SubPage { slot: 17; key: "barUpdates"; label: qsTr("Updates Indicator"); keywords: ["updates", "indicator"]; Component { BarUpdates {} } }
                SubPage { slot: 19; key: "barMedia"; label: qsTr("Media"); keywords: ["media", "player", "music"]; Component { BarMedia {} } }
                SubPage { slot: 20; key: "barWeather"; label: qsTr("Weather"); keywords: ["weather", "temperature", "forecast"]; Component { BarWeather {} } }
                SubPage { slot: 21; key: "barPerformance"; label: qsTr("Performance"); keywords: ["cpu", "gpu", "ram", "memory"]; Component { BarPerformance {} } }
                SubPage { slot: 22; key: "barScreenCapture"; label: qsTr("Screen Capture"); keywords: ["screenshot", "recording"]; Component { BarScreenCapture {} } }
                SubPage { slot: 23; key: "barKeepAwake"; label: qsTr("Keep Awake"); keywords: ["idle", "sleep", "caffeine"]; Component { BarKeepAwake {} } }
            }

            Page {
                slot: 3
                key: "launcher"
                label: qsTr("Launcher")
                icon: "apps"
                status: Config.launcher.enabled ? qsTr("Enabled") : qsTr("Disabled")
                description: qsTr("Application search, fuzzy matching, clipboard history, and categories")
                keywords: ["launcher", "search", "fuzzy", "clipboard", "layout"]
                component: Component { LauncherPanel {} }
            }

            Page {
                slot: 4
                key: "sidebar"
                label: qsTr("Sidebar")
                icon: "dock_to_right"
                status: Config.sidebar.enabled ? qsTr("Enabled") : qsTr("Disabled")
                description: qsTr("Slide-out sidebar, notifications, and quick widgets")
                keywords: ["sidebar", "dock_to_right", "drawer"]
                component: Component { SidebarPanel {} }
            }

            Page {
                slot: 5
                key: "utilitiesPanel"
                label: qsTr("Quick toggle")
                icon: "settings_input_component"
                status: Config.utilities.enabled ? qsTr("Enabled") : qsTr("Disabled")
                description: qsTr("Quick settings toggles panel layout and button ordering")
                keywords: ["quick toggle", "utilities", "toggles"]
                component: Component { UtilitiesPanel {} }
            }

            Page {
                slot: 16
                key: "overview"
                label: qsTr("Overview")
                icon: "view_carousel"
                status: Config.overview.enabled ? qsTr("Enabled") : qsTr("Disabled")
                description: qsTr("Window overview, workspace thumbnails, and gesture hot corners")
                keywords: ["overview", "gestures", "hot corner", "workspaces"]
                component: Component { OverviewPanel {} }
            }

            Page {
                slot: 18
                key: "tabSwitcher"
                label: qsTr("Window Switcher")
                icon: "view_array"
                status: !Config.tabSwitch.enabled ? qsTr("Disabled") : (Config.tabSwitch.currentDesktopOnly ? qsTr("Current desktop only") : qsTr("All desktops"))
                description: qsTr("Alt+Tab task switcher, window previews, and desktop filters")
                keywords: ["tab switcher", "alt+tab", "task switcher", "windows"]
                component: Component { TabSwitcherPanel {} }
            }

            Page {
                slot: 24
                key: "osdPanel"
                label: qsTr("OSD")
                icon: "tune"
                status: {
                    if (!GlobalConfig.osd.enabled) return qsTr("Disabled");
                    switch (GlobalConfig.osd.style) {
                        case "pill": return qsTr("Pill");
                        case "compact": return qsTr("Compact");
                        case "radial": return qsTr("Radial");
                        case "card": return qsTr("Card");
                        case "bar": return qsTr("Minimal Bar");
                        default: return qsTr("Default (Edge)");
                    }
                }
                description: qsTr("On-screen display styles, volume and brightness sliders, and positioning")
                keywords: ["osd", "volume", "brightness", "pill", "radial", "card", "slider"]
                component: Component { OsdPanel {} }
            }
        },

        Category {
            categoryIdx: 3
            key: "network"
            label: qsTr("Network & Connectivity")
            icon: "wifi"
            description: qsTr("Wi-Fi, Bluetooth, network")
            defaultSlot: 13

            Page {
                slot: 13
                key: "network"
                label: qsTr("Network")
                icon: "wifi"
                section: qsTr("Network")
                status: Nmcli.activeWifiSsid ? Nmcli.activeWifiSsid : (Nmcli.wifiEnabled ? qsTr("Disconnected") : qsTr("Disabled"))
                description: qsTr("Wi-Fi, wired ethernet, IPv4 gateways, and VPN tunnel connections")
                keywords: ["wireless", "internet", "connections", "network", "vpn", "ethernet"]
                component: Component { NetworkPage {} }

                SubPage { slot: 1; key: "ethernetDetail"; label: qsTr("Ethernet"); keywords: ["ethernet", "lan"]; Component { EthernetDetailPage {} } }
                SubPage { slot: 2; key: "addNetwork"; label: qsTr("Add Network"); keywords: ["wifi", "manual", "ssid"]; Component { AddNetworkPage {} } }
                SubPage { slot: 3; key: "networkDetail"; label: qsTr("Network Detail"); keywords: ["signal", "ip", "dns"]; Component { NetworkDetailPage {} } }
                SubPage { slot: 4; key: "addVpn"; label: qsTr("Add VPN"); keywords: ["vpn", "tunnel", "wireguard", "openvpn"]; Component { AddVpnPage {} } }
            }

            Page {
                slot: 5
                key: "allNetworks"
                label: qsTr("All Networks")
                icon: "network_check"
                section: qsTr("Network")
                status: qsTr("%1 available").arg(Nmcli.networks.length)
                description: qsTr("Scan and connect to available Wi-Fi access points")
                keywords: ["list", "available", "scan", "wifi"]
                component: Component { AllNetworksPage {} }
            }

            Page {
                slot: 6
                key: "savedNetworks"
                label: qsTr("Saved Networks")
                icon: "history"
                section: qsTr("Network")
                status: qsTr("Manage known connections")
                description: qsTr("Manage remembered Wi-Fi profiles and stored credentials")
                keywords: ["remembered", "forget", "profiles"]
                component: Component { SavedNetworksPage {} }
            }

            Page {
                slot: 7
                key: "hotspot"
                label: qsTr("Hotspot")
                icon: "wifi_tethering"
                section: qsTr("Network")
                status: Nmcli.hotspot.active ? qsTr("Active") : qsTr("Inactive")
                description: qsTr("Share network connection with other devices via Wi-Fi hotspot")
                keywords: ["hotspot", "tethering", "access point", "share connection"]
                component: Component { HotspotPage {} }
            }

            Page {
                slot: 8
                key: "proxy"
                label: qsTr("Proxy")
                icon: "vpn_key"
                section: qsTr("Network")
                status: qsTr("Network proxy settings")
                description: qsTr("HTTP, HTTPS, SOCKS, and automatic PAC proxy configurations")
                keywords: ["proxy", "http", "socks", "pac", "kioslaverc"]
                component: Component { ProxyPage {} }
            }

            Page {
                slot: 10
                key: "bluetooth"
                label: qsTr("Bluetooth")
                icon: "bluetooth"
                section: qsTr("Bluetooth")
                status: (Bluetooth.defaultAdapter?.enabled ?? false) ? qsTr("Enabled") : qsTr("Disabled")
                description: qsTr("Manage paired Bluetooth accessories, discoverable visibility, and audio sinks")
                keywords: ["wireless", "devices", "accessories", "bluetooth", "discoverable", "pairable"]
                component: Component { BluetoothPage {} }

                SubPage { slot: 11; key: "btDeviceInfo"; label: qsTr("Device Info"); keywords: ["battery", "device"]; Component { BtDeviceInfo {} } }
                SubPage { slot: 12; key: "bluetoothPairing"; label: qsTr("Pair New Device"); keywords: ["pairing", "pair", "search", "bluetooth"]; Component { BluetoothPairing {} } }
            }
        },

        Category {
            categoryIdx: 4
            key: "displays"
            label: qsTr("Display & Sound")
            icon: "monitor"
            description: qsTr("Displays, audio, notifications")
            defaultSlot: 11

            Page {
                slot: 11
                key: "displays"
                label: qsTr("Displays")
                icon: "display_settings"
                section: qsTr("Display")
                status: qsTr("%1 display(s) connected").arg(Displays.outputs.length)
                description: qsTr("Resolution, refresh rate, orientation, fractional scaling, and HDR")
                keywords: ["displays", "scale", "fractional", "zoom", "hidpi", "screen", "rotation", "hdr"]
                component: Component { DisplayPage {} }

                SubPage { slot: 1; key: "displayModes"; label: qsTr("Display Modes"); keywords: ["resolution", "mode", "refresh rate", "hz"]; Component { DisplayModesPage {} } }
            }

            Page {
                slot: 2
                key: "audio"
                label: qsTr("Audio")
                icon: "volume_up"
                section: qsTr("Sound & Audio")
                status: Audio.muted ? qsTr("Muted") : qsTr("%1%").arg(Math.round(Audio.volume * 100))
                description: qsTr("Output speakers, input microphones, master volume, and balances")
                keywords: ["speakers", "output", "volume", "playback", "sink", "microphone", "recording"]
                component: Component { AudioPage {} }

                SubPage { slot: 3; key: "appVolumes"; label: qsTr("App Volumes"); keywords: ["app", "volume", "stream", "per-app"]; Component { AppVolumes {} } }
                SubPage { slot: 4; key: "soundEffects"; label: qsTr("Sounds"); keywords: ["sfx", "feedback", "camera", "screen lock", "sounds"]; Component { SoundEffectsPage {} } }
                SubPage { slot: 5; key: "notificationSilencing"; label: qsTr("Muted Apps"); keywords: ["silence", "mute", "muted", "turn off notifications", "hide notifications"]; Component { NotificationSilencingPage {} } }
            }

            Page {
                slot: 6
                key: "notificationPreferences"
                label: qsTr("Notification Behaviour")
                icon: "notifications"
                section: qsTr("Notifications")
                status: qsTr("Position, timeout, and display behavior")
                description: qsTr("Notification banners, positions, timeouts, toasts, and focus sessions")
                keywords: ["notifications", "fullscreen", "position", "timeout", "taskbar"]
                component: Component { NotificationPreferencesPage {} }

                SubPage { slot: 7; key: "toastPreferences"; label: qsTr("Toasts"); keywords: ["popup", "banner", "sound", "volume"]; Component { ToastPreferencesPage {} } }
                SubPage { slot: 8; key: "toastEvents"; label: qsTr("Toast Events"); keywords: ["charging", "clipboard", "vpn", "keyboard", "audio"]; Component { ToastEventsPage {} } }
                SubPage { slot: 9; key: "focus"; label: qsTr("Focus Sessions"); keywords: ["do not disturb", "dnd", "schedule", "focus", "quiet"]; Component { FocusPage {} } }
                SubPage { slot: 10; key: "notifications"; label: qsTr("Notifications"); keywords: ["history", "alerts"]; Component { NotificationsPage {} } }
            }
        },

        Category {
            categoryIdx: 5
            key: "utilities"
            label: qsTr("Utilities & Tools")
            icon: "build"
            description: qsTr("Utilities panel, toggles, game mode, AI")
            defaultSlot: 4

            Page {
                slot: 4
                key: "utilitiesPanelPage"
                label: qsTr("Utilities panel")
                icon: "widgets"
                section: qsTr("Quick controls")
                status: qsTr("Choose the cards shown in the panel")
                description: qsTr("Choose cards and monitors pinned in the slide-out utilities panel")
                keywords: ["keep awake", "screenshot", "record", "utilities"]
                component: Component { UtilitiesPanelPage {} }
            }

            Page {
                slot: 5
                key: "quickToggles"
                label: qsTr("Quick toggles")
                icon: "toggle_on"
                section: qsTr("Quick controls")
                status: qsTr("Choose the controls shown in Quick Toggles")
                description: qsTr("Select which switches appear in the dashboard quick toggles")
                keywords: ["toggles", "dashboard", "switches"]
                component: Component { QuickTogglesPage {} }
            }

            Page {
                slot: 1
                key: "gameMode"
                label: qsTr("Game Mode")
                icon: "sports_esports"
                section: qsTr("Performance")
                status: qsTr("Auto-enable rules and performance overrides")
                description: qsTr("Performance mode, window rule targets, and GPU profile boosts")
                keywords: ["hyprland overrides", "performance", "games", "game mode"]
                component: Component { GameModePage {} }

                SubPage { slot: 2; key: "gameModeTargets"; label: qsTr("Auto-enable rules"); keywords: ["game mode", "rules", "target windows"]; Component { GameModeTargetsPage {} } }
            }

            Page {
                slot: 6
                key: "quickShare"
                label: qsTr("Quick Share")
                icon: "near_me"
                section: qsTr("File sharing")
                status: qsTr("Send files to nearby devices")
                description: qsTr("Nearby file sharing over Wi-Fi and Bluetooth to Android and Linux devices")
                keywords: ["bluetooth", "nearby", "file sharing", "send file", "receive file", "android"]
                component: Component { QuickSharePage {} }
            }

            Page {
                slot: 7
                key: "ai"
                label: qsTr("AI Assistant")
                icon: "smart_toy"
                section: qsTr("AI")
                status: qsTr("Models, providers, and parameters")
                description: qsTr("Ollama local models, Claude accounts, and API provider configurations")
                keywords: ["claude", "ai", "llm", "cli", "assistant", "accounts", "providers", "ollama", "openai"]
                component: Component { AiSettingsPage {} }
            }
        },

        Category {
            categoryIdx: 6
            key: "apps"
            label: qsTr("Applications & Shortcuts")
            icon: "apps"
            description: qsTr("Default apps, shortcuts")
            defaultSlot: 4

            Page {
                slot: 4
                key: "apps"
                label: qsTr("Apps")
                icon: "apps"
                status: qsTr("Default openers, installed apps, and search")
                description: qsTr("Default web browser, email client, file manager, and MIME file associations")
                keywords: ["browser", "email", "default", "open with", "associations"]
                component: Component { AppsPage {} }
            }

            Page {
                slot: 1
                key: "allApps"
                label: qsTr("All Apps")
                icon: "list_alt"
                status: qsTr("Browse and manage desktop apps")
                description: qsTr("Inspect installed applications, launcher favorites, and uninstalled items")
                keywords: ["installed", "list", "all apps", "uninstall", "favorites", "hidden"]
                component: Component { AllApps {} }

                SubPage { slot: 2; key: "appInfo"; label: qsTr("App Info"); keywords: ["app", "package", "version"]; Component { AppInfo {} } }
            }

            Page {
                slot: 3
                key: "shortcutManager"
                label: qsTr("Keyboard Shortcuts")
                icon: "keyboard"
                status: qsTr("View and configure shell keybindings")
                description: qsTr("Configure system hotkeys, window management keys, and custom scripts")
                keywords: ["global", "keys", "hotkeys", "keybinds", "shortcuts", "custom keybinds"]
                component: Component { ShortcutManagerPage {} }
            }
        },

        Category {
            categoryIdx: 7
            key: "services"
            label: qsTr("System & Services")
            icon: "settings_suggest"
            description: qsTr("Session, services, storage, about")
            defaultSlot: 12

            Page {
                slot: 12
                key: "session"
                label: qsTr("Session")
                icon: "power_settings_new"
                section: qsTr("System")
                status: qsTr("Power, lock, and logout options")
                description: qsTr("Shutdown, restart, sleep, hibernate, lock screen, and logout controls")
                keywords: ["power", "shutdown", "logout", "reboot", "hibernate"]
                component: Component { SessionPage {} }
            }

            Page {
                slot: 1
                key: "services"
                label: qsTr("System Services")
                icon: "build"
                section: qsTr("System")
                status: qsTr("Lyrics, GPU, and system integration")
                description: qsTr("Background services, cava audio visualizer, GPU monitors, and systemd daemons")
                keywords: ["daemons", "systemd", "tuning", "visualiser", "microphone", "cava"]
                component: Component { ServicesPage {} }
            }

            Page {
                slot: 4
                key: "language"
                label: qsTr("Language & Region")
                icon: "language"
                section: qsTr("System")
                status: qsTr("System locale, spellcheck, and formats")
                description: qsTr("Display language, regional formats, timezones, and spellcheck options")
                keywords: ["locale", "translation", "ui", "clock", "timezone", "format"]
                component: Component { LanguageAndRegion {} }
            }

            Page {
                slot: 5
                key: "accessibility"
                label: qsTr("Accessibility")
                icon: "accessibility_new"
                section: qsTr("System")
                status: qsTr("Vision, hearing, and interaction aids")
                description: qsTr("Font scale, motion reduction, color filters, and screen reader assistance")
                keywords: ["font scale", "reduce motion", "magnifier", "invert colours", "colour filters", "screen reader", "a11y"]
                component: Component { AccessibilityPage {} }
            }

            Page {
                slot: 8
                key: "storage"
                label: qsTr("Storage")
                icon: "storage"
                section: qsTr("System")
                status: qsTr("Mount points, free space, and drives")
                description: qsTr("Inspect disks, partition free space, mount points, and eject removable drives")
                keywords: ["mount", "usb", "disk", "partition", "filesystem", "drive", "unmount", "eject"]
                component: Component { StoragePage {} }
            }

            Page {
                slot: 11
                key: "about"
                label: qsTr("About")
                icon: "info"
                section: qsTr("System")
                status: qsTr("System specifications and versions")
                description: qsTr("Hardware specs, kernel release, Quickshell shell version, and license details")
                keywords: ["hardware", "specs", "cpu", "ram", "caelestia", "quickshell", "release", "uninstall"]
                component: Component { AboutPage {} }
            }

            Page {
                slot: 2
                key: "arpc"
                label: qsTr("Discord Rich Presence")
                icon: "sports_esports"
                section: qsTr("Services")
                status: qsTr("Broadcast your activity to Discord")
                description: qsTr("Connect system media playback and active games to Discord rich presence")
                keywords: ["discord", "steamgriddb", "activity", "arpc", "rpc"]
                component: Component { ArpcPage {} }
            }

            Page {
                slot: 3
                key: "calendar"
                label: qsTr("Calendar")
                icon: "calendar_today"
                section: qsTr("Services")
                status: qsTr("Sync calendar events and accounts")
                description: qsTr("Google, Nextcloud, and local ICS calendar sync with taskbar popout")
                keywords: ["agenda", "events", "ics", "ical", "google", "nextcloud", "reminder"]
                component: Component { CalendarPage {} }
            }

            Page {
                slot: 6
                key: "startup"
                label: qsTr("Startup Applications")
                icon: "rocket_launch"
                section: qsTr("Services")
                status: qsTr("Manage apps launched upon login")
                description: qsTr("Configure autostart programs, services, and background scripts on login")
                keywords: ["login", "startup", "autostart", "boot", "session"]
                component: Component { AutostartPage {} }

                SubPage { slot: 7; key: "startupAppPicker"; label: qsTr("Add to startup"); keywords: ["add", "application", "login"]; Component { AutostartAppPicker {} } }
            }

            Page {
                slot: 9
                key: "plugins"
                label: qsTr("Plugins")
                icon: "extension"
                section: qsTr("Services")
                status: qsTr("Manage installed extensions and add-ons")
                description: qsTr("Configure, enable, or disable Caelestia shell plugins and extensions")
                keywords: ["extensions", "addons", "plugins"]
                component: Component { PluginsPage {} }
            }

            Page {
                slot: 10
                key: "updates"
                label: qsTr("Updates")
                icon: "system_update"
                section: qsTr("Services")
                status: qsTr("Check for package and system updates")
                description: qsTr("Pacman, flatpak, firmware updates, and Caelestia shell version upgrades")
                keywords: ["upgrade", "packages", "pacman", "dnf", "apt", "firmware"]
                component: Component { UpdatesPage {} }
            }
        }
    ]

    readonly property list<Component> pageComps: [
        Component { StackPage { pages: root.collectAllPagesForCategory(0) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(1) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(2) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(3) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(4) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(5) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(6) } },
        Component { StackPage { pages: root.collectAllPagesForCategory(7) } }
    ]

    function collectAllPagesForCategory(catIdx: int): var {
        const cat = categories[catIdx];
        if (!cat) return [];
        const list = [root.hubSubPage];
        for (let i = 0; i < cat.pages.length; i++) {
            const p = cat.pages[i];
            list.push(p);
            if (p.subPages) {
                for (let j = 0; j < p.subPages.length; j++) {
                    list.push(p.subPages[j]);
                }
            }
        }
        return list;
    }

    function defaultSlotForCategory(idx: int): int {
        return (idx >= 0 && idx < categories.length) ? categories[idx].defaultSlot : 0;
    }

    function parentSlotFor(catIdx: int, slot: int): int {
        const cat = categories[catIdx];
        if (!cat) return slot;
        for (let i = 0; i < cat.pages.length; i++) {
            const page = cat.pages[i];
            if (page.slot === slot) return slot;
            const subs = page.subPages || [];
            for (let j = 0; j < subs.length; j++) {
                if (subs[j].slot === slot) return page.slot;
            }
        }
        return slot;
    }

    function slotForKey(key: string): int {
        for (let i = 0; i < categories.length; i++) {
            const pages = categories[i].pages;
            for (let j = 0; j < pages.length; j++) {
                if (pages[j].key === key) return pages[j].slot;
                const subs = pages[j].subPages || [];
                for (let k = 0; k < subs.length; k++) {
                    if (subs[k].key === key) return subs[k].slot;
                }
            }
        }
        return -1;
    }

    function categoryIdxForKey(key: string): int {
        for (let i = 0; i < categories.length; i++) {
            if (categories[i].key === key) return i;
            const pages = categories[i].pages;
            for (let j = 0; j < pages.length; j++) {
                if (pages[j].key === key) return i;
                const subs = pages[j].subPages || [];
                for (let k = 0; k < subs.length; k++) {
                    if (subs[k].key === key) return i;
                }
            }
        }
        return -1;
    }

    function subPageIdxFor(pathOrKey: string): int {
        const slot = slotForKey(pathOrKey);
        if (slot >= 0) return slot;
        const normalized = pathOrKey.split("/").pop().replace(".qml", "");
        for (let i = 0; i < categories.length; i++) {
            const pages = categories[i].pages;
            for (let j = 0; j < pages.length; j++) {
                if (pages[j].key.toLowerCase() === normalized.toLowerCase()) return pages[j].slot;
                const subs = pages[j].subPages || [];
                for (let k = 0; k < subs.length; k++) {
                    if (subs[k].key.toLowerCase() === normalized.toLowerCase()) return subs[k].slot;
                }
            }
        }
        return -1;
    }

    component PlaceholderComp: Item {
        property NexusState nState
        property int pageIdx: -1

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Tokens.padding.extraSmall

            MaterialIcon {
                text: "handyman"
                color: Colours.palette.m3outlineVariant
                fontStyle: Tokens.font.icon.extraLarge
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: qsTr("Page under construction")
                color: Colours.palette.m3outlineVariant
                font: Tokens.font.title.large
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: qsTr("This page is not available in this build. Update the shell to get it.")
                color: Colours.palette.m3outlineVariant
                font: Tokens.font.body.large
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
