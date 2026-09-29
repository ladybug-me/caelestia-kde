pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.controls as Controls
import qs.utils

Controls.Menu {
    id: root

    property Item target: null

    property real menuExtent: 260

    readonly property DesktopEntry appEntry: target?.desktopEntry ?? null

    readonly property bool isPinnedToDock: appEntry ? Strings.testRegexList(GlobalConfig.bar.dock.pinnedApps, appEntry.id) : false

    signal renameRequested(Item delegateTarget)

    signal trashRequested(string path)

    function openFor(delegateItem, clickX, clickY): void {
        target = delegateItem;
        const bgW = backgroundItem && backgroundItem.implicitWidth > 0 ? backgroundItem.implicitWidth : menuExtent;
        const bgH = backgroundItem && backgroundItem.implicitHeight > 0 ? backgroundItem.implicitHeight : menuExtent;
        const flipX = delegateItem.x + clickX + bgW > delegateItem.parent.width;
        const flipY = delegateItem.y + clickY + bgH > delegateItem.parent.height;
        marginX = clickX - (flipX ? bgW : 0);
        marginY = clickY - (flipY ? bgH : 0);
        expanded = true;
    }

    function openTarget(): void {
        if (!target)
            return;
        if (target.desktopEntry)
            Launch.launchEntry(target.desktopEntry);
        else
            Launch.exec(["xdg-open", target.path]);
    }

    function revealTarget(): void {
        if (!target)
            return;
        const idx = Math.max(target.path.lastIndexOf("/"), 0);
        Launch.exec(["xdg-open", target.path.substring(0, idx)]);
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

    attachTo: target
    z: 9999
    attachSideX: Controls.Menu.Left
    attachSideY: Controls.Menu.Top
    thisSideX: Controls.Menu.Left
    thisSideY: Controls.Menu.Top

    items: [
        Controls.MenuItem {
            text: qsTr("Open")
            icon: "open_in_new"
            onClicked: {
                root.expanded = false;
                root.openTarget();
            }
        },
        Controls.MenuItem {
            text: qsTr("Show in File Manager")
            icon: "folder_open"
            onClicked: {
                root.expanded = false;
                root.revealTarget();
            }
        },
        Controls.MenuItem {
            text: root.isPinnedToDock ? qsTr("Unpin from dock") : qsTr("Pin to dock")
            icon: "push_pin"
            visible: root.appEntry !== null
            onClicked: {
                root.expanded = false;
                root.togglePinToDock();
            }
        },
        Controls.MenuItem {
            text: qsTr("Rename")
            icon: "edit"
            onClicked: {
                root.expanded = false;
                root.renameRequested(root.target);
            }
        },
        Controls.MenuItem {
            text: qsTr("Move to Trash")
            icon: "delete"
            onClicked: {
                root.expanded = false;
                root.trashRequested(root.target ? root.target.path : "");
            }
        }
    ]
}
