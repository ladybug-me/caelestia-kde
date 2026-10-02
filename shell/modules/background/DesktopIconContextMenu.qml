pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.controls as Controls
import qs.services
import qs.utils

Controls.Menu {
    id: root

    required property var controller

    // What the menu acts on: the selected keys, and the open group they sit in.
    property var keys: []
    property string groupId: ""

    readonly property bool single: keys.length === 1
    readonly property string firstKey: keys[0] ?? ""
    readonly property bool firstIsGroup: firstKey !== "" && controller.isGroupKey(firstKey)
    readonly property var firstEntry: single && !firstIsGroup ? controller.entryOf(firstKey) : null
    readonly property DesktopEntry appEntry: firstEntry?.desktopEntry ?? null
    readonly property bool hasGroups: keys.some(k => controller.isGroupKey(k))
    readonly property bool hasWidgets: keys.some(k => controller.isWidgetKey(k))
    readonly property bool onlyWidgets: keys.length > 0 && keys.every(k => controller.isWidgetKey(k))
    readonly property bool hasFiles: controller.entriesFor(keys).length > 0
    readonly property var firstWidget: single ? controller.widgetOf(firstKey) : null
    readonly property bool firstIsBig: single && controller.isBigKey(firstKey)
    readonly property bool isPinnedToDock: appEntry ? Strings.testRegexList(GlobalConfig.bar.dock.pinnedApps, appEntry.id) : false

    function openAt(x: real, y: real, selected: var, inGroup: string): void {
        keys = selected;
        groupId = inGroup;
        anchor.x = x;
        anchor.y = y;
        const bgW = backgroundItem && backgroundItem.implicitWidth > 0 ? backgroundItem.implicitWidth : 260;
        const bgH = backgroundItem && backgroundItem.implicitHeight > 0 ? backgroundItem.implicitHeight : maxHeight;
        marginX = x + bgW > controller.width ? -bgW : 0;
        marginY = y + bgH > controller.height ? -bgH : 0;
        expanded = true;
    }

    function togglePinToDock(): void {
        if (!appEntry?.id)
            return;
        const current = GlobalConfig.bar.dock.pinnedApps ? [...GlobalConfig.bar.dock.pinnedApps] : [];
        const id = appEntry.id;
        if (Strings.testRegexList(current, id)) {
            const idx = current.indexOf(id);
            if (idx !== -1)
                current.splice(idx, 1);
        } else {
            current.push(id);
        }
        GlobalConfig.bar.dock.pinnedApps = current;
    }

    attachTo: anchor
    z: 9999
    maxHeight: 560
    attachSideX: Controls.Menu.Left
    attachSideY: Controls.Menu.Top
    thisSideX: Controls.Menu.Left
    thisSideY: Controls.Menu.Top

    items: [
        Controls.MenuItem {
            text: !root.single ? qsTr("Open %1 Items").arg(root.keys.length) : root.firstIsGroup ? qsTr("Open Group") : qsTr("Open")
            icon: "open_in_new"
            visible: !root.onlyWidgets
            onClicked: root.controller.openKeys(root.keys)
        },
        Controls.MenuItem {
            text: qsTr("Show in File Manager")
            icon: "folder_open"
            visible: root.firstEntry !== null
            onClicked: {
                const path = root.firstEntry.path;
                Launch.exec(["xdg-open", path.substring(0, Math.max(path.lastIndexOf("/"), 0))]);
            }
        },
        Controls.MenuItem {
            text: root.isPinnedToDock ? qsTr("Unpin from dock") : qsTr("Pin to dock")
            icon: "push_pin"
            visible: root.appEntry !== null
            onClicked: root.togglePinToDock()
        },
        Controls.MenuItem {
            text: qsTr("Rename")
            icon: "edit"
            visible: root.single && !root.hasWidgets
            onClicked: root.controller.startRename(root.firstKey)
        },
        Controls.MenuItem {
            text: root.firstIsBig ? qsTr("Show as Icon") : qsTr("Show as Large Folder")
            icon: root.firstIsBig ? "collapse_content" : "expand_content"
            visible: root.single && root.firstIsGroup && root.groupId === ""
            onClicked: {
                const size = root.controller.widgetCatalog.group.size;
                if (root.firstIsBig)
                    root.controller.resizeItem(root.firstKey, 1, 1);
                else
                    root.controller.resizeItem(root.firstKey, size.w, size.h);
            }
        },
        Controls.MenuItem {
            text: qsTr("Change Folder...")
            icon: "drive_folder_upload"
            visible: root.firstWidget?.type === "folder"
            onClicked: root.controller.tiles[root.firstKey]?.content?.chooseFolder()
        },
        Controls.MenuItem {
            text: qsTr("Open in File Manager")
            icon: "folder_open"
            visible: root.firstWidget?.type === "folder"
            onClicked: root.controller.tiles[root.firstKey]?.content?.openInFileManager()
        },
        Controls.MenuItem {
            text: qsTr("Group Items")
            icon: "folder_special"
            visible: root.groupId === "" && root.controller.groupable(root.keys)
            onClicked: root.controller.groupSelection()
        },
        Controls.MenuItem {
            text: qsTr("Ungroup")
            icon: "folder_off"
            visible: root.groupId === "" && root.hasGroups
            onClicked: root.keys.filter(k => root.controller.isGroupKey(k)).forEach(k => root.controller.ungroup(root.controller.nameOf(k)))
        },
        Controls.MenuItem {
            text: qsTr("Remove from Group")
            icon: "drive_file_move"
            visible: root.groupId !== ""
            onClicked: {
                const id = root.groupId;
                root.controller.closeGroup();
                root.controller.removeFromGroup(id, root.keys.map(k => root.controller.nameOf(k)), null);
            }
        },
        Controls.MenuItem {
            text: qsTr("Copy")
            icon: "content_copy"
            visible: root.hasFiles
            onClicked: root.controller.copyKeys(root.keys, false)
        },
        Controls.MenuItem {
            text: qsTr("Cut")
            icon: "content_cut"
            visible: root.hasFiles
            onClicked: root.controller.copyKeys(root.keys, true)
        },
        Controls.MenuItem {
            text: root.hasGroups ? qsTr("Move Contents to Trash") : qsTr("Move to Trash")
            icon: "delete"
            visible: root.hasFiles
            onClicked: root.controller.trashKeys(root.keys)
        },
        Controls.MenuItem {
            text: root.keys.filter(k => root.controller.isWidgetKey(k)).length > 1 ? qsTr("Remove Widgets") : qsTr("Remove Widget")
            icon: "close"
            visible: root.hasWidgets
            onClicked: root.controller.removeWidgets(root.keys)
        }
    ]

    Item {
        id: anchor

        parent: root.controller
    }
}
