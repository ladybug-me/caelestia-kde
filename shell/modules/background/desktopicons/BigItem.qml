pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// A desktop item bigger than one cell: a large folder or a widget. Draws the
// card, takes selection, dragging, the context menu and resizing, and loads
// the actual content on top.
Item {
    id: root

    required property var controller
    required property string key

    readonly property bool isGroup: controller.isGroupKey(key)
    readonly property string itemId: controller.nameOf(key)
    readonly property var widget: isGroup ? null : (DesktopLayout.widgets[itemId] ?? null)
    // A widget's own settings. Groups have none, so they read an empty object and
    // every `config.x` below stays a plain lookup instead of a ReferenceError.
    readonly property var config: widget?.config ?? ({})
    readonly property var info: controller.widgetCatalog.infoForGrid(isGroup ? "group" : (widget?.type ?? ""), controller.cols, controller.rows)
    readonly property var span: {
        const raw = controller.displaySpans[key] ?? info.size;
        return {
            w: Math.max(1, Math.min(raw.w, controller.cols)),
            h: Math.max(1, Math.min(raw.h, controller.rows))
        };
    }
    readonly property bool frameless: !isGroup && (info.frameless === true || config.frameless === true)
    // Locked widgets cannot be dragged or resized from the desktop.
    readonly property bool locked: !isGroup && widget?.locked === true
    // Keeps the outline on every widget while the option is on, so that one that
    // is empty (or hidden by its own condition) can still be located. It does not
    // follow the desktop icons toggle: widgets stay on the desktop without them.
    // Edit mode outlines every card for the same reason.
    readonly property bool outlined: !isGroup && (DesktopLayout.widgetOutlines || widgetEditMode)

    property bool selected: false
    property bool focusVisible: false
    property bool dimmed: false
    property bool mergeTarget: false
    property real appear: 0
    // Set while the desktop is in widget edit mode: the content stops taking
    // input and this card's own area is raised over it, so the whole card drags.
    property bool widgetEditMode: false
    readonly property bool hovered: hover.hovered
    // True while any border of the card is dragged.
    readonly property bool resizing: resizeGrips.some(grip => grip.pressed)
    readonly property var resizeGrips: [gripLeft, gripRight, gripTop, gripBottom, gripTopLeft, gripTopRight, gripBottomLeft, gripBottomRight]
    // Thickness of the draggable borders and the size of their corners.
    readonly property int gripEdge: Tokens.padding.small
    readonly property int gripCorner: Tokens.padding.large
    readonly property int gripHandle: Tokens.padding.large * 2
    readonly property alias content: loader.item
    // Every large item carries its name under the card, like an icon label.
    // The label sits in the gap to the next row, so that gap is kept only a little
    // wider than the one between columns; otherwise rows look much further apart.
    readonly property real sideGap: Tokens.padding.extraLarge / 2
    readonly property real topGap: Tokens.padding.small
    readonly property real labelHeight: isGroup ? Tokens.padding.extraLargeIncreased : topGap
    readonly property string label: {
        if (isGroup)
            return DesktopLayout.groups[itemId]?.name ?? "";
        const path = widget?.type === "folder" ? (config.path ?? "").replace(/\/+$/, "") : "";
        return path !== "" ? path.substring(path.lastIndexOf("/") + 1) : info.name;
    }

    signal pressed(var mouse)
    signal clicked(var mouse)
    signal doubleClicked(var mouse)
    signal contextMenuRequested(real x, real y)
    signal dragRequested(real x, real y)

    function setConfig(patch: var): void {
        if (!isGroup)
            DesktopLayout.setWidgetConfig(itemId, patch);
    }

    // Renaming only applies to large folders, through their label.
    function startRename(text: string, selectUntil: int): void {
        if (isGroup)
            title.startRename(text);
    }

    function commitRename(): void {
        title.commitRename();
    }

    function cancelRename(): void {
        title.cancelRename();
    }

    function overIcon(x: real, y: real): bool {
        return true;
    }

    opacity: (dimmed ? 0.4 : 1) * appear
    scale: (0.9 + 0.1 * appear) * (mergeTarget ? 1.02 : 1)
    Component.onCompleted: appear = 1

    Behavior on appear {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on scale {
        Anim {
            type: Anim.FastSpatial
        }
    }

    HoverHandler {
        id: hover
    }

    // Frosted glass: the part of the controller's blurred wallpaper behind
    // the card, clipped to it.
    Loader {
        anchors.fill: card
        active: !root.frameless && !!root.controller.glass

        sourceComponent: MultiEffect {
            source: ShaderEffectSource {
                sourceItem: root.controller.glass
                sourceRect: Qt.rect(root.controller.gridOrigin.x + root.x + card.x, root.controller.gridOrigin.y + root.y + card.y, card.width, card.height)
            }
            maskSource: cardMask
            maskEnabled: true
            autoPaddingEnabled: false
        }
    }

    StyledRect {
        id: cardMask

        anchors.fill: card
        radius: card.radius
        visible: false
        layer.enabled: true
    }

    StyledRect {
        id: card

        anchors.fill: parent
        anchors.leftMargin: root.frameless ? 0 : root.sideGap
        anchors.rightMargin: root.frameless ? 0 : root.sideGap
        anchors.topMargin: root.frameless ? 0 : root.topGap
        anchors.bottomMargin: root.frameless ? 0 : root.labelHeight
        radius: root.frameless ? Tokens.rounding.medium : Tokens.rounding.extraLarge
        color: root.frameless ? "transparent" : (GlobalConfig.appearance.pitchBlack ? Qt.alpha("#000000", 0.7) : Qt.alpha(Colours.palette.m3surfaceContainer, 0.4))
        border.width: root.selected || root.mergeTarget || root.focusVisible ? 2 : (root.frameless ? 0 : 1)
        border.color: root.selected || root.mergeTarget || root.focusVisible ? Qt.darker(Colours.palette.m3primary, 1.45) : Qt.alpha(Colours.palette.m3onSurface, 0.12)

        // Background of the card: selects, opens, drags and resizes the item.
        // Controls inside the content take their own clicks first. In edit mode the
        // content above is disabled and this area is raised over it, so a press
        // anywhere on the card starts a move.
        MouseArea {
            id: bgArea

            property point pressPos
            property bool dragSent: false

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            z: root.widgetEditMode ? 1 : 0
            cursorShape: root.widgetEditMode && !root.locked ? Qt.OpenHandCursor : Qt.ArrowCursor
            onPressed: mouse => {
                pressPos = Qt.point(mouse.x, mouse.y);
                dragSent = false;
                root.pressed({
                    x: mouse.x + card.x,
                    y: mouse.y + card.y,
                    button: mouse.button,
                    modifiers: mouse.modifiers
                });
            }
            onPositionChanged: mouse => {
                if (root.locked || !(pressedButtons & Qt.LeftButton) || dragSent)
                    return;
                const dx = mouse.x - pressPos.x;
                const dy = mouse.y - pressPos.y;
                if (dx * dx + dy * dy >= Qt.styleHints.startDragDistance * Qt.styleHints.startDragDistance) {
                    dragSent = true;
                    root.dragRequested(pressPos.x + card.x, pressPos.y + card.y);
                }
            }
            onClicked: mouse => {
                if (dragSent)
                    return;
                if (mouse.button === Qt.RightButton)
                    root.contextMenuRequested(mouse.x + card.x, mouse.y + card.y);
                else
                    root.clicked(mouse);
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    root.doubleClicked(mouse);
            }
        }

        Loader {
            id: loader

            readonly property string wanted: root.info.source

            function load(): void {
                if (wanted !== "")
                    setSource(Qt.resolvedUrl(wanted), {
                        frame: root,
                        controller: root.controller
                    });
                else
                    source = "";
            }

            anchors.fill: parent
            anchors.margins: root.frameless ? 0 : (root.isGroup ? Tokens.padding.small : Tokens.padding.large)
            asynchronous: true
            // Edit mode owns the card: the widget's controls must not keep hover,
            // focus or a text cursor while it is being moved.
            enabled: !root.widgetEditMode

            onWantedChanged: load()
            Component.onCompleted: load()
        }

        // Edit mode: names the widget and its size, so a card whose content is
        // empty (or hidden by its own condition) can still be told apart.
        StyledRect {
            id: badge

            readonly property int inset: Tokens.padding.small / 2

            visible: root.widgetEditMode && !root.isGroup && card.width > 90 && card.height > 32
            anchors.top: card.top
            anchors.left: card.left
            anchors.margins: inset
            implicitWidth: Math.min(badgeRow.implicitWidth + Tokens.padding.medium, card.width - inset * 2)
            implicitHeight: badgeRow.implicitHeight + Tokens.padding.extraSmall
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.92)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.3)
            z: 2

            RowLayout {
                id: badgeRow

                anchors.centerIn: parent
                width: Math.max(0, parent.implicitWidth - Tokens.padding.medium)
                spacing: Tokens.padding.extraSmall

                MaterialIcon {
                    visible: root.locked
                    text: "lock"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.label
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    text: `${root.span.w} × ${root.span.h}`
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    // Outline for every widget while the outlines option is on: locates widgets
    // that are empty or hidden by their own condition.
    StyledRect {
        id: outline

        anchors.fill: card
        visible: root.outlined && !root.selected && !root.mergeTarget && !root.focusVisible
        color: "transparent"
        radius: card.radius
        border.width: 2
        border.color: Colours.palette.m3primary
    }

    // Centred in the gap down to the next row's card (its top gap included), so
    // names in different scripts line up.
    // Only groups carry a name; widgets show none.
    StyledRect {
        visible: root.isGroup && !root.frameless
        anchors.horizontalCenter: card.horizontalCenter
        anchors.verticalCenter: card.bottom
        anchors.verticalCenterOffset: (root.labelHeight + root.topGap) / 2 - 1
        width: title.width + Tokens.padding.medium * 2
        height: title.height + Tokens.padding.small
        radius: Tokens.rounding.small
        color: root.selected && !title.renaming ? Qt.alpha(Colours.palette.m3primary, 0.24) : "transparent"

        GroupTitle {
            id: title

            anchors.centerIn: parent
            width: Math.min(implicitWidth, card.width)
            desktopStyle: true
            text: root.label
            onRenameRequested: root.controller.startRename(root.key)
            onRenameCommitted: text => {
                root.controller.finishRename(root);
                root.controller.renameGroup(root.itemId, text);
            }
            onRenameCancelled: root.controller.finishRename(root)
        }
    }

    // Every border resizes in whole cells: the four edges grow one axis, the
    // corners both. Dragging the left or top edge keeps the opposite edge in
    // place, so the item's origin cell moves with the drag.
    Grip {
        id: gripLeft

        horizontal: -1
        vertical: 0
        anchors.left: card.left
        anchors.top: card.top
        anchors.bottom: card.bottom
        width: root.gripEdge
    }

    Grip {
        id: gripRight

        horizontal: 1
        vertical: 0
        anchors.right: card.right
        anchors.top: card.top
        anchors.bottom: card.bottom
        width: root.gripEdge
    }

    Grip {
        id: gripTop

        horizontal: 0
        vertical: -1
        anchors.top: card.top
        anchors.left: card.left
        anchors.right: card.right
        anchors.leftMargin: root.gripEdge
        anchors.rightMargin: root.gripEdge
        height: root.gripEdge
    }

    Grip {
        id: gripBottom

        horizontal: 0
        vertical: 1
        anchors.bottom: card.bottom
        anchors.left: card.left
        anchors.right: card.right
        anchors.leftMargin: root.gripEdge
        anchors.rightMargin: root.gripEdge
        height: root.gripEdge
    }

    Grip {
        id: gripTopLeft

        horizontal: -1
        vertical: -1
        anchors.left: card.left
        anchors.top: card.top
        width: root.gripCorner
        height: root.gripCorner
    }

    Grip {
        id: gripTopRight

        horizontal: 1
        vertical: -1
        anchors.right: card.right
        anchors.top: card.top
        width: root.gripCorner
        height: root.gripCorner
    }

    Grip {
        id: gripBottomLeft

        horizontal: -1
        vertical: 1
        anchors.left: card.left
        anchors.bottom: card.bottom
        width: root.gripCorner
        height: root.gripCorner
    }

    // The one corner that shows a handle, so the cards keep their grip.
    Grip {
        id: gripBottomRight

        horizontal: 1
        vertical: 1
        anchors.right: card.right
        anchors.bottom: card.bottom
        width: root.gripHandle
        height: root.gripHandle

        MaterialIcon {
            anchors.centerIn: parent
            text: "drag_handle"
            rotation: -45
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    component Grip: MouseArea {
        id: grip

        // Which way the grip grows the item: -1 towards the left/top edge, 1
        // towards the right/bottom edge, 0 for the axis it leaves alone.
        required property int horizontal
        required property int vertical

        property point pressPoint
        property var startSpan
        property var startPos

        // The span and origin cell the pointer at p, in controller coordinates,
        // would give the item.
        function resized(p: point): var {
            const ctrl = root.controller;
            const maxW = Math.max(1, Math.min(Math.max(root.info.max.w, startSpan.w), ctrl.cols));
            const maxH = Math.max(1, Math.min(Math.max(root.info.max.h, startSpan.h), ctrl.rows));
            const minW = Math.max(1, Math.min(root.info.min.w, maxW));
            const minH = Math.max(1, Math.min(root.info.min.h, maxH));
            // Edges that stay put while the drag moves the opposite one.
            const rightEdge = startPos.col + startSpan.w;
            const bottomEdge = startPos.row + startSpan.h;
            let w = startSpan.w;
            let h = startSpan.h;
            let col = startPos.col;
            let row = startPos.row;
            if (horizontal !== 0) {
                const cells = Math.round((p.x - pressPoint.x) / ctrl.cellWidth);
                if (horizontal > 0)
                    w = Math.max(minW, Math.min(maxW, Math.min(ctrl.cols - startPos.col, startSpan.w + cells)));
                else {
                    w = Math.max(minW, Math.min(maxW, Math.min(rightEdge, startSpan.w - cells)));
                    col = rightEdge - w;
                }
            }
            if (vertical !== 0) {
                const cells = Math.round((p.y - pressPoint.y) / ctrl.cellHeight);
                if (vertical > 0)
                    h = Math.max(minH, Math.min(maxH, Math.min(ctrl.rows - startPos.row, startSpan.h + cells)));
                else {
                    h = Math.max(minH, Math.min(maxH, Math.min(bottomEdge, startSpan.h - cells)));
                    row = bottomEdge - h;
                }
            }
            return {
                w: w,
                h: h,
                col: col,
                row: row
            };
        }

        z: 2
        hoverEnabled: true
        preventStealing: true
        enabled: !root.locked
        visible: !root.locked && opacity > 0
        // Edit mode keeps every border grabbable without hovering the card first.
        opacity: root.locked ? 0 : (root.hovered || root.selected || root.widgetEditMode || pressed ? 1 : 0)
        cursorShape: {
            if (root.locked)
                return Qt.ArrowCursor;
            if (horizontal === 0)
                return Qt.SizeVerCursor;
            if (vertical === 0)
                return Qt.SizeHorCursor;
            return horizontal === vertical ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
        }

        onPressed: mouse => {
            pressPoint = mapToItem(root.controller, mouse.x, mouse.y);
            startSpan = root.span;
            startPos = root.controller.displayPositions[root.key] ?? { col: 0, row: 0 };
            const p = mapToItem(root, mouse.x, mouse.y);
            root.pressed({
                x: p.x,
                y: p.y,
                button: Qt.LeftButton,
                modifiers: Qt.NoModifier
            });
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const s = resized(mapToItem(root.controller, mouse.x, mouse.y));
            root.controller.previewResize(root.key, s.w, s.h, {
                col: s.col,
                row: s.row
            });
        }
        onReleased: {
            const s = root.controller.displaySpans[root.key] ?? startSpan;
            const pos = root.controller.displayPositions[root.key] ?? startPos;
            // A click that never moved the border must not rewrite the layout.
            if (s.w === startSpan.w && s.h === startSpan.h && pos.col === startPos.col && pos.row === startPos.row) {
                root.controller.endResizePreview();
                return;
            }
            root.controller.resizeItem(root.key, s.w, s.h, {
                col: pos.col,
                row: pos.row
            });
        }
        onCanceled: root.controller.endResizePreview()

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }
    }
}
