pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls as Controls

// Asks what to do with files dropped in from another app, like Plasma does.
Controls.Menu {
    id: root

    property var controller: null

    property var urls: []
    property string dest: ""
    property var cell: null

    readonly property bool allLocal: urls.every(u => u.startsWith("file://"))

    function openAt(x: real, y: real, dropped: var, target: string, at: var): void {
        urls = dropped;
        dest = target;
        cell = at;
        anchor.x = x;
        anchor.y = y;
        const bgW = backgroundItem && backgroundItem.implicitWidth > 0 ? backgroundItem.implicitWidth : 220;
        const bgH = backgroundItem && backgroundItem.implicitHeight > 0 ? backgroundItem.implicitHeight : 220;
        marginX = x + bgW > root.width ? -bgW : 0;
        marginY = y + bgH > root.height ? -bgH : 0;
        expanded = true;
    }

    function run(action: string): void {
        controller?.transfer(urls, dest, action, cell);
        urls = [];
    }

    attachTo: anchor
    z: 9999
    attachSideX: Controls.Menu.Left
    attachSideY: Controls.Menu.Top
    thisSideX: Controls.Menu.Left
    thisSideY: Controls.Menu.Top

    items: [
        Controls.MenuItem {
            text: qsTr("Move Here")
            icon: "drive_file_move"
            visible: root.allLocal
            onClicked: root.run("move")
        },
        Controls.MenuItem {
            text: qsTr("Copy Here")
            icon: "content_copy"
            onClicked: root.run("copy")
        },
        Controls.MenuItem {
            text: qsTr("Link Here")
            icon: "link"
            visible: root.allLocal
            onClicked: root.run("link")
        },
        Controls.MenuItem {
            text: qsTr("Cancel")
            icon: "close"
            onClicked: root.urls = []
        }
    ]

    Item {
        id: anchor
    }
}
