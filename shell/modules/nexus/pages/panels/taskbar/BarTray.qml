pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var entries: TrayRegistry.entries
    property bool dragging: false
    property string draggingId: ""
    property real grabDy: 0
    property real dragTop: 0
    property real landingY: 0
    property bool landing: false

    function stateLabel(state: string): string {
        switch (state) {
        case "visible":
            return qsTr("Always visible");
        case "hidden":
            return qsTr("Hidden");
        default:
            return qsTr("Collapse");
        }
    }

    function stateIcon(state: string): string {
        switch (state) {
        case "visible":
            return "push_pin";
        case "hidden":
            return "visibility_off";
        default:
            return "expand_more";
        }
    }

    function syncOrder(): void {
        if (root.dragging)
            return;

        const entries = root.entries;
        if (entries.length === orderModel.count && entries.every((entry, i) => {
            const row = orderModel.get(i);
            return row.trayId === entry.id && row.trayKey === entry.alias && row.title === entry.title && row.trayIcon === entry.icon && row.running === entry.running;
        }))
            return;

        orderModel.clear();
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            orderModel.append({
                trayId: entry.id,
                trayKey: entry.alias,
                title: entry.title,
                trayIcon: entry.icon,
                running: entry.running
            });
        }
    }

    function indexOfId(id: string): int {
        for (let i = 0; i < orderModel.count; i++) {
            if (orderModel.get(i).trayId === id)
                return i;
        }
        return -1;
    }

    function dragTo(id: string, sceneY: real): void {
        const content = orderList.contentItem;
        if (!content)
            return;

        const y = content.mapFromItem(null, 0, sceneY).y;

        if (root.draggingId !== id) {
            root.landing = false;
            landAnim.stop();
            root.draggingId = id;
            root.dragging = true;
            const item = orderList.itemAtIndex(root.indexOfId(id));
            root.grabDy = item ? y - item.y : 0;
        }

        root.dragTop = y - root.grabDy;

        const from = root.indexOfId(id);
        if (from === -1)
            return;

        const target = orderList.indexAt(orderList.width / 2, y);
        if (target === -1 || target === from)
            return;

        const item = orderList.itemAtIndex(target);
        if (!item)
            return;

        const mid = item.mapToItem(content, 0, 0).y + item.height / 2;
        if (from < target ? y < mid : y > mid)
            return;

        orderModel.move(from, target, 1);
    }

    function dropOrder(): void {
        if (!root.dragging)
            return;

        const from = root.indexOfId(root.draggingId);
        const own = orderList.itemAtIndex(from);

        root.landingY = own ? own.y : 0;
        root.landing = true;
        landAnim.start();
    }

    function commitOrder(): void {
        const ids = [];
        for (let i = 0; i < orderModel.count; i++)
            ids.push(orderModel.get(i).trayKey);

        const current = GlobalConfig.bar.tray.order;
        if (ids.length === current.length && ids.every((v, i) => v === current[i]))
            return;

        GlobalConfig.bar.tray.order = ids;
    }

    title: qsTr("Tray")
    isSubPage: true

    scrollReserve: 320

    Component.onCompleted: root.syncOrder()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Connections {
            function onEntriesChanged(): void {
                root.syncOrder();
            }

            target: TrayRegistry
        }

        Binding {
            target: root.flickable
            property: "interactive"
            value: root.scrollable && !root.dragging
        }

        ListModel {
            id: orderModel
        }

        Anim {
            id: landAnim

            target: root
            property: "dragTop"
            to: root.landingY
            type: Anim.FastSpatial
            onStopped: {
                if (!root.landing)
                    return;

                root.landing = false;
                root.dragging = false;
                root.draggingId = "";
                root.grabDy = 0;
                root.dragTop = 0;
                root.commitOrder();
            }
        }

        ToggleRow {
            first: true
            text: qsTr("Background")
            reset: ({ node: GlobalConfig.bar.tray, setting: "background" })
            checked: Config.bar.tray.background
            onToggled: GlobalConfig.bar.tray.background = checked
        }

        ToggleRow {
            text: qsTr("Recolor icons")
            reset: ({ node: GlobalConfig.bar.tray, setting: "recolour" })
            checked: Config.bar.tray.recolour
            onToggled: GlobalConfig.bar.tray.recolour = checked
        }

        ToggleRow {
            text: qsTr("Compact")
            reset: ({ node: GlobalConfig.bar.tray, setting: "compact" })
            checked: Config.bar.tray.compact
            onToggled: GlobalConfig.bar.tray.compact = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show the tray menu popout when hovering")
            reset: ({ node: GlobalConfig.bar.popouts, setting: "tray" })
            checked: Config.bar.popouts.tray
            onToggled: GlobalConfig.bar.popouts.tray = checked
        }

        SectionHeader {
            text: qsTr("Icons")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: !Config.bar.tray.compact
            text: qsTr("Collapsing is off, so every icon already stays on the bar. These choices apply once Compact is on.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        ListView {
            id: orderList

            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            interactive: false
            clip: false
            spacing: Tokens.spacing.extraSmall / 2
            model: orderModel
            delegate: orderDelegate

            move: Transition {
                Anim {
                    properties: "x,y"
                    type: Anim.FastSpatial
                }
            }

            displaced: Transition {
                Anim {
                    properties: "x,y"
                    type: Anim.FastSpatial
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: orderModel.count === 0
            text: qsTr("No tray icons have been seen yet.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: orderModel.count > 1
            text: qsTr("Drag a row to change the order")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        Component {
            id: orderDelegate

            SelectRow {
                id: row

                required property int index
                required property string trayId
                required property string trayKey
                required property string title
                required property string trayIcon
                required property bool running

                width: ListView.view.width
                height: row.implicitHeight
                reorderable: true
                highlight: root.draggingId === row.trayId
                liftY: root.draggingId === row.trayId ? root.dragTop - row.y : 0
                first: row.index === 0
                last: row.index === orderModel.count - 1
                label: row.title
                subtext: row.running ? row.trayId : qsTr("%1 (not running)").arg(row.trayId)
                icon: Icons.getTrayIcon(row.trayId, row.trayIcon)
                active: menuItems.find(item => item.value === TrayRegistry.stateOf(row.trayKey)) ?? null
                fallbackText: root.stateLabel(TrayRegistry.stateOf(row.trayKey))
                fallbackIcon: root.stateIcon(TrayRegistry.stateOf(row.trayKey))
                onSelected: item => {
                    if (item.value === "forget")
                        TrayRegistry.forget(row.trayKey);
                    else
                        TrayRegistry.setState(row.trayKey, item.value);
                }
                onReorderStart: root.dragging = true
                onReorderDrag: sceneY => root.dragTo(row.trayId, sceneY)
                onReorderDrop: root.dropOrder()

                menuItems: [
                    MenuItem {
                        text: root.stateLabel("visible")
                        icon: root.stateIcon("visible")
                        value: "visible"
                    },
                    MenuItem {
                        text: root.stateLabel("collapsed")
                        icon: root.stateIcon("collapsed")
                        value: "collapsed"
                    },
                    MenuItem {
                        text: root.stateLabel("hidden")
                        icon: root.stateIcon("hidden")
                        value: "hidden"
                    },
                    MenuItem {
                        visible: !row.running
                        text: qsTr("Forget")
                        icon: "delete"
                        value: "forget"
                    }
                ]
            }
        }
    }
}
