pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

ColumnLayout {
    id: root

    required property NexusState nState
    readonly property var currentPage: PageDictionary.pages[root.nState.currentPageIdx]
    property int selectedIndex: 0
    property bool selectionActive: false
    property Item selectedCard: null

    function currentCards(): var {
        const col = stack.children[root.nState.currentPageIdx];
        if (!col || !col.children)
            return [];
        const cards = [];
        for (let i = 0; i < col.children.length; i++) {
            const child = col.children[i];
            if (child && child.slot !== undefined)
                cards.push(child);
        }
        return cards;
    }

    function syncSelection(): void {
        if (!root.selectionActive) {
            root.selectedCard = null;
            return;
        }
        const cards = currentCards();
        if (cards.length === 0) {
            root.selectedCard = null;
            return;
        }
        if (root.selectedIndex < 0)
            root.selectedIndex = 0;
        else if (root.selectedIndex >= cards.length)
            root.selectedIndex = cards.length - 1;

        root.selectedCard = cards[root.selectedIndex];
        ensureVisible(root.selectedCard);
    }

    function moveUp(): void {
        const cards = currentCards();
        if (cards.length === 0)
            return;
        root.selectionActive = true;
        root.selectedIndex = root.selectedIndex > 0 ? root.selectedIndex - 1 : cards.length - 1;
        syncSelection();
    }

    function moveDown(): void {
        const cards = currentCards();
        if (cards.length === 0)
            return;
        root.selectionActive = true;
        root.selectedIndex = (root.selectedIndex >= 0 && root.selectedIndex < cards.length - 1) ? root.selectedIndex + 1 : 0;
        syncSelection();
    }

    function selectCurrentOrFirst(): void {
        const cards = currentCards();
        if (cards.length === 0)
            return;
        root.selectionActive = true;
        let idx = -1;
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].slot === root.nState.activeSubPageSlot) {
                idx = i;
                break;
            }
        }
        root.selectedIndex = idx >= 0 ? idx : 0;
        syncSelection();
    }

    function activateSelected(): void {
        if (!root.selectionActive || !root.selectedCard)
            return;
        const card = root.selectedCard;
        if (card.cardEnabled) {
            root.nState.selectSubCategory(card.slot);
        }
        root.clearSelection();
    }

    function clearSelection(): void {
        root.selectionActive = false;
        root.selectedCard = null;
    }

    function ensureVisible(item: Item): void {
        if (!item)
            return;
        const pt = flickable.contentItem.mapFromItem(item, 0, 0);
        const top = pt.y;
        const bottom = pt.y + item.height;
        if (top < flickable.contentY) {
            flickable.contentY = top;
        } else if (bottom > flickable.contentY + flickable.height) {
            flickable.contentY = bottom - flickable.height;
        }
    }

    function ensureActiveCardVisible(): void {
        const cards = currentCards();
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].slot === root.nState.activeSubPageSlot) {
                ensureVisible(cards[i]);
                break;
            }
        }
    }

    spacing: Tokens.spacing.medium

    Connections {
        function onCurrentPageIdxChanged(): void {
            root.clearSelection();
            Qt.callLater(root.ensureActiveCardVisible);
        }

        function onActiveSubPageSlotChanged(): void {
            Qt.callLater(root.ensureActiveCardVisible);
        }

        target: root.nState
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 46

        StyledRect {
            visible: root.nState.compact

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.extraSmall
            width: 36
            height: 36
            radius: Tokens.rounding.full
            color: "transparent"

            StateLayer {
                radius: parent.radius

                onClicked: root.nState.exitCompactPage()
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "arrow_back"
                fontStyle: Tokens.font.icon.medium
            }
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: root.nState.compact ? 46 : Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            text: root.currentPage ? root.currentPage.label : ""
            font: Tokens.font.title.builders.large.weight(Font.Medium).build()
            color: Colours.palette.m3onSurface
            elide: Text.ElideRight
        }
    }

    VerticalFadeFlickable {
        id: flickable

        Layout.fillWidth: true
        Layout.fillHeight: true

        topMargin: 0
        bottomMargin: Tokens.padding.large
        contentHeight: stack.children[root.nState.currentPageIdx]?.implicitHeight ?? stack.implicitHeight

        StyledRect {
            z: 2

            visible: flickable.contentHeight > flickable.height + 1

            width: 3
            height: Math.max(24, flickable.height * flickable.visibleArea.heightRatio)
            x: flickable.width - Tokens.padding.small
            y: flickable.contentY + flickable.visibleArea.yPosition * flickable.height
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
            opacity: 0.6
        }

        StackLayout {
            id: stack

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.medium
            currentIndex: root.nState.currentPageIdx

            // Page 0: Appearance
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "wallpaper"
                    label: qsTr("Wallpapers")
                    status: qsTr("Browse and select wallpapers")
                    slot: 1
                }
                SubcategoryCard {
                    icon: "cloud_download"
                    label: qsTr("Library & Components")
                    status: qsTr("Wallhaven, online wallpapers, tags and filters")
                    slot: 6
                }
                SubcategoryCard {
                    icon: "settings_suggest"
                    label: qsTr("Wallpaper Settings")
                    status: Wallpapers.hasSkwd ? qsTr("Configure wallpaper engine, mixer, and effects") : qsTr("Configure scaling, recoloring, video playback, and slideshows")
                    slot: 5
                }
                SubcategoryCard {
                    icon: "lock"
                    label: qsTr("Lock screen")
                    status: qsTr("Wallpaper sync and lock screen settings")
                    slot: 8
                }
                SubcategoryCard {
                    icon: "palette"
                    label: qsTr("Colors")
                    status: qsTr("Caelestia owns color management and not skwd-wall.")
                    slot: 3
                }
                SubcategoryCard {
                    icon: "style"
                    label: qsTr("Theme & Effects")
                    status: qsTr("Islands, Pitch Black, Transparency")
                    slot: 7
                }
            }

            // Page 1: Desktop & Tiling
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "desktop_windows"
                    label: qsTr("Desktop")
                    status: Config.background.disableQuickshellDesktop ? qsTr("Disabled (Plasma)") : (Config.background.desktopIconsEnabled ? qsTr("Icons enabled") : qsTr("Icons disabled"))
                    slot: 4
                }
                SubcategoryCard {
                    icon: "extension"
                    label: qsTr("Desktop Addons")
                    status: qsTr("Visualiser, auto-hide, styling")
                    cardEnabled: !Config.background.disableQuickshellDesktop
                    slot: 1
                }
                SubcategoryCard {
                    icon: "menu_open"
                    label: qsTr("Right click menu")
                    status: qsTr("Configure desktop right click menu")
                    cardEnabled: !Config.background.disableQuickshellDesktop
                    slot: 2
                }
                SubcategoryCard {
                    icon: "view_quilt"
                    label: qsTr("Windows Tiling")
                    status: Config.general.krohnkiteEnabled ? qsTr("Enabled (Krohnkite)") : qsTr("Disabled")
                    slot: 3
                }
            }

            // Page 2: Panels & Interface
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "dashboard"
                    label: qsTr("Dashboard")
                    status: Config.dashboard.enabled ? qsTr("Enabled") : qsTr("Disabled")
                    slot: 1
                }
                SubcategoryCard {
                    icon: "dock_to_bottom"
                    label: qsTr("Taskbar")
                    status: Config.bar.persistent ? qsTr("Always visible") : Config.bar.showOnHover ? qsTr("Reveal on hover") : qsTr("Reveal on drag")
                    slot: 2
                }
                SubcategoryCard {
                    icon: "apps"
                    label: qsTr("Launcher")
                    status: Config.launcher.enabled ? qsTr("Enabled") : qsTr("Disabled")
                    slot: 3
                }
                SubcategoryCard {
                    icon: "dock_to_right"
                    label: qsTr("Sidebar")
                    status: Config.sidebar.enabled ? qsTr("Enabled") : qsTr("Disabled")
                    slot: 4
                }
                SubcategoryCard {
                    icon: "settings_input_component"
                    label: qsTr("Quick toggle")
                    status: Config.utilities.enabled ? qsTr("Enabled") : qsTr("Disabled")
                    slot: 5
                }
                SubcategoryCard {
                    icon: "view_carousel"
                    label: qsTr("Overview")
                    status: Config.overview.enabled ? qsTr("Enabled") : qsTr("Disabled")
                    slot: 16
                }
                SubcategoryCard {
                    icon: "view_array"
                    label: qsTr("Window Switcher")
                    status: !Config.tabSwitch.enabled ? qsTr("Disabled") : (Config.tabSwitch.currentDesktopOnly ? qsTr("Current desktop only") : qsTr("All desktops"))
                    slot: 18
                }
            }

            // Page 3: Network & Connectivity
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "wifi"
                    label: qsTr("Wi-Fi & Connection")
                    status: Nmcli.activeWifiSsid ? Nmcli.activeWifiSsid : (Nmcli.wifiEnabled ? qsTr("Disconnected") : qsTr("Disabled"))
                    slot: 0
                }
                SubcategoryCard {
                    icon: "network_check"
                    label: qsTr("All Networks")
                    status: qsTr("%1 available").arg(Nmcli.networks.length)
                    slot: 5
                }
                SubcategoryCard {
                    icon: "history"
                    label: qsTr("Saved Networks")
                    status: qsTr("Manage known connections")
                    slot: 6
                }
                SubcategoryCard {
                    icon: "wifi_tethering"
                    label: qsTr("Hotspot")
                    status: Nmcli.hotspot.active ? qsTr("Active") : qsTr("Inactive")
                    slot: 7
                }
                SubcategoryCard {
                    icon: "vpn_key"
                    label: qsTr("Proxy")
                    status: qsTr("Network proxy settings")
                    slot: 8
                }
                SubcategoryCard {
                    icon: "bluetooth"
                    label: qsTr("Bluetooth")
                    status: (Bluetooth.defaultAdapter?.enabled ?? false) ? qsTr("Enabled") : qsTr("Disabled")
                    slot: 10
                }
                SubcategoryCard {
                    icon: "add_circle"
                    label: qsTr("Pair New Device")
                    status: qsTr("Search for nearby Bluetooth devices")
                    slot: 12
                }
            }

            // Page 4: Display & Sound
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "display_settings"
                    label: qsTr("Layout & Scale")
                    status: qsTr("%1 display(s) connected").arg(Displays.outputs.length)
                    slot: 0
                }
                SubcategoryCard {
                    icon: "volume_up"
                    label: qsTr("Output & Input")
                    status: Audio.muted ? qsTr("Muted") : qsTr("%1%").arg(Math.round(Audio.volume * 100))
                    slot: 2
                }
                SubcategoryCard {
                    icon: "tune"
                    label: qsTr("App Volumes")
                    status: Audio.appStreams.length === 0 ? qsTr("No apps playing audio") : Audio.appStreams.length === 1 ? qsTr("1 app playing audio") : qsTr("%1 apps playing audio").arg(Audio.appStreams.length)
                    slot: 3
                }
                SubcategoryCard {
                    icon: "music_note"
                    label: qsTr("Sound Effects")
                    status: qsTr("Feedback sounds and volume")
                    slot: 4
                }
                SubcategoryCard {
                    icon: "notifications_off"
                    label: qsTr("Notification Silence")
                    status: qsTr("Applications that send without sound")
                    slot: 5
                }
                SubcategoryCard {
                    icon: "notifications"
                    label: qsTr("Preferences")
                    status: qsTr("Position, timeout, and display behavior")
                    slot: 6
                }
                SubcategoryCard {
                    icon: "campaign"
                    label: qsTr("Toasts")
                    status: qsTr("Fullscreen behavior, appearance, and sound")
                    slot: 7
                }
                SubcategoryCard {
                    icon: "tune"
                    label: qsTr("Toasts Events")
                    status: qsTr("Choose which system changes show a toast")
                    slot: 8
                }
                SubcategoryCard {
                    icon: "do_not_disturb_on"
                    label: qsTr("Focus Sessions")
                    status: Focus.active ? qsTr("Running until %1").arg(Focus.activeEnd()) : qsTr("Do Not Disturb on a schedule")
                    slot: 9
                }
            }

            // Page 5: Utilities & Tools
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "volume_up"
                    label: qsTr("On-screen slider")
                    status: qsTr("Volume, microphone, brightness, and edge triggers")
                    slot: 3
                }
                SubcategoryCard {
                    icon: "widgets"
                    label: qsTr("Utilities panel")
                    status: qsTr("Choose the cards shown in the panel")
                    slot: 4
                }
                SubcategoryCard {
                    icon: "toggle_on"
                    label: qsTr("Quick toggles")
                    status: qsTr("Choose the controls shown in Quick Toggles")
                    slot: 5
                }
                SubcategoryCard {
                    icon: "sports_esports"
                    label: qsTr("Game Mode")
                    status: qsTr("Auto-enable rules and performance overrides")
                    slot: 1
                }
                SubcategoryCard {
                    icon: "near_me"
                    label: qsTr("Quick share")
                    status: qsTr("Send files to nearby devices")
                    slot: 6
                }
                SubcategoryCard {
                    icon: "smart_toy"
                    label: qsTr("AI Configuration")
                    status: qsTr("Models, providers, and parameters")
                    slot: 7
                }
            }

            // Page 6: Applications & Shortcuts
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "apps"
                    label: qsTr("Default Applications")
                    status: qsTr("Configure system default openers")
                    slot: 0
                }
                SubcategoryCard {
                    icon: "list_alt"
                    label: qsTr("Installed Applications")
                    status: qsTr("Browse and manage desktop apps")
                    slot: 1
                }
                SubcategoryCard {
                    icon: "keyboard"
                    label: qsTr("Keyboard Shortcuts")
                    status: qsTr("View and configure shell keybindings")
                    slot: 3
                }
            }

            // Page 7: System & Services
            ColumnLayout {
                spacing: Tokens.spacing.small

                SubcategoryCard {
                    icon: "power_settings_new"
                    label: qsTr("Session settings")
                    status: qsTr("Power, lock, and logout options")
                    slot: 0
                }
                SubcategoryCard {
                    icon: "build"
                    label: qsTr("System Services")
                    status: qsTr("Lyrics, GPU, and system integration")
                    slot: 1
                }
                SubcategoryCard {
                    icon: "sync_alt"
                    label: qsTr("Remote IPC")
                    status: qsTr("Local and network remote procedure calls")
                    slot: 2
                }
                SubcategoryCard {
                    icon: "calendar_today"
                    label: qsTr("Calendar Integration")
                    status: qsTr("Sync calendar events and accounts")
                    slot: 3
                }
                SubcategoryCard {
                    icon: "language"
                    label: qsTr("Language & Format")
                    status: qsTr("System locale, spellcheck, and formats")
                    slot: 4
                }
                SubcategoryCard {
                    icon: "accessibility_new"
                    label: qsTr("Accessibility")
                    status: qsTr("Vision, hearing, and interaction aids")
                    slot: 5
                }
                SubcategoryCard {
                    icon: "rocket_launch"
                    label: qsTr("Startup Applications")
                    status: qsTr("Manage apps launched upon login")
                    slot: 6
                }
                SubcategoryCard {
                    icon: "storage"
                    label: qsTr("Disk & Storage")
                    status: qsTr("Mount points, free space, and drives")
                    slot: 8
                }
                SubcategoryCard {
                    icon: "extension"
                    label: qsTr("Caelestia Plugins")
                    status: qsTr("Manage installed extensions and add-ons")
                    slot: 9
                }
                SubcategoryCard {
                    icon: "system_update"
                    label: qsTr("Updates")
                    status: qsTr("Check for package and system updates")
                    slot: 10
                }
                SubcategoryCard {
                    icon: "info"
                    label: qsTr("About System")
                    status: qsTr("Hardware, OS version, and shell info")
                    slot: 11
                }
            }
        }
    }

    component SubcategoryCard: StyledRect {
        id: card

        required property string icon
        required property string label
        property string status: ""
        required property int slot
        property bool cardEnabled: true

        readonly property bool isSelected: root.nState.activeSubPageSlot === slot
        readonly property bool isNavSelected: root.selectedCard === card

        Layout.fillWidth: true
        implicitHeight: 66

        radius: Tokens.rounding.large
        color: isSelected
            ? Colours.palette.m3secondaryContainer
            : isNavSelected
                ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 4)
                : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
        border.color: isNavSelected
            ? Colours.palette.m3primary
            : (isSelected ? Colours.palette.m3outlineVariant : "transparent")
        border.width: isNavSelected ? 2 : (isSelected ? 1 : 0)
        opacity: cardEnabled ? 1.0 : 0.5

        Behavior on color {
            CAnim {}
        }

        Behavior on border.color {
            CAnim {}
        }

        StateLayer {
            id: stateLayer

            anchors.fill: parent
            radius: parent.radius
            enabled: card.cardEnabled
            manualHoverOverride: card.isNavSelected

            onClicked: {
                root.clearSelection();
                root.nState.selectSubCategory(card.slot);
            }
        }

        StyledRect {
            visible: card.isSelected

            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.extraSmall
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 22
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
        }

        RowLayout {
            id: cardLayout

            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            anchors.topMargin: Tokens.padding.small
            anchors.bottomMargin: Tokens.padding.small
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 34
                implicitHeight: 34

                radius: Tokens.rounding.full
                color: card.isSelected ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1

                    text: card.icon
                    color: card.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                    grade: 25
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: card.label
                    font: Tokens.font.body.builders.medium.size(Math.round(Tokens.font.body.medium.pointSize * 0.92)).build()
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: card.status
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.builders.small.size(9).build()
                    elide: Text.ElideRight
                }
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "chevron_right"
                color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
