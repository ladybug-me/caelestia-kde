pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth

QtObject {
    property ShellScreen screen
    property bool isWindow
    property bool animatingContainer
    property int currentPageIdx
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

    // Which bar the components page edits: -1 is the main bar, anything else
    // indexes `bar.panels`.
    property int barComponentsTarget: -1

    signal close
    signal subPageOpened(target: var)
    signal subPageClosed
    signal subPagesCleared

    function openSubPage(target: var): void {
        subPageIdxStack.push(target);
        subPageOpened(target);
    }

    function goToPage(pageIdx: int): void {
        if (pageIdx !== currentPageIdx) {
            currentPageIdx = pageIdx;
            return;
        }
        pendingSubPageIdx = -1;
        if (subPageIdxStack.length === 0)
            return;
        subPageIdxStack.length = 0;
        subPagesCleared();
    }

    // Navigation that changes page, such as a search result. Landing on the
    // page that is already showing still opens immediately: nothing to wait for.
    function goToSubPage(pageIdx: int, subPageIdx: int): void {
        if (pageIdx === currentPageIdx) {
            pendingSubPageIdx = -1;
            if (subPageIdx >= 0)
                openSubPage(subPageIdx);
            else
                goToPage(pageIdx);
            return;
        }
        currentPageIdx = pageIdx;
        pendingSubPageIdx = subPageIdx;
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

    onCurrentPageIdxChanged: {
        subPageIdxStack.length = 0;
        pendingSubPageIdx = -1;
        barComponentsTarget = -1;
    }
}
