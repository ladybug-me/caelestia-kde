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
    property bool sidePane: false

    signal close
    signal subPageOpened(target: var)
    signal subPageClosed
    signal subPagesCleared
    signal subCategorySelected(target: var)

    function defaultSlotForPage(pageIdx: int): int {
        if (!sidePane)
            return 0;

        return PageCompRegistry.defaultSlotForCategory(pageIdx);
    }

    function parentSubCategorySlot(pageIdx: int, slot: int): int {
        return PageCompRegistry.parentSlotFor(pageIdx, slot);
    }

    // Without the side pane the section's list of subcategories is the root of
    // the stack, so a requested sub-page is not already showing anywhere.
    function rootSlotFor(pageIdx: int, target: int): int {
        return sidePane ? parentSubCategorySlot(pageIdx, target) : 0;
    }

    function selectSubCategory(slot: var): void {
        activeSubPageSlot = slot;
        pendingSubPageIdx = -1;
        subPageIdxStack.length = 0;
        subCategorySelected(slot);
    }

    function openSubPage(target: var): void {
        if (sidePane && compact)
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
        if (sidePane)
            compactSubcategories = true;
    }

    function exitCompactPage(): void {
        compactSubcategories = false;
    }

    // Navigation that changes page, such as a search result. Landing on the
    // page that is already showing still opens immediately: nothing to wait for.
    function goToSubPage(pageIdx: int, subPageIdx: int): void {
        if (!sidePane) {
            // The section list is the root of the stack, so a result lands on
            // that list with the sub-page opened on top of it.
            if (pageIdx !== currentPageIdx)
                currentPageIdx = pageIdx;
            else
                goToPage(pageIdx);

            if (subPageIdx > 0)
                openSubPage(subPageIdx);
            return;
        }

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
                activeSubPageSlot = rootSlotFor(currentPageIdx, target);
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
            activeSubPageSlot = rootSlotFor(currentPageIdx, target);
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

    onSidePaneChanged: {
        // The pane can be toggled from inside the window it lays out, so the
        // content has to drop back to whatever the new layout calls its root.
        if (currentPageIdx < 0)
            return;
        compactSubcategories = false;
        subPageIdxStack.length = 0;
        activeSubPageSlot = defaultSlotForPage(currentPageIdx);
        subCategorySelected(activeSubPageSlot);
    }
}
