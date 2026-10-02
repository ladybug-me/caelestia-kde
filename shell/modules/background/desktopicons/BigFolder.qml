pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A group shown as a large folder: a grid of its app icons, each opening with
// one click. When they do not all fit, the last slot previews the rest and
// opens the full group. Names show when hovering, since the icons have none.
Item {
    id: root

    property var frame
    property var controller

    readonly property string groupId: frame.itemId
    readonly property var entries: controller.groupEntries(groupId)

    // Icons are sized for a 3x3 folder and keep that size: a bigger folder
    // fits more of them instead of drawing them larger.
    readonly property size reference: areaFor(3, 3)
    readonly property real slot: Math.min(reference.width, reference.height) / 3
    // Whole pixels throughout: icons drawn at fractional sizes or positions
    // get resampled and come out blurry.
    readonly property int iconSize: Math.round(slot * 0.82)
    // Laid out for the size the folder is heading to, not the animated one,
    // so the icons move once while the card grows around them.
    readonly property size target: areaFor(frame.span.w, frame.span.h)
    readonly property int columns: Math.max(1, Math.floor(target.width / slot))
    readonly property int rows: Math.max(1, Math.floor(target.height / slot))
    readonly property int capacity: columns * rows
    readonly property bool overflow: entries.length > capacity
    readonly property int shownCount: overflow ? capacity - 1 : entries.length
    readonly property var rest: overflow ? entries.slice(capacity - 1, capacity + 3) : []
    readonly property real offsetX: (target.width - columns * slot) / 2
    readonly property real offsetY: (target.height - rows * slot) / 2
    property Item hoveredSlot: null

    // Room the content gets at a given size in cells, matching BigItem's margins.
    function areaFor(w: int, h: int): size {
        const inset = Tokens.padding.small * 2;
        return Qt.size(w * controller.cellWidth - frame.sideGap * 2 - inset, h * controller.cellHeight - frame.topGap - frame.labelHeight - inset);
    }

    function slotX(index: int): real {
        return Math.round(offsetX + (index % columns) * slot);
    }

    function slotY(index: int): real {
        return Math.round(offsetY + Math.floor(index / columns) * slot);
    }

    function syncMembers(): void {
        const names = entries.map(e => e.fileName);
        for (let i = members.count - 1; i >= 0; i--)
            if (names.indexOf(members.get(i).name) === -1)
                members.remove(i);
        for (let i = 0; i < names.length; i++) {
            let at = -1;
            for (let j = i; j < members.count; j++) {
                if (members.get(j).name === names[i]) {
                    at = j;
                    break;
                }
            }
            if (at === -1)
                members.insert(i, { name: names[i] });
            else if (at !== i)
                members.move(at, i, 1);
        }
    }

    onEntriesChanged: syncMembers()
    Component.onCompleted: syncMembers()

    // One delegate per member that lives as long as the member does, so a
    // resize only moves icons around instead of rebuilding them.
    ListModel {
        id: members
    }

    Repeater {
        model: members

        Item {
            id: slotItem

            required property string name
            required property int index
            readonly property var modelData: root.controller.files[name] ?? null
            readonly property string memberKey: DesktopLayout.fileKey(name)
            readonly property bool dragged: root.controller.dragGroup === root.groupId && root.controller.dragKeys.indexOf(memberKey) !== -1
            readonly property bool fits: index < root.shownCount

            x: root.slotX(index)
            y: root.slotY(index)
            width: root.slot
            height: root.slot
            opacity: !fits ? 0 : dragged ? 0.35 : 1
            scale: fits ? 1 : 0.6
            visible: opacity > 0
            enabled: fits

            Behavior on x {
                Anim {}
            }

            Behavior on y {
                Anim {}
            }

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            EntryIcon {
                id: icon

                anchors.centerIn: parent
                width: root.iconSize
                height: width
                entry: slotItem.modelData
                materialYou: root.controller.materialYou
                vibrant: root.controller.vibrant
                scale: slotArea.pressed ? 0.92 : slotArea.containsMouse ? 1.08 : 1

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            MouseArea {
                id: slotArea

                property point pressPos
                property bool dragSent: false

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onContainsMouseChanged: {
                    if (containsMouse)
                        root.hoveredSlot = slotItem;
                    else if (root.hoveredSlot === slotItem)
                        root.hoveredSlot = null;
                }
                onPressed: mouse => {
                    pressPos = Qt.point(mouse.x, mouse.y);
                    dragSent = false;
                    root.controller.grabKeyboard();
                }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton) || dragSent)
                        return;
                    const dx = mouse.x - pressPos.x;
                    const dy = mouse.y - pressPos.y;
                    if (dx * dx + dy * dy >= Qt.styleHints.startDragDistance * Qt.styleHints.startDragDistance) {
                        dragSent = true;
                        root.hoveredSlot = null;
                        root.controller.beginMemberDrag(root.groupId, slotItem.name, icon, pressPos.x - icon.x, pressPos.y - icon.y);
                    }
                }
                // Large folders act like a launcher: one click opens.
                onClicked: mouse => {
                    if (dragSent || !slotItem.modelData)
                        return;
                    if (mouse.button === Qt.RightButton) {
                        const p = mapToItem(root.controller, mouse.x, mouse.y);
                        root.controller.memberContextMenu(root.groupId, slotItem.name, p.x, p.y);
                    } else {
                        slotItem.modelData.launch();
                    }
                }
            }
        }
    }

    // The rest of the group in miniature; opens the whole group.
    Item {
        x: root.slotX(Math.max(0, root.capacity - 1))
        y: root.slotY(Math.max(0, root.capacity - 1))
        width: root.slot
        height: root.slot
        opacity: root.overflow ? 1 : 0
        visible: opacity > 0

        Behavior on x {
            Anim {}
        }

        Behavior on y {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: Math.round(root.iconSize * 0.08)
            scale: moreArea.pressed ? 0.92 : moreArea.containsMouse ? 1.08 : 1

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            // A fixed four slots so the previews are not rebuilt on resize.
            Repeater {
                model: 4

                EntryIcon {
                    required property int index

                    width: Math.round(root.iconSize * 0.46)
                    height: width
                    entry: root.rest[index] ?? null
                    visible: !!entry
                    materialYou: root.controller.materialYou
                    vibrant: root.controller.vibrant
                }
            }
        }

        MouseArea {
            id: moreArea

            anchors.fill: parent
            enabled: root.overflow
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.controller.openGroup(root.groupId)
        }
    }

    // Name of the hovered app.
    StyledRect {
        id: bubble

        readonly property Item target: root.hoveredSlot
        property string text

        x: target ? Math.max(-Tokens.padding.large, Math.min(root.width - width + Tokens.padding.large, target.x + target.width / 2 - width / 2)) : x
        y: target ? target.y - height + Tokens.padding.small : y
        z: 5
        implicitWidth: bubbleText.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: bubbleText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: Colours.palette.m3inverseSurface
        opacity: target && bubbleDelay.ready ? 1 : 0
        visible: opacity > 0

        onTargetChanged: {
            if (target) {
                text = target.modelData?.displayName ?? "";
                bubbleDelay.restart();
            } else {
                bubbleDelay.ready = false;
                bubbleDelay.stop();
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Timer {
            id: bubbleDelay

            property bool ready: false

            interval: 350
            onTriggered: ready = true
        }

        StyledText {
            id: bubbleText

            anchors.centerIn: parent
            text: bubble.text
            color: Colours.palette.m3inverseOnSurface
            font: Tokens.font.label.medium
        }
    }
}
