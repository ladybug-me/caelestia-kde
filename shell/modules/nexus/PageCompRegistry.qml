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
import qs.modules.nexus.pages.network
import qs.modules.nexus.pages.panels
import qs.modules.nexus.pages.services
import qs.modules.nexus.pages.utilities
import qs.modules.nexus.pages.wallandstyle
import qs.modules.nexus.pages.panels.taskbar

QtObject {
    id: root

    readonly property Component placeholderComp: Component {
        PlaceholderComp {}
    }
    readonly property list<Component> pageComps: [
        Component {
            StackPage {
                Component {
                    WallpaperAndStyle {}
                }
                Component {
                    WallpaperSelect {}
                }
                Component {
                    WallpaperCategory {}
                }
                Component {
                    ColourSelect {}
                }
                Component {
                    WallhavenPage {}
                }
                Component {
                    WallpaperSettingsPage {}
                }
                Component {
                    SlideshowAndOrderPage {}
                }
                Component {
                    VideoWallpapersPage {}
                }
                Component {
                    AppearancePage {}
                }
                Component {
                    LockScreenPage {}
                }
                Component {
                    AdvancedColorsPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    DesktopPage {}
                }
                Component {
                    DesktopAddonsPage {}
                }
                Component {
                    ContextMenuPage {}
                }
                Component {
                    KrohnkitePage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    PanelsPage {}
                }
                Component {
                    DashboardPanel {}
                }
                Component {
                    TaskbarPanel {}
                }
                Component {
                    LauncherPanel {}
                }
                Component {
                    SidebarPanel {}
                }
                Component {
                    UtilitiesPanel {}
                }
                Component {
                    BarComponents {}
                }
                Component {
                    BarWorkspaces {}
                }
                Component {
                    BarGreeter {}
                }
                Component {
                    BarTray {}
                }
                Component {
                    BarStatusIcons {}
                }
                Component {
                    BarClock {}
                }
                Component {
                    BarDock {}
                }
                Component {
                    BarGithub {}
                }
                Component {
                    BarPreviewScales {}
                }
                Component {
                    TaskbarElements {}
                }
                Component {
                    OverviewPanel {}
                }
                Component {
                    BarUpdates {}
                }
                Component {
                    TabSwitcherPanel {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    NetworkPage {}
                }
                Component {
                    EthernetDetailPage {}
                }
                Component {
                    AddNetworkPage {}
                }
                Component {
                    NetworkDetailPage {}
                }
                Component {
                    AddVpnPage {}
                }
                Component {
                    AllNetworksPage {}
                }
                Component {
                    SavedNetworksPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    BluetoothPage {}
                }
                Component {
                    BtDeviceInfo {}
                }
                Component {
                    BluetoothPairing {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    AudioPage {}
                }
                Component {
                    AppVolumes {}
                }
                Component {
                    SoundEffectsPage {}
                }
                Component {
                    NotificationSilencingPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    NotificationsPage {}
                }
                Component {
                    NotificationPreferencesPage {}
                }
                Component {
                    ToastPreferencesPage {}
                }
                Component {
                    ToastEventsPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    UtilitiesPage {}
                }
                Component {
                    GameModePage {}
                }
                Component {
                    GameModeTargetsPage {}
                }
                Component {
                    OsdPage {}
                }
                Component {
                    ClipboardPage {}
                }
                Component {
                    UtilitiesPanelPage {}
                }
                Component {
                    QuickTogglesPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    SessionPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    ShortcutManagerPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    AppsPage {}
                }
                Component {
                    AllApps {}
                }
                Component {
                    AppInfo {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    ServicesPage {}
                }
                Component {
                    ArpcPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    LanguageAndRegion {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    UpdatesPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    PluginsPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    AboutPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    AiSettingsPage {}
                }
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
