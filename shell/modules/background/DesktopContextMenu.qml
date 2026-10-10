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
    readonly property bool iconsEnabled: screenName ? ContextMenuStore.iconsShownOn(screenName) : GlobalConfig.background.desktopIconsEnabled
    readonly property bool iconsShown: (screenName ? GlobalConfig.forScreen(screenName) : GlobalConfig).background.desktopIconsEnabled

    function executeEntryByKey(key) {
        let entry = root.entryByKey[key];
        if (!entry) return;

        root.expanded = false;

        // In-shell state changes run right away; anything that opens a window
        // or spawns a process waits for the menu to finish closing.
        if (entry.action === "Paste") {
            DesktopLayout.pasteRequested(root.screenName, root.attachTo.x, root.attachTo.y);
            return;
        }
        if (entry.action === "AddWidget") {
            DesktopLayout.addWidgetRequested(root.screenName, root.attachTo.x, root.attachTo.y);
            return;
        }
        if (entry.action === "ArrangeIcons") {
            DesktopLayout.viewOptionsRequested(root.screenName, root.attachTo.x, root.attachTo.y);
            return;
        }
        if (entry.action === "ToggleDesktopIcons") {
            ContextMenuStore.toggleIcons(root.screenName);
            return;
        }
        if (entry.action === "EnterEditMode") {
            ContextMenuStore.editMode = true;
            return;
        }
        if (entry.action === "Wallpapers.next()") {
            Wallpapers.next();
            return;
        }

        execTimer.pendingAction = () => {
            if (entry.action) {
                if (entry.action === "Quickshell.reload()") Quickshell.reload();
                else if (entry.action === "WindowFactory.create()") WindowFactory.create();
                else if (entry.action === "OpenRightClickMenu") {
                    WindowFactory.create(null, {
                        initialPageIdx: PageRegistry.indexForKey("desktop"),
                        initialSubPageIdx: 2
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

            if (entry.action === "ToggleDesktopIcons") {
                item.text = Qt.binding(() => root.iconsEnabled ? qsTr("Hide Desktop Icons") : qsTr("Show Desktop Icons"));
                item.icon = Qt.binding(() => root.iconsEnabled ? "visibility_off" : "visibility");
                item.visible = true;
            } else if (entry.action === "Paste") {
                item.text = entry.label;
                item.icon = entry.icon || "content_paste";
                item.visible = Qt.binding(() => root.iconsShown && DesktopLayout.clipboardHasFiles);
            } else if (entry.action === "AddWidget") {
                item.text = entry.label;
                item.icon = entry.icon || "widgets";
                item.visible = Qt.binding(() => root.iconsShown);
            } else if (entry.action === "ArrangeIcons") {
                item.text = entry.label;
                item.icon = entry.icon || "sort";
                item.visible = Qt.binding(() => root.iconsShown);
            } else {
                item.text = entry.label;
                item.icon = entry.icon || "widgets";
                item.visible = true;
            }
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
    }

    function reloadMenu(forceDisk) {
        ContextMenuStore.ensureLoaded(forceDisk === true);
        if (ContextMenuStore.loaded && !ContextMenuStore.loading) {
            root.applyEntries(ContextMenuStore.entries, forceDisk === true ? "store_disk" : "store_cache");
        }
    }

    // The model is rebuilt only when the store's entries change, so opening
    // the menu does not recreate every row.
    function refresh() {
        ContextMenuStore.ensureLoaded(false);
    }

    // Called when the menu is requested again while already open.
    function reopen() {
        refresh();
        replayReveal();
    }

    attachSideX: _flipX ? Controls.Menu.Left : Controls.Menu.Right
    attachSideY: _flipY ? Controls.Menu.Top : Controls.Menu.Bottom
    thisSideX: _flipX ? Controls.Menu.Right : Controls.Menu.Left
    thisSideY: _flipY ? Controls.Menu.Bottom : Controls.Menu.Top
    transparentBackground: true
    revealHorizontal: true

    rightClickReposition: true
    onRightClickedAt: (x, y) => ContextMenuStore.openDesktopContextMenu(x, y, root.screenName)

    onExpandedChanged: {
        if (expanded) {
            DesktopLayout.refreshClipboard();
            refresh();
        }
    }

    Component.onCompleted: reloadMenu(true)

    Timer {
        id: execTimer

        property var pendingAction: null

        interval: Tokens.anim.durations.small
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
