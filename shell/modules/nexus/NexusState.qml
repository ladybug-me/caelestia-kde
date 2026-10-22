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
    property int editingVpnIndex: -1
    property string selectedNetworkSsid
    property string selectedNetworkUuid
    property string selectedEthernetInterface
    property bool networkDetailsFromSaved

    property string pendingNetworkSsid: ""

    property int pendingSubPageIdx: -1

    signal close
    signal subPageOpened(target: var)
    signal subPageClosed

    function openSubPage(target: var): void {
        subPageIdxStack.push(target);
        subPageOpened(target);
    }

    // Navigation that changes page, such as a search result. Landing on the
    // page that is already showing still opens immediately: nothing to wait for.
    function goToSubPage(pageIdx: int, subPageIdx: int): void {
        if (pageIdx === currentPageIdx) {
            pendingSubPageIdx = -1;
            if (subPageIdx >= 0)
                openSubPage(subPageIdx);
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
    }
}
