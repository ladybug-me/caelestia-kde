pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.components.controls as Controls
import qs.services

// Right-click menu for a single desktop icon: open it, reveal the parent
// folder in the file manager, start the icon's inline rename editor, or
// move the file to the trash. One instance per DesktopIcons is retargeted
// to whichever delegate was right-clicked (see openFor()).
Controls.Menu {
    id: root

    property Item target: null

    property real menuExtent: 260

    signal renameRequested(Item delegateTarget)

    signal trashRequested(string path)

    function openFor(delegateItem, clickX, clickY): void {
        target = delegateItem;
        const bgW = backgroundItem && backgroundItem.implicitWidth > 0 ? backgroundItem.implicitWidth : menuExtent;
        const bgH = backgroundItem && backgroundItem.implicitHeight > 0 ? backgroundItem.implicitHeight : menuExtent;
        // Menu corner lands on the cursor; flip near the desktop edges so it
        // never spills off screen.
        const flipX = delegateItem.x + clickX + bgW > delegateItem.parent.width;
        const flipY = delegateItem.y + clickY + bgH > delegateItem.parent.height;
        marginX = clickX - (flipX ? bgW : 0);
        marginY = clickY - (flipY ? bgH : 0);
        expanded = true;
    }

    function openTarget(): void {
        if (!target)
            return;
        const p = target.path;
        if (p.toLowerCase().endsWith(".desktop"))
            Launch.exec(["kioclient", "exec", p]);
        else
            Launch.exec(["xdg-open", p]);
    }

    function revealTarget(): void {
        if (!target)
            return;
        const idx = Math.max(target.path.lastIndexOf("/"), 0);
        Launch.exec(["xdg-open", target.path.substring(0, idx)]);
    }

    attachTo: target

    z: 9999

    // The menu's own corner is positioned purely through marginX/marginY in
    // openFor(); anchoring to the delegate's top-left keeps that math honest.
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
