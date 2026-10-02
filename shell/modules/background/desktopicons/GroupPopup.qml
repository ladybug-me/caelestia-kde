pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// The panel an open group shows its members in. Sits next to the group's
// icon; members can be opened, selected, reordered and dragged back out.
Item {
    id: root

    required property var controller
    property rect anchorRect

    readonly property bool open: controller.openGroupId !== ""
    // Stays on the last group while the panel animates closed.
    property string shownId: ""
    readonly property var group: DesktopLayout.groups[shownId] ?? null
    readonly property var members: (group?.members ?? []).filter(m => !!controller.files[m])
    property var previewOrder: null
    readonly property var displayOrder: previewOrder ?? members
    property bool joinHover: false

    readonly property int columns: Math.max(1, Math.min(5, members.length <= 4 ? members.length : Math.ceil(Math.sqrt(members.length))))
    readonly property int gridRows: Math.max(1, Math.ceil(members.length / columns))
    readonly property real progress: open ? 1 : 0
    property real shown: progress

    function memberPositions(): var {
        const out = {};
        members.forEach((m, i) => out[DesktopLayout.fileKey(m)] = { col: i % columns, row: Math.floor(i / columns) });
        return out;
    }

    function order(): var {
        return members.map(m => DesktopLayout.fileKey(m));
    }

    function range(a: string, b: string): var {
        const keys = order();
        const ia = keys.indexOf(a);
        const ib = keys.indexOf(b);
        if (ia === -1 || ib === -1)
            return ib === -1 ? [] : [b];
        return keys.slice(Math.min(ia, ib), Math.max(ia, ib) + 1);
    }

    function indexAt(x: real, y: real): int {
        const p = grid.mapFromItem(root, x, y);
        const col = Math.max(0, Math.min(columns - 1, Math.floor(p.x / controller.cellWidth)));
        const row = Math.max(0, Math.floor(p.y / controller.cellHeight));
        return Math.min(members.length - 1, row * columns + col);
    }

    function draggedNames(): var {
        return controller.dragKeys.filter(k => !controller.isGroupKey(k)).map(k => controller.nameOf(k));
    }

    function startTitleRename(): void {
        if (!group)
            return;
        if (controller.renameActive && controller.renamingDelegate !== title)
            controller.renamingDelegate.commitRename();
        controller.renamingDelegate = title;
        title.startRename(group.name);
    }

    anchors.fill: parent
    visible: shown > 0
    onOpenChanged: {
        if (open)
            shownId = controller.openGroupId;
    }

    onMembersChanged: {
        const want = {};
        for (const m of members)
            want[m] = true;
        for (let i = membersModel.count - 1; i >= 0; i--)
            if (!want[membersModel.get(i).name])
                membersModel.remove(i);
        const have = {};
        for (let i = 0; i < membersModel.count; i++)
            have[membersModel.get(i).name] = true;
        for (const m of members)
            if (!have[m])
                membersModel.append({ name: m });
    }

    Behavior on shown {
        Anim {
            type: open ? Anim.DefaultSpatial : Anim.FastEffects
        }
    }

    Connections {
        function onOpenGroupIdChanged(): void {
            if (root.controller.openGroupId !== "")
                root.shownId = root.controller.openGroupId;
        }

        target: root.controller
    }

    ListModel {
        id: membersModel
    }

    // Clicking outside closes the group.
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.controller.closeGroup()
    }

    Elevation {
        id: panel

        readonly property real pad: Tokens.padding.large
        readonly property real wantX: root.anchorRect.x + root.anchorRect.width / 2 - width / 2
        readonly property real wantY: root.anchorRect.y + root.anchorRect.height / 2 - height / 2

        x: Math.max(Tokens.padding.large, Math.min(root.width - width - Tokens.padding.large, wantX))
        y: Math.max(Tokens.padding.large, Math.min(root.height - height - Tokens.padding.large, wantY))
        width: root.columns * root.controller.cellWidth + pad * 2
        height: Math.min(root.height * 0.8, title.height + Tokens.spacing.medium + root.gridRows * root.controller.cellHeight + pad * 2)
        radius: Tokens.rounding.large
        level: 3
        opacity: root.shown * (root.controller.dragGroup === root.shownId && root.shownId !== "" && !dropArea.containsDrag ? 0.3 : 1)
        transform: Scale {
            origin.x: root.anchorRect.x + root.anchorRect.width / 2 - panel.x
            origin.y: root.anchorRect.y + root.anchorRect.height / 2 - panel.y
            xScale: 0.4 + 0.6 * root.shown
            yScale: 0.4 + 0.6 * root.shown
        }

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on width {
            Anim {}
        }

        Behavior on height {
            Anim {}
        }

        // Swallow clicks on the panel background so they do not close it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: {
                root.controller.grabKeyboard();
                root.controller.clearSelection();
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: GlobalConfig.appearance.pitchBlack ? "#000000" : Qt.alpha(Colours.palette.m3surfaceContainer, 0.96)
            border.width: root.joinHover ? 2 : 0
            border.color: Colours.palette.m3primary
            clip: true

            GroupTitle {
                id: title

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: panel.pad
                text: root.group?.name ?? ""
                onRenameRequested: root.startTitleRename()
                onRenameCommitted: text => {
                    root.controller.finishRename(title);
                    root.controller.renameGroup(root.shownId, text);
                }
                onRenameCancelled: root.controller.finishRename(title)
            }

            Flickable {
                id: flick

                anchors.top: title.bottom
                anchors.topMargin: Tokens.spacing.medium
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: panel.pad
                anchors.rightMargin: panel.pad
                anchors.bottomMargin: panel.pad
                contentHeight: grid.height
                interactive: contentHeight > height
                clip: true

                Item {
                    id: grid

                    width: root.columns * root.controller.cellWidth
                    height: root.gridRows * root.controller.cellHeight

                    Repeater {
                        model: membersModel

                        IconTile {
                            id: tile

                            required property string name
                            readonly property string tileKey: DesktopLayout.fileKey(name)
                            readonly property int slot: root.displayOrder.indexOf(name)

                            key: tileKey
                            entry: root.controller.files[name] ?? null
                            visible: slot !== -1
                            width: root.controller.cellWidth
                            height: root.controller.cellHeight
                            x: (Math.max(0, slot) % root.columns) * root.controller.cellWidth
                            y: Math.floor(Math.max(0, slot) / root.columns) * root.controller.cellHeight
                            z: selected ? 2 : 1
                            iconSize: root.controller.iconSize
                            materialYou: root.controller.materialYou
                            vibrant: root.controller.vibrant
                            pointingCursor: DesktopLayout.singleClick
                            selected: root.controller.selection[tileKey] === true && root.open
                            focusVisible: root.controller.keyboardActive && root.controller.focusKey === tileKey && root.open
                            dimmed: root.controller.dragGroup === root.shownId && root.controller.dragKeys.indexOf(tileKey) !== -1

                            Component.onCompleted: {
                                const next = Object.assign({}, root.controller.tiles);
                                next[tileKey] = tile;
                                root.controller.tiles = next;
                            }
                            Component.onDestruction: {
                                if (root.controller.tiles[tileKey] === tile) {
                                    const next = Object.assign({}, root.controller.tiles);
                                    delete next[tileKey];
                                    root.controller.tiles = next;
                                }
                                root.controller.finishRename(tile);
                            }

                            onPressed: mouse => root.controller.tilePressed(tileKey, mouse)
                            onClicked: mouse => root.controller.tileClicked(tileKey, mouse)
                            onDoubleClicked: mouse => root.controller.tileDoubleClicked(tileKey, mouse)
                            onContextMenuRequested: (x, y) => root.controller.tileContextMenu(tileKey, x, y)
                            onDragRequested: root.controller.beginDrag(tileKey)
                            onRenameCommitted: text => {
                                root.controller.finishRename(tile);
                                root.controller.applyRename(tileKey, text);
                            }
                            onRenameCancelled: root.controller.finishRename(tile)

                            Behavior on x {
                                Anim {}
                            }

                            Behavior on y {
                                Anim {}
                            }
                        }
                    }
                }
            }
        }

        DropArea {
            id: dropArea

            function update(drag: var): void {
                if (root.controller.dragGroup !== root.shownId) {
                    root.joinHover = root.controller.dragGroup === "";
                    return;
                }
                const names = root.draggedNames();
                const rest = root.members.filter(m => names.indexOf(m) === -1);
                const at = Math.min(rest.length, root.indexAt(drag.x + panel.x, drag.y + panel.y));
                rest.splice(at, 0, ...root.members.filter(m => names.indexOf(m) !== -1));
                root.previewOrder = rest;
            }

            anchors.fill: parent
            enabled: root.open
            onEntered: drag => {
                if (!root.controller.isInternal(drag)) {
                    drag.accepted = false;
                    return;
                }
                drag.accept(Qt.MoveAction);
                update(drag);
            }
            onPositionChanged: drag => update(drag)
            onExited: {
                root.previewOrder = null;
                root.joinHover = false;
            }
            onDropped: drop => {
                const fromHere = root.controller.dragGroup === root.shownId;
                const index = root.indexAt(drop.x + panel.x, drop.y + panel.y);
                root.previewOrder = null;
                root.joinHover = false;
                drop.accept(Qt.MoveAction);
                if (fromHere)
                    root.controller.reorderGroup(root.shownId, root.draggedNames(), index);
                else if (root.controller.dragGroup === "" && root.controller.groupable(root.controller.dragKeys.concat([DesktopLayout.groupKey(root.shownId)])))
                    root.controller.makeGroup(root.controller.dragKeys, null, root.shownId);
            }
        }
    }
}
