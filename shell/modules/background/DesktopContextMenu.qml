pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.controls as Controls
import qs.services
import qs.utils
import qs.modules.nexus

Controls.Menu {
    id: root

    property real _menuW: root.backgroundItem && root.backgroundItem.implicitWidth > 0 ? root.backgroundItem.implicitWidth : 250
    property real _menuH: root.backgroundItem && root.backgroundItem.implicitHeight > 0 ? root.backgroundItem.implicitHeight : 350
    property bool _flipX: attachTo && attachTo.parent && (attachTo.x + _menuW > attachTo.parent.width)
    property bool _flipY: attachTo && attachTo.parent && (attachTo.y + _menuH > attachTo.parent.height)
    property string screenName: ""
    property var itemPool: ({})
    property var entryByKey: ({})
    property real perfMenuOpenStartedAt: 0

    function executeEntryByKey(key) {
        let entry = root.entryByKey[key];
        if (!entry) return;

        root.expanded = false;

        execTimer.pendingAction = () => {
            if (entry.action) {
                if (entry.action === "Wallpapers.next()") Wallpapers.next();
                else if (entry.action === "Quickshell.reload()") Quickshell.reload();
                else if (entry.action === "WindowFactory.create()") WindowFactory.create();
                else if (entry.action === "ToggleDesktopIcons") {
                    let newState = !GlobalConfig.background.desktopIconsEnabled;
                    GlobalConfig.background.desktopIconsEnabled = newState;
                    for (let i = 0; i < Quickshell.screens.length; i++) {
                        let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                        if (sConf) sConf.background.resetOption("desktopIconsEnabled");
                    }
                    GlobalConfig.save();
                } else if (entry.action === "OpenRightClickMenu") {
                    WindowFactory.create(null, {
                        initialPageIdx: PageRegistry.indexForKey("desktop"), // Desktop
                        initialSubPageIdx: 2 // Right Click Menu is index 2
                    });
                } else if (entry.action === "OpenTerminal") {
                    Launch.exec([...GlobalConfig.general.apps.terminal]);
                }
            } else if (entry.command) {
                if (entry.command === "terminal") {
                    Launch.exec([...GlobalConfig.general.apps.terminal]);
                } else {
                    Launch.exec(typeof entry.command === "string" ? entry.command.split(" ") : entry.command);
                }
            }
        };
        execTimer.restart();
    }

    function applyEntries(entries, sourceName) {
        const buildStartedAt = Date.now();
        const normalized = (!entries || entries.length === 0)
            ? ContextMenuStore.cloneEntries(ContextMenuStore.defaultEntries())
            : ContextMenuStore.cloneEntries(entries);
        const newArr = [];
        const nextEntryByKey = {};

        for (let i = 0; i < normalized.length; i++) {
            let entry = normalized[i];
            if (!entry.enabled) continue;

            let key = (entry.id && entry.id.length > 0) ? entry.id : ("idx_" + i);
            nextEntryByKey[key] = entry;

            let item = root.itemPool[key];
            if (!item) {
                item = menuItemComp.createObject(root);
                item.clicked.connect(() => root.executeEntryByKey(key));
                root.itemPool[key] = item;
            }

            item.text = entry.label;
            item.icon = entry.icon || "application-x-executable";
            newArr.push(item);
        }
        for (const k in root.itemPool) {
            if (!nextEntryByKey.hasOwnProperty(k)) {
                root.itemPool[k].destroy();
                delete root.itemPool[k];
            }
        }

        root.entryByKey = nextEntryByKey;
        root.dynamicModel = newArr;
        const buildMs = Date.now() - buildStartedAt;
        console.log("[perf][DesktopContextMenu] build model source=" + sourceName + " items=" + newArr.length + " ms=" + buildMs);

        if (root.perfMenuOpenStartedAt > 0) {
            const openMs = Date.now() - root.perfMenuOpenStartedAt;
            console.log("[perf][DesktopContextMenu] open latency ms=" + openMs + " source=" + sourceName);
            root.perfMenuOpenStartedAt = 0;
        }
    }

    function reloadMenu(forceDisk) {
        ContextMenuStore.ensureLoaded(forceDisk === true);
        if (ContextMenuStore.loaded && !ContextMenuStore.loading) {
            root.applyEntries(ContextMenuStore.entries, forceDisk === true ? "store_disk" : "store_cache");
        }
    }

    attachSideX: _flipX ? Controls.Menu.Left : Controls.Menu.Right
    attachSideY: _flipY ? Controls.Menu.Top : Controls.Menu.Bottom
    thisSideX: _flipX ? Controls.Menu.Right : Controls.Menu.Left
    thisSideY: _flipY ? Controls.Menu.Bottom : Controls.Menu.Top
    transparentBackground: true

    // While the menu is open the ContentWindow mask expands to cover the whole
    // screen, so desktop right-clicks land on this full-screen catcher instead of
    // Background.qml's TapHandler. Forward them so the menu reopens at the new spot.
    rightClickReposition: true
    onRightClickedAt: (x, y) => ContextMenuStore.openDesktopContextMenu(x, y, root.screenName)

    onExpandedChanged: {
        if (expanded) {
            root.perfMenuOpenStartedAt = Date.now();
            reloadMenu(false);
        }
    }

    Component.onCompleted: reloadMenu(true)

    Timer {
        id: execTimer

        property var pendingAction: null

        interval: 250
        repeat: false

        onTriggered: {
            if (pendingAction) pendingAction();
            pendingAction = null;
        }
    }

    Connections {
        function onEntriesChanged() {
            root.applyEntries(ContextMenuStore.entries, "store_update");
        }

        target: ContextMenuStore
    }

    Component {
        id: menuItemComp

        Controls.MenuItem {}
    }
}
