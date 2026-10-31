pragma Singleton

import QtQuick
import QtQuick.Layouts
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

    readonly property Component placeholderComp: Component {
        PlaceholderComp {}
    }
    readonly property list<Component> pageComps: [
        // Page 0: Appearance
        Component {
            StackPage {
                SubPage { slot: 0; key: "wallpaperAndStyle"; Component { WallpaperAndStyle {} } }
                SubPage { slot: 1; key: "wallpaperSelect"; Component { WallpaperSelect {} } }
                SubPage { slot: 2; key: "wallpaperCategory"; Component { WallpaperCategory {} } }
                SubPage { slot: 3; key: "colourSelect"; Component { ColourSelect {} } }
                SubPage { slot: 4; key: "wallhaven"; Component { WallhavenPage {} } }
                SubPage { slot: 5; key: "wallpaperSettings"; Component { WallpaperSettingsPage {} } }
                SubPage { slot: 6; key: "libraryAndCommunity"; Component { LibraryAndCommunityPage {} } }
                SubPage { slot: 7; key: "appearance"; Component { AppearancePage {} } }
                SubPage { slot: 8; key: "lockScreen"; Component { LockScreenPage {} } }
                SubPage { slot: 9; key: "advancedColors"; Component { AdvancedColorsPage {} } }
            }
        },
        // Page 1: Desktop & Tiling
        Component {
            StackPage {
                SubPage { slot: 0; key: "desktop"; Component { DesktopPage {} } }
                SubPage { slot: 1; key: "desktopAddons"; Component { DesktopAddonsPage {} } }
                SubPage { slot: 2; key: "contextMenu"; Component { ContextMenuPage {} } }
                SubPage { slot: 3; key: "krohnkite"; Component { KrohnkitePage {} } }
                SubPage { slot: 4; key: "desktopSettings"; Component { DesktopSettingsPage {} } }
            }
        },
        // Page 2: Panels & Interface
        Component {
            StackPage {
                SubPage { slot: 0; key: "panels"; Component { PanelsPage {} } }
                SubPage { slot: 1; key: "dashboard"; Component { DashboardPanel {} } }
                SubPage { slot: 2; key: "taskbar"; Component { TaskbarPanel {} } }
                SubPage { slot: 3; key: "launcher"; Component { LauncherPanel {} } }
                SubPage { slot: 4; key: "sidebar"; Component { SidebarPanel {} } }
                SubPage { slot: 5; key: "utilitiesPanel"; Component { UtilitiesPanel {} } }
                SubPage { slot: 6; key: "barComponents"; Component { BarComponents {} } }
                SubPage { slot: 7; key: "barWorkspaces"; Component { BarWorkspaces {} } }
                SubPage { slot: 8; key: "barGreeter"; Component { BarGreeter {} } }
                SubPage { slot: 9; key: "barTray"; Component { BarTray {} } }
                SubPage { slot: 10; key: "barStatusIcons"; Component { BarStatusIcons {} } }
                SubPage { slot: 11; key: "barClock"; Component { BarClock {} } }
                SubPage { slot: 12; key: "barDock"; Component { BarDock {} } }
                SubPage { slot: 13; key: "barGithub"; Component { BarGithub {} } }
                SubPage { slot: 14; key: "barPreviewScales"; Component { BarPreviewScales {} } }
                SubPage { slot: 15; key: "taskbarElements"; Component { TaskbarElements {} } }
                SubPage { slot: 16; key: "overview"; Component { OverviewPanel {} } }
                SubPage { slot: 17; key: "barUpdates"; Component { BarUpdates {} } }
                SubPage { slot: 18; key: "tabSwitcher"; Component { TabSwitcherPanel {} } }
                SubPage { slot: 19; key: "barMedia"; Component { BarMedia {} } }
                SubPage { slot: 20; key: "barWeather"; Component { BarWeather {} } }
                SubPage { slot: 21; key: "barPerformance"; Component { BarPerformance {} } }
                SubPage { slot: 22; key: "barScreenCapture"; Component { BarScreenCapture {} } }
                SubPage { slot: 23; key: "barKeepAwake"; Component { BarKeepAwake {} } }
            }
        },
        // Page 3: Network & Connectivity
        Component {
            StackPage {
                SubPage { slot: 0; key: "network"; Component { NetworkPage {} } }
                SubPage { slot: 1; key: "ethernetDetail"; Component { EthernetDetailPage {} } }
                SubPage { slot: 2; key: "addNetwork"; Component { AddNetworkPage {} } }
                SubPage { slot: 3; key: "networkDetail"; Component { NetworkDetailPage {} } }
                SubPage { slot: 4; key: "addVpn"; Component { AddVpnPage {} } }
                SubPage { slot: 5; key: "allNetworks"; Component { AllNetworksPage {} } }
                SubPage { slot: 6; key: "savedNetworks"; Component { SavedNetworksPage {} } }
                SubPage { slot: 7; key: "hotspot"; Component { HotspotPage {} } }
                SubPage { slot: 8; key: "proxy"; Component { ProxyPage {} } }
                SubPage { slot: 10; key: "bluetooth"; Component { BluetoothPage {} } }
                SubPage { slot: 11; key: "btDeviceInfo"; Component { BtDeviceInfo {} } }
                SubPage { slot: 12; key: "bluetoothPairing"; Component { BluetoothPairing {} } }
            }
        },
        // Page 4: Display & Sound
        Component {
            StackPage {
                SubPage { slot: 0; key: "displays"; Component { DisplayPage {} } }
                SubPage { slot: 1; key: "displayModes"; Component { DisplayModesPage {} } }
                SubPage { slot: 2; key: "audio"; Component { AudioPage {} } }
                SubPage { slot: 3; key: "appVolumes"; Component { AppVolumes {} } }
                SubPage { slot: 4; key: "soundEffects"; Component { SoundEffectsPage {} } }
                SubPage { slot: 5; key: "notificationSilencing"; Component { NotificationSilencingPage {} } }
                SubPage { slot: 6; key: "notificationPreferences"; Component { NotificationPreferencesPage {} } }
                SubPage { slot: 7; key: "toastPreferences"; Component { ToastPreferencesPage {} } }
                SubPage { slot: 8; key: "toastEvents"; Component { ToastEventsPage {} } }
                SubPage { slot: 9; key: "focus"; Component { FocusPage {} } }
                SubPage { slot: 10; key: "notifications"; Component { NotificationsPage {} } }
            }
        },
        // Page 5: Utilities & Tools
        Component {
            StackPage {
                SubPage { slot: 0; key: "utilities"; Component { UtilitiesPage {} } }
                SubPage { slot: 1; key: "gameMode"; Component { GameModePage {} } }
                SubPage { slot: 2; key: "gameModeTargets"; Component { GameModeTargetsPage {} } }
                SubPage { slot: 3; key: "osd"; Component { OsdPage {} } }
                SubPage { slot: 4; key: "utilitiesPanelPage"; Component { UtilitiesPanelPage {} } }
                SubPage { slot: 5; key: "quickToggles"; Component { QuickTogglesPage {} } }
                SubPage { slot: 6; key: "quickShare"; Component { QuickSharePage {} } }
                SubPage { slot: 7; key: "ai"; Component { AiSettingsPage {} } }
            }
        },
        // Page 6: Applications & Shortcuts
        Component {
            StackPage {
                SubPage { slot: 0; key: "apps"; Component { AppsPage {} } }
                SubPage { slot: 1; key: "allApps"; Component { AllApps {} } }
                SubPage { slot: 2; key: "appInfo"; Component { AppInfo {} } }
                SubPage { slot: 3; key: "shortcutManager"; Component { ShortcutManagerPage {} } }
            }
        },
        // Page 7: System & Services
        Component {
            StackPage {
                SubPage { slot: 0; key: "session"; Component { SessionPage {} } }
                SubPage { slot: 1; key: "services"; Component { ServicesPage {} } }
                SubPage { slot: 2; key: "arpc"; Component { ArpcPage {} } }
                SubPage { slot: 3; key: "calendar"; Component { CalendarPage {} } }
                SubPage { slot: 4; key: "language"; Component { LanguageAndRegion {} } }
                SubPage { slot: 5; key: "accessibility"; Component { AccessibilityPage {} } }
                SubPage { slot: 6; key: "startup"; Component { AutostartPage {} } }
                SubPage { slot: 7; key: "startupAppPicker"; Component { AutostartAppPicker {} } }
                SubPage { slot: 8; key: "storage"; Component { StoragePage {} } }
                SubPage { slot: 9; key: "plugins"; Component { PluginsPage {} } }
                SubPage { slot: 10; key: "updates"; Component { UpdatesPage {} } }
                SubPage { slot: 11; key: "about"; Component { AboutPage {} } }
            }
        }
    ]

    component PlaceholderComp: Item {
        property NexusState nState

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
                text: qsTr("This page will be available in a future update.")
                color: Colours.palette.m3outlineVariant
                font: Tokens.font.body.large
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
