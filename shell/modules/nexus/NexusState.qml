pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth

QtObject {
    property ShellScreen screen
    property bool isWindow
    property bool animatingContainer
    property int currentPageIdx: -1
    property var subPageKeyStack: []
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

    property string pendingSubPageKey: ""
    property string activeSubPageKey: ""
    property bool compact: false
    property bool compactSubcategories: false
    property bool sidePane: false

    signal close
    signal subPageOpened(target: string)
    signal subPageClosed
    signal subPagesCleared
    signal subCategorySelected(target: string)

    function defaultPageForCategory(pageIdx: int): string {
        if (!sidePane)
            return "hub";

        return PageCompRegistry.defaultPageForCategory(pageIdx);
    }

    function parentSubCategory(pageIdx: int, key: string): string {
        return PageCompRegistry.parentPageFor(pageIdx, key);
    }

    function rootPageFor(pageIdx: int, target: string): string {
        return sidePane ? parentSubCategory(pageIdx, target) : "hub";
    }

    function selectSubCategory(key: string): void {
        activeSubPageKey = key;
        pendingSubPageKey = "";
        subPageKeyStack.length = 0;
        subCategorySelected(key);
    }

    function openSubPage(target: string): void {
        if (sidePane && compact)
            compactSubcategories = true;
        subPageKeyStack.push(target);
        subPageOpened(target);
    }

    function goToPage(pageIdx: int): void {
        if (pageIdx !== currentPageIdx) {
            currentPageIdx = pageIdx;
            return;
        }
        pendingSubPageKey = "";
        activeSubPageKey = defaultPageForCategory(currentPageIdx);
        subCategorySelected(activeSubPageKey);
        if (subPageKeyStack.length === 0)
            return;
        subPageKeyStack.length = 0;
        subPagesCleared();
    }

    function enterCompactPage(): void {
        if (sidePane)
            compactSubcategories = true;
    }

    function exitCompactPage(): void {
        compactSubcategories = false;
    }

    function goToSubPage(pageIdx: int, subPageKey: string): void {
        if (!sidePane) {
            if (pageIdx !== currentPageIdx) {
                pendingSubPageKey = subPageKey;
                currentPageIdx = pageIdx;
            } else {
                goToPage(pageIdx);
                if (subPageKey !== "" && subPageKey !== "hub")
                    openSubPage(subPageKey);
            }
            return;
        }

        if (pageIdx === currentPageIdx) {
            pendingSubPageKey = "";
            if (compact)
                compactSubcategories = true;
            if (subPageKey !== "") {
                const parentKey = parentSubCategory(pageIdx, subPageKey);
                selectSubCategory(parentKey);
                if (subPageKey !== parentKey) {
                    openSubPage(subPageKey);
                }
            } else {
                goToPage(pageIdx);
            }
            return;
        }
        pendingSubPageKey = subPageKey;
        currentPageIdx = pageIdx;
    }

    function closeSubPage(): void {
        subPageClosed();
        subPageKeyStack.pop();
    }

    function openNetworkDetail(ssid: string, uuid: string, fromSaved: bool): void {
        selectedNetworkSsid = ssid;
        selectedNetworkUuid = uuid;
        networkDetailsFromSaved = fromSaved;
        openSubPage("networkDetail");
    }

    Component.onCompleted: {
        if (currentPageIdx < 0) {
            currentPageIdx = 0;
        } else if (activeSubPageKey === "") {
            if (pendingSubPageKey !== "") {
                const target = pendingSubPageKey;
                pendingSubPageKey = "";
                activeSubPageKey = rootPageFor(currentPageIdx, target);
                subPageKeyStack.length = 0;
                if (target !== activeSubPageKey) {
                    subPageKeyStack.push(target);
                }
            } else {
                activeSubPageKey = defaultPageForCategory(currentPageIdx);
            }
            subCategorySelected(activeSubPageKey);
        }
    }

    onCurrentPageIdxChanged: {
        if (currentPageIdx < 0)
            return;
        compactSubcategories = compact;
        subPageKeyStack.length = 0;
        if (pendingSubPageKey !== "") {
            const target = pendingSubPageKey;
            pendingSubPageKey = "";
            activeSubPageKey = rootPageFor(currentPageIdx, target);
            if (target !== activeSubPageKey) {
                subPageKeyStack.push(target);
            }
        } else {
            activeSubPageKey = defaultPageForCategory(currentPageIdx);
        }
        subCategorySelected(activeSubPageKey);
    }

    onSearchOpenChanged: {
        if (searchOpen && compact && compactSubcategories) {
            exitCompactPage();
        }
    }

    onSidePaneChanged: {
        if (currentPageIdx < 0)
            return;
        compactSubcategories = false;
        subPageKeyStack.length = 0;
        activeSubPageKey = defaultPageForCategory(currentPageIdx);
        subCategorySelected(activeSubPageKey);
    }
}
