pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth

QtObject {
    property ShellScreen screen
    property bool isWindow
    property bool animatingContainer
    property int currentPageIdx: -1
    property var subPageIdxStack: []
    property bool searchOpen
    property string searchQuery

    property string selectedWallpaperCategory
    property BluetoothDevice selectedBtDevice
    property DesktopEntry selectedApp
    property string selectedOutput
    property int editingVpnIndex: -1
    property string selectedNetworkSsid
    property string selectedNetworkUuid
    property string selectedEthernetInterface
    property bool networkDetailsFromSaved

    property string pendingNetworkSsid: ""

    property int pendingSubPageIdx: -1
    property int activeSubPageSlot: -1
    property bool compact: false
    property bool compactSubcategories: false

    signal close
    signal subPageOpened(target: var)
    signal subPageClosed
    signal subPagesCleared
    signal subCategorySelected(target: var)

    function defaultSlotForPage(pageIdx: int): int {
        switch (pageIdx) {
        case 0: return 1; // Appearance: Wallpapers
        case 1: return 4; // Desktop: Desktop Settings
        case 2: return 1; // Panels & Interface: Dashboard
        case 3: return 0; // Network & Connectivity: Wi-Fi & Connection
        case 4: return 0; // Display & Sound: Layout & Scale
        case 5: return 3; // Utilities & Tools: On-screen slider
        case 6: return 0; // Applications & Shortcuts: Default Applications
        case 7: return 0; // System & Services: Session settings
        default: return 0;
        }
    }

    function parentSubCategorySlot(pageIdx: int, slot: int): int {
        if (pageIdx === 0) {
            // Appearance
            if (slot === 2) return 1; // Wallpapers -> WallpaperCategory
            if (slot === 4) return 6; // Library -> Wallhaven
            if (slot === 9) return 3; // Colors -> AdvancedColors
            return slot;
        }
        if (pageIdx === 1) {
            // Desktop & Tiling
            if (slot === 0) return 4; // DesktopPage -> Desktop
            return slot;
        }
        if (pageIdx === 2) {
            // Panels & Interface
            if ([6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21, 22, 23].indexOf(slot) !== -1)
                return 2; // Taskbar
            return slot;
        }
        if (pageIdx === 3) {
            // Network & Connectivity
            if ([1, 2, 3, 4].indexOf(slot) !== -1) return 0; // Ethernet, AddNetwork, Detail, Vpn -> Wi-Fi & Connection
            if (slot === 11) return 10; // BtDeviceInfo -> Bluetooth
            return slot;
        }
        if (pageIdx === 4) {
            // Display & Sound
            if (slot === 1) return 0; // DisplayModesPage -> Layout & Scale
            if (slot === 10) return 6; // Notifications main -> Preferences
            return slot;
        }
        if (pageIdx === 5) {
            // Utilities & Tools
            if (slot === 2) return 1; // Game mode targets -> Game mode
            return slot;
        }
        if (pageIdx === 6) {
            // Applications & Shortcuts
            if (slot === 2) return 1; // AppInfo -> Installed Applications
            return slot;
        }
        if (pageIdx === 7) {
            // System & Services
            if (slot === 7) return 6; // AutostartAppPicker -> Startup Applications
            return slot;
        }
        return slot;
    }

    function selectSubCategory(slot: var): void {
        activeSubPageSlot = slot;
        pendingSubPageIdx = -1;
        subPageIdxStack.length = 0;
        subCategorySelected(slot);
    }

    function openSubPage(target: var): void {
        if (compact)
            compactSubcategories = true;
        subPageIdxStack.push(target);
        subPageOpened(target);
    }

    function goToPage(pageIdx: int): void {
        if (pageIdx !== currentPageIdx) {
            currentPageIdx = pageIdx;
            return;
        }
        pendingSubPageIdx = -1;
        activeSubPageSlot = defaultSlotForPage(currentPageIdx);
        subCategorySelected(activeSubPageSlot);
        if (subPageIdxStack.length === 0)
            return;
        subPageIdxStack.length = 0;
        subPagesCleared();
    }

    function enterCompactPage(): void {
        compactSubcategories = true;
    }

    function exitCompactPage(): void {
        compactSubcategories = false;
    }

    // Navigation that changes page, such as a search result. Landing on the
    // page that is already showing still opens immediately: nothing to wait for.
    function goToSubPage(pageIdx: int, subPageIdx: int): void {
        const subIdx = subPageIdx;
        if (pageIdx === currentPageIdx) {
            pendingSubPageIdx = -1;
            if (compact)
                compactSubcategories = true;
            if (subIdx >= 0) {
                const parentSlot = parentSubCategorySlot(pageIdx, subIdx);
                selectSubCategory(parentSlot);
                if (subIdx !== parentSlot) {
                    openSubPage(subIdx);
                }
            } else {
                goToPage(pageIdx);
            }
            return;
        }
        pendingSubPageIdx = subIdx;
        currentPageIdx = pageIdx;
    }

    function closeSubPage(): void {
        subPageClosed();
        subPageIdxStack.pop();
    }

    function openNetworkDetail(ssid: string, uuid: string, fromSaved: bool): void {
        selectedNetworkSsid = ssid;
        selectedNetworkUuid = uuid;
        networkDetailsFromSaved = fromSaved;
        openSubPage(3);
    }

    Component.onCompleted: {
        if (currentPageIdx < 0) {
            currentPageIdx = 0;
        } else if (activeSubPageSlot < 0) {
            if (pendingSubPageIdx >= 0) {
                const target = pendingSubPageIdx;
                pendingSubPageIdx = -1;
                activeSubPageSlot = parentSubCategorySlot(currentPageIdx, target);
                subPageIdxStack.length = 0;
                if (target !== activeSubPageSlot) {
                    subPageIdxStack.push(target);
                }
            } else {
                activeSubPageSlot = defaultSlotForPage(currentPageIdx);
            }
            subCategorySelected(activeSubPageSlot);
        }
    }

    onCurrentPageIdxChanged: {
        if (currentPageIdx < 0)
            return;
        compactSubcategories = compact;
        subPageIdxStack.length = 0;
        if (pendingSubPageIdx >= 0) {
            const target = pendingSubPageIdx;
            pendingSubPageIdx = -1;
            activeSubPageSlot = parentSubCategorySlot(currentPageIdx, target);
            if (target !== activeSubPageSlot) {
                subPageIdxStack.push(target);
            }
        } else {
            activeSubPageSlot = defaultSlotForPage(currentPageIdx);
        }
        subCategorySelected(activeSubPageSlot);
    }

    onSearchOpenChanged: {
        if (searchOpen && compact && compactSubcategories) {
            exitCompactPage();
        }
    }
}
