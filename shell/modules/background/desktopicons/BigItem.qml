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
    readonly property var config: widget?.config ?? ({})
    readonly property var info: controller.widgetCatalog.info(isGroup ? "group" : (widget?.type ?? ""))
    readonly property var span: controller.displaySpans[key] ?? info.size

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
    readonly property real labelHeight: Tokens.padding.extraLargeIncreased
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

    // Frosted glass: the wallpaper behind the card, blurred and clipped to it.
    Loader {
        anchors.fill: card
        active: !!root.controller.wallpaper && !GameMode.enabled
        asynchronous: true

        sourceComponent: MultiEffect {
            source: ShaderEffectSource {
                sourceItem: root.controller.wallpaper
                sourceRect: Qt.rect(root.controller.gridOrigin.x + root.x + card.x, root.controller.gridOrigin.y + root.y + card.y, card.width, card.height)
            }
            maskSource: cardMask
            maskEnabled: true
            blurEnabled: true
            blur: 1
            blurMax: 48
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
        anchors.leftMargin: root.sideGap
        anchors.rightMargin: root.sideGap
        anchors.topMargin: root.topGap
        anchors.bottomMargin: root.labelHeight
        radius: Tokens.rounding.extraLarge
        color: GlobalConfig.appearance.pitchBlack ? Qt.alpha("#000000", 0.7) : Qt.alpha(Colours.palette.m3surfaceContainer, 0.4)
        border.width: root.selected || root.mergeTarget || root.focusVisible ? 2 : 1
        border.color: root.selected || root.mergeTarget || root.focusVisible ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.12)

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
                if (!(pressedButtons & Qt.LeftButton) || dragSent)
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
            anchors.margins: root.isGroup ? Tokens.padding.small : Tokens.padding.large
            asynchronous: true

            onWantedChanged: load()
            Component.onCompleted: load()
        }
    }

    // Centred in the gap down to the next row's card (its top gap included), so
    // names in different scripts line up.
    StyledRect {
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
        cursorShape: Qt.SizeFDiagCursor
        visible: opacity > 0
        opacity: root.hovered || root.selected || pressed ? 1 : 0
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
            const w = Math.max(root.info.min.w, Math.min(root.info.max.w, Math.round(startSpan.w + (p.x - origin.x) / root.controller.cellWidth)));
            const h = Math.max(root.info.min.h, Math.min(root.info.max.h, Math.round(startSpan.h + (p.y - origin.y) / root.controller.cellHeight)));
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
