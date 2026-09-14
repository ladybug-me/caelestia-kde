pragma Singleton

import QtQuick
import Quickshell
import qs.services
import Caelestia.Config

Singleton {
    id: root

    property var items: []
    property int selectedIndex: 0

    function triggerCycleNext(): void {
        if (items.length === 0) return;
        selectedIndex = (selectedIndex + 1) % items.length;
    }

    function triggerCyclePrev(): void {
        if (items.length === 0) return;
        selectedIndex = (selectedIndex - 1 + items.length) % items.length;
    }

    function focusSelectedWindow(): void {
        if (selectedIndex >= 0 && selectedIndex < items.length) {
            focusWindow(items[selectedIndex].address);
        }
    }

    function reload(): void {
        updateItems();
    }

    function refreshHighlight(): void {
        if (GlobalConfig.tabSwitch?.previewOnDesktop && selectedIndex >= 0 && selectedIndex < items.length) {
            Kwin.highlightWindow(items[selectedIndex].address);
        }
    }

    function getDesktopName(client: var): string {
        if (!client || !client.workspace) return "";
        const wsId = client.workspace.id;
        const wsUuid = client.workspace.uuid;
        if (Kwin.workspaces) {
            for (let i = 0; i < Kwin.workspaces.length; ++i) {
                const ws = Kwin.workspaces[i];
                if ((wsUuid && ws.id === wsUuid) || (wsId !== undefined && wsId !== -1 && ws.index === wsId)) {
                    return ws.name || ("Desktop " + ws.index);
                }
            }
        }
        if (typeof wsId === "number" && wsId > 0) return "Desktop " + wsId;
        return wsUuid ? String(wsUuid) : "";
    }

    function updateItems(): void {
        const activeAddress = Kwin.activeWindow ? Kwin.activeWindow.address : "";
        const winList = (Kwin.windowList || []).filter(w => !(w.class && w.class.toLowerCase().includes("xwaylandvideobridge")));
        
        let currentItems = root.items.slice();
        
        // 1. Remove closed windows
        currentItems = currentItems.filter(item => {
            for (let i = 0; i < winList.length; i++) {
                if (winList[i].address === item.address) return true;
            }
            return false;
        });
        
        // Helper to format
        const formatClient = (client) => {
            return {
                address: client.address,
                title: client.title || "",
                class: client.class || "",
                iconName: client.iconName || client.class || "",
                workspace: client.workspace?.id ?? "",
                workspaceUuid: client.workspace?.uuid ?? "",
                desktopName: getDesktopName(client),
                minimized: !!client.minimized,
                closeable: true,
                pid: client.pid || 0,
                monitor: client.output || "",
                wayland: true,
                size: [client.width || 0, client.height || 0],
                at: [client.x || 0, client.y || 0]
            };
        };

        // 2. Add new windows & update existing
        for (let i = 0; i < winList.length; ++i) {
            const client = winList[i];
            let found = false;
            for (let j = 0; j < currentItems.length; ++j) {
                if (currentItems[j].address === client.address) {
                    currentItems[j] = formatClient(client); // Update properties
                    found = true;
                    break;
                }
            }
            if (!found) {
                currentItems.push(formatClient(client));
            }
        }
        
        // 3. Move active window to index 0 (MRU ordering)
        if (activeAddress) {
            for (let i = 0; i < currentItems.length; i++) {
                if (currentItems[i].address === activeAddress) {
                    const activeWin = currentItems.splice(i, 1)[0];
                    currentItems.unshift(activeWin);
                    break;
                }
            }
        }

        // 4. Filter by current desktop if GlobalConfig.tabSwitch.currentDesktopOnly is active (KDE DesktopMode = 0)
        if (GlobalConfig.tabSwitch?.currentDesktopOnly && true) {
            const currentWsId = Kwin.activeWsId;
            const currentWsUuid = (Kwin.workspaces && currentWsId > 0 && currentWsId <= Kwin.workspaces.length) 
                ? Kwin.workspaces[currentWsId - 1].id 
                : "";
            currentItems = currentItems.filter(item => {
                if (!item.workspace && !item.workspaceUuid) return true;
                if (item.workspace === -1 || item.workspace === 0) return true;
                if (item.workspace === currentWsId) return true;
                if (currentWsUuid && item.workspaceUuid === currentWsUuid) return true;
                return false;
            });
        }

        // 5. Filter by current screen if GlobalConfig.tabSwitch.allScreens is false (KDE MultiScreenMode = 1)
        if (GlobalConfig.tabSwitch && !GlobalConfig.tabSwitch.allScreens) {
            const activeOut = Kwin.activeOutputName || Kwin.cursorOutputName();
            if (activeOut) {
                currentItems = currentItems.filter(item => !item.monitor || item.monitor === activeOut);
            }
        }

        // 6. Filter minimized windows if GlobalConfig.tabSwitch.showMinimized is false (KDE MinMode = 1)
        if (GlobalConfig.tabSwitch && !GlobalConfig.tabSwitch.showMinimized) {
            currentItems = currentItems.filter(item => !item.minimized);
        }
        
        items = currentItems;

        // A window closing (e.g. from the switcher's own close button) can leave
        // selectedIndex pointing past the end of the shrunk array — clamp it back
        // onto the last item rather than leaving ListView.currentIndex invalid.
        if (root.selectedIndex >= currentItems.length)
            root.selectedIndex = Math.max(0, currentItems.length - 1);
    }

    function query(search: string): var {
        if (!search)
            return items;
        const lower = search.toLowerCase();
        return items.filter(w => (w.title && w.title.toLowerCase().includes(lower)) || (w.class && w.class.toLowerCase().includes(lower)) || (w.desktopName && w.desktopName.toLowerCase().includes(lower)));
    }

    function focusWindow(address: string): void {
        Kwin.clearHighlight();
        Kwin.focusWindow(address);
    }

    function closeWindow(address: string): void {
        Kwin.closeWindow(address);
    }

    onSelectedIndexChanged: {
        refreshHighlight();
    }

    Component.onCompleted: {
        updateItems();
    }

    Connections {
        function onWindowListChanged(): void {
            root.updateItems();
        }

        function onActiveWindowChanged(): void {
            root.updateItems();
        }

        target: Kwin
    }

    Connections {
        function onCurrentDesktopOnlyChanged(): void {
            root.updateItems();
        }

        function onAllScreensChanged(): void {
            root.updateItems();
        }

        function onShowMinimizedChanged(): void {
            root.updateItems();
        }

        function onPreviewOnDesktopChanged(): void {
            if (!GlobalConfig.tabSwitch.previewOnDesktop) {
                Kwin.clearHighlight();
            } else {
                root.refreshHighlight();
            }
        }

        target: GlobalConfig.tabSwitch
    }
}

