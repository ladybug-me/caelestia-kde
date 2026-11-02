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
    property var submenuRows: ({})
    readonly property bool iconsEnabled: screenName ? ContextMenuStore.iconsShownOn(screenName) : GlobalConfig.background.desktopIconsEnabled
    readonly property bool iconsShown: (screenName ? GlobalConfig.forScreen(screenName) : GlobalConfig).background.desktopIconsEnabled

    function executeEntryByKey(key) {
        let entry = root.entryByKey[key];
        if (!entry) return;

        root.close();

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
            WidgetEditor.close();
            ContextMenuStore.editMode = true;
            return;
        }
        if (entry.action === "EditWidgets") {
            WidgetEditor.toggle();
            // The menu held the keyboard while it was open, so the desktop has to
            // take it back for Escape and Delete to reach the editor.
            if (WidgetEditor.active)
                DesktopLayout.controllerFor(root.screenName)?.grabKeyboard();
            return;
        }
        if (entry.action === "ToggleWidgetLock") {
            // Any unlocked widget means the next click locks them all; only when
            // everything is already locked does the entry unlock the set.
            DesktopLayout.setAllWidgetsLocked(DesktopLayout.anyWidgetUnlocked());
            return;
        }
        if (entry.action === "ToggleWidgetOutlines") {
            DesktopLayout.setWidgetOutlines(!DesktopLayout.widgetOutlines);
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

    function isGroupEntry(entry) {
        return entry.type === "group" && entry.children && entry.children.length > 0;
    }

    function submenuEntry(key, entry) {
        let item = root.submenuRows[key];
        if (!item) {
            item = menuItemComp.createObject(root);
            item.clicked.connect(() => root.executeEntryByKey(key));
            root.submenuRows[key] = item;
        }

        if (entry.action === "EditWidgets") {
            item.text = Qt.binding(() => WidgetEditor.active ? qsTr("Done Editing Widgets") : (entry.label || qsTr("Edit Widgets")));
            item.icon = Qt.binding(() => WidgetEditor.active ? "check" : (entry.icon || "edit"));
            item.visible = Qt.binding(() => !Config.background.disableQuickshellDesktop);
        } else if (entry.action === "AddWidget") {
            item.text = entry.label;
            item.icon = entry.icon || "widgets";
            item.visible = Qt.binding(() => root.iconsShown);
        } else if (entry.action === "ToggleWidgetLock") {
            item.text = Qt.binding(() => DesktopLayout.anyWidgetUnlocked() ? qsTr("Lock All Widgets") : qsTr("Unlock All Widgets"));
            item.icon = Qt.binding(() => DesktopLayout.anyWidgetUnlocked() ? "lock" : "lock_open");
            item.visible = true;
        } else if (entry.action === "ToggleWidgetOutlines") {
            item.text = entry.label;
            item.icon = Qt.binding(() => DesktopLayout.widgetOutlines ? "check_box" : "check_box_outline_blank");
            item.visible = true;
        } else {
            item.text = entry.label;
            item.icon = entry.icon || "widgets";
            item.visible = true;
        }

        return item;
    }

    function applyEntries(entries, sourceName) {
        const buildStartedAt = Date.now();
        const normalized = (!entries || entries.length === 0)
            ? ContextMenuStore.cloneEntries(ContextMenuStore.defaultEntries())
            : ContextMenuStore.cloneEntries(entries);
        const newArr = [];
        const nextEntryByKey = {};
        const nextSubmenuKeys = {};

        for (let i = 0; i < normalized.length; i++) {
            let entry = normalized[i];
            if (!entry.enabled) continue;

            let key = (entry.id && entry.id.length > 0) ? entry.id : ("idx_" + i);
            nextEntryByKey[key] = entry;

            if (root.isGroupEntry(entry)) {
                const children = [];
                for (let c = 0; c < entry.children.length; c++) {
                    const child = entry.children[c];
                    if (!child || child.enabled === false) continue;

                    const childKey = (child.id && child.id.length > 0) ? child.id : (key + "_" + c);
                    nextEntryByKey[childKey] = child;
                    nextSubmenuKeys[childKey] = true;
                    children.push(root.submenuEntry(childKey, child));
                }

                if (children.length === 0) continue;

                let item = root.itemPool[key];
                if (!item) {
                    item = menuItemComp.createObject(root);
                    root.itemPool[key] = item;
                }

                item.text = entry.label || qsTr("Widgets");
                item.icon = entry.icon || "widgets";
                item.visible = true;
                item.submenu = children;
                newArr.push(item);
                continue;
            }

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
        for (const k in root.submenuRows) {
            if (!nextSubmenuKeys.hasOwnProperty(k)) {
                root.submenuRows[k].destroy();
                delete root.submenuRows[k];
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

    // Every entry has to be reachable without scrolling, so the menu grows to its content.
    // The window is the only real limit: past that the entries would be off-screen rather
    // than a short flick away, and the menu flips above the cursor when it will not fit
    // below. The floor keeps the old clamp if the window is not measured yet.
    maxHeight: Math.max(320, root.height > 0 ? root.height - Tokens.padding.large : 560)

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
