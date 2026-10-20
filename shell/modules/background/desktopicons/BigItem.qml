pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
    readonly property bool outlineAlways: !isGroup && DesktopLayout.widgetOutlines

    property bool selected: false
    property bool focusVisible: false
    property bool dimmed: false
    property bool mergeTarget: false
    property real appear: 0
    readonly property bool hovered: hover.hovered
    readonly property bool resizing: grip.pressed
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
        // Controls inside the content take their own clicks first.
        MouseArea {
            id: bgArea

            property point pressPos
            property bool dragSent: false

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
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

            onWantedChanged: load()
            Component.onCompleted: load()
        }
    }

    // Outline for every widget while the outlines option is on: locates widgets
    // that are empty or hidden by their own condition.
    StyledRect {
        id: outline

        anchors.fill: card
        visible: root.outlineAlways && !root.selected && !root.mergeTarget && !root.focusVisible
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

    // Drag the corner to resize in whole cells.
    MouseArea {
        id: grip

        property point origin
        property var startSpan

        anchors.right: card.right
        anchors.bottom: card.bottom
        z: 2
        width: Tokens.padding.large * 2
        height: width
        hoverEnabled: true
        cursorShape: root.locked ? Qt.ArrowCursor : Qt.SizeFDiagCursor
        enabled: !root.locked
        visible: !root.locked && opacity > 0
        opacity: root.locked ? 0 : (root.hovered || root.selected || pressed ? 1 : 0)
        preventStealing: true
        onPressed: mouse => {
            origin = mapToItem(root.controller, mouse.x, mouse.y);
            startSpan = root.span;
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
            const p = mapToItem(root.controller, mouse.x, mouse.y);
            const maxW = Math.max(1, Math.min(root.info.max.w, root.controller.cols));
            const maxH = Math.max(1, Math.min(root.info.max.h, root.controller.rows));
            const minW = Math.max(1, Math.min(root.info.min.w, maxW));
            const minH = Math.max(1, Math.min(root.info.min.h, maxH));
            const w = Math.max(minW, Math.min(maxW, Math.round(startSpan.w + (p.x - origin.x) / root.controller.cellWidth)));
            const h = Math.max(minH, Math.min(maxH, Math.round(startSpan.h + (p.y - origin.y) / root.controller.cellHeight)));
            root.controller.previewResize(root.key, w, h);
        }
        onReleased: {
            const s = root.controller.displaySpans[root.key] ?? startSpan;
            root.controller.resizeItem(root.key, s.w, s.h);
        }
        onCanceled: root.controller.endResizePreview()

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: "drag_handle"
            rotation: -45
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
