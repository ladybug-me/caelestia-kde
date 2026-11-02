pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.drawers

MouseArea {
    id: root

    enum Side {
        Top,
        Bottom,
        Left,
        Right
    }

    required property Item attachTo
    property bool autoFlipY: true
    readonly property real _menuH: menu && menu.implicitHeight > 0 ? menu.implicitHeight : 200
    readonly property bool flippedY: {
        if (!autoFlipY || !attachTo || !parent)
            return false;
        watcher.transform;
        try {
            const pt = attachTo.mapToItem(parent, 0, attachTo.height);
            if (!pt)
                return false;
            const spaceBelow = parent.height - pt.y;
            const ptTop = attachTo.mapToItem(parent, 0, 0);
            const spaceAbove = ptTop ? ptTop.y : 0;
            return (spaceBelow < _menuH + Tokens.spacing.small + Tokens.padding.small) && (spaceAbove > spaceBelow);
        } catch (e) {
            return false;
        }
    }

    property int attachSideX: Menu.Right
    property int attachSideY: autoFlipY && flippedY ? Menu.Top : Menu.Bottom
    property int thisSideX: Menu.Right
    property int thisSideY: autoFlipY && flippedY ? Menu.Bottom : Menu.Top
    property real marginX
    property real marginY

    property list<MenuItem> items
    property var dynamicModel: items
    property MenuItem active: dynamicModel[0] ?? null
    property bool expanded
    property bool rightClickReposition: false
    property real maxHeight: 320
    readonly property alias backgroundItem: menu
    readonly property alias submenuPanel: submenu
    property bool transparentBackground: false
    // Unfold sideways from the anchor with a short, non-overshooting curve
    // instead of dropping down.
    property bool revealHorizontal: false
    property var submenuRow: null
    property var submenuItems: []
    property bool submenuOpen: false
    readonly property int firstVisibleIndex: {
        const model = dynamicModel ?? [];
        for (let i = 0; i < model.length; i++)
            if (model[i]?.visible)
                return i;
        return -1;
    }
    readonly property int lastVisibleIndex: {
        const model = dynamicModel ?? [];
        for (let i = model.length - 1; i >= 0; i--)
            if (model[i]?.visible)
                return i;
        return -1;
    }
    readonly property int submenuFirstVisibleIndex: {
        const model = submenuItems ?? [];
        for (let i = 0; i < model.length; i++)
            if (model[i]?.visible)
                return i;
        return -1;
    }
    readonly property int submenuLastVisibleIndex: {
        const model = submenuItems ?? [];
        for (let i = model.length - 1; i >= 0; i--)
            if (model[i]?.visible)
                return i;
        return -1;
    }

    signal itemSelected(item: MenuItem)
    signal rightClickedAt(real x, real y)

    // Plays the opening animation again, e.g. after the menu moved while open.
    function replayReveal(): void {
        if (!revealHorizontal || !expanded)
            return;
        revealOut.stop();
        revealIn.stop();
        menu.hScale = 0;
        revealIn.start();
    }

    function openSubmenu(row: Item, entries: var): void {
        closeTimer.stop();
        submenuRow = row;
        submenuItems = entries ?? [];
        submenuOpen = true;
        Qt.callLater(root.positionSubmenu);
    }

    function positionSubmenu(): void {
        const row = submenuRow;
        if (!row || !submenu)
            return;
        const panelRight = menu.x + menu.implicitWidth;
        const overlap = Tokens.padding.extraSmall / 2;
        submenu.opensRight = panelRight + submenu.implicitWidth <= root.width;
        submenu.x = submenu.opensRight ? panelRight - overlap : menu.x - submenu.implicitWidth + overlap;
        const rowTop = row.mapToItem(root, 0, 0).y;
        const rowBottom = rowTop + row.height;
        const panelBottom = menu.y + menu.implicitHeight;
        submenu.flushTop = rowTop - menu.y <= Tokens.padding.extraSmall;
        submenu.flushBottom = !submenu.flushTop && panelBottom - rowBottom <= Tokens.padding.extraSmall;
        if (submenu.flushTop)
            submenu.y = menu.y;
        else if (submenu.flushBottom)
            submenu.y = panelBottom - submenu.implicitHeight;
        else
            submenu.y = rowTop;
    }

    function closeSubmenu(): void {
        submenuOpen = false;
    }

    function close(): void {
        if (!expanded)
            return;
        if (closeTimer.running)
            return;
        if (submenuOpen) {
            closeSubmenu();
            closeTimer.restart();
            return;
        }
        closeTimer.stop();
        expanded = false;
    }

    onExpandedChanged: {
        if (expanded) {
            closeTimer.stop();
        } else {
            submenuRow = null;
            submenuItems = [];
        }
        if (!revealHorizontal)
            return;
        revealIn.stop();
        revealOut.stop();
        if (expanded)
            revealIn.start();
        else
            revealOut.start();
    }

    parent: {
        let node = root.attachTo;
        let interactionsNode = null;

        while (node && node.parent) {
            if (node.utilitiesShortcutActive !== undefined) {
                interactionsNode = node;
            }
            node = node.parent;
        }

        if (interactionsNode) {
            return interactionsNode;
        }

        return node || root.parent;
    }
    anchors.fill: parent

    enabled: expanded
    acceptedButtons: rightClickReposition ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
    onClicked: mouse => {
        if (rightClickReposition && mouse.button === Qt.RightButton) {
            rightClickedAt(mouse.x, mouse.y);
            return;
        }
        root.close();
    }

    opacity: expanded ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: root.revealHorizontal ? Anim.FastEffects : Anim.DefaultEffects
        }
    }

    Timer {
        id: closeTimer

        interval: Tokens.anim.durations.small
        onTriggered: root.expanded = false
    }

    NumberAnimation {
        id: revealIn

        target: menu
        property: "hScale"
        to: 1
        duration: Tokens.anim.durations.small
        easing: Tokens.anim.emphasizedDecel
    }

    NumberAnimation {
        id: revealOut

        target: menu
        property: "hScale"
        to: 0
        duration: Math.round(Tokens.anim.durations.small * 0.75)
        easing: Tokens.anim.emphasizedAccel
    }

    TransformWatcher {
        id: watcher

        a: root.parent
        b: root.attachTo
    }

    Elevation {
        id: menu

        property string vAnchor: "none"
        property string hAnchor: "none"
        property real offsetScale: 1 - animScale
        property real vScale: root.expanded ? 1 : 0.0
        property real hScale: 0
        readonly property real animScale: root.revealHorizontal ? hScale : vScale

        x: {
            watcher.transform;
            const item = root.attachTo;
            if (!item || !root.parent)
                return 0;
            let off = root.attachSideX === Menu.Left ? 0 : item.width;
            if (root.thisSideX === Menu.Right)
                off -= width;
            const pt = item.mapToItem(root.parent, off, 0);
            return (pt ? pt.x : 0) + root.marginX;
        }
        y: {
            watcher.transform;
            const item = root.attachTo;
            if (!item || !root.parent)
                return 0;
            let off = root.attachSideY === Menu.Top ? 0 : item.height;
            if (root.thisSideY === Menu.Bottom)
                off -= height;
            const pt = item.mapToItem(root.parent, 0, off);
            return (pt ? pt.y : 0) + root.marginY;
        }

        radius: Tokens.rounding.large
        level: root.transparentBackground ? 0 : 2
        implicitWidth: Math.max(200, column.implicitWidth + Tokens.padding.extraSmall * 2)
        implicitHeight: Math.min(root.maxHeight, column.implicitHeight + Tokens.padding.extraSmall * 2)
        width: root.revealHorizontal ? implicitWidth * animScale : implicitWidth
        height: root.revealHorizontal ? implicitHeight : implicitHeight * animScale
        clip: root.revealHorizontal

        Behavior on vScale {
            enabled: !root.revealHorizontal

            Anim {}
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onWheel: e => e.accepted = true
            onClicked: {}
        }

        StyledRect {
            // Sideways, the content stays pinned to the edge the menu grows
            // from and trails it by a few pixels while the panel unfolds.
            x: {
                if (!root.revealHorizontal)
                    return 0;
                const trail = (1 - menu.animScale) * Tokens.padding.extraLarge;
                return root.thisSideX === Menu.Right ? menu.width - menu.implicitWidth + trail : -trail;
            }
            y: root.thisSideY === Menu.Bottom ? menu.height - menu.implicitHeight : 0
            width: menu.implicitWidth
            height: menu.implicitHeight
            opacity: root.revealHorizontal ? Math.min(1, menu.animScale * 1.5) : 1

            transform: Scale {
                yScale: root.revealHorizontal ? 1 : menu.animScale
                origin.y: root.thisSideY === Menu.Bottom ? menu.implicitHeight : 0
            }

            radius: parent.radius
            color: root.transparentBackground
                ? Qt.alpha(Colours.palette.m3surfaceContainerLow, 0)
                : (GlobalConfig.appearance.pitchBlack
                    ? "#000000"
                    : Colours.palette.m3surfaceContainerLow)

            Flickable {
                id: flickable

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                interactive: contentHeight > height

                ScrollBar.vertical: StyledScrollBar {
                    flickable: flickable
                }

                ColumnLayout {
                    id: column

                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.dynamicModel
                        delegate: rowComp
                    }
                }
            }
        }
    }

    Elevation {
        id: submenu

        property bool opensRight: true
        property real hScale: root.submenuOpen ? 1 : 0
        property bool flushTop: false
        property bool flushBottom: false
        property string vAnchor: "none"
        property string hAnchor: opensRight ? "left" : "right"

        /* Same stacking and backdrop as the menu itself: over it, and drawn by
           whoever paints the menu background when that one is transparent. */
        z: root.z + 1
        radius: Tokens.rounding.large
        level: root.transparentBackground ? 0 : 2
        implicitWidth: Math.max(200, submenuColumn.implicitWidth + Tokens.padding.extraSmall * 2)
        implicitHeight: Math.min(root.maxHeight, submenuColumn.implicitHeight + Tokens.padding.extraSmall * 2)
        width: implicitWidth * hScale
        height: implicitHeight
        clip: true
        visible: hScale > 0.01

        Connections {
            function onXChanged(): void {
                root.positionSubmenu();
            }

            function onYChanged(): void {
                root.positionSubmenu();
            }

            function onImplicitWidthChanged(): void {
                root.positionSubmenu();
            }

            function onImplicitHeightChanged(): void {
                root.positionSubmenu();
            }

            target: menu
        }

        Connections {
            function onImplicitWidthChanged(): void {
                root.positionSubmenu();
            }

            function onImplicitHeightChanged(): void {
                root.positionSubmenu();
            }

            target: submenu
        }

        Behavior on hScale {
            NumberAnimation {
                duration: Tokens.anim.durations.small
                easing: Tokens.anim.emphasizedDecel
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onWheel: e => e.accepted = true
            onClicked: {}
        }

        StyledRect {
            x: submenu.opensRight ? 0 : submenu.width - submenu.implicitWidth
            width: submenu.implicitWidth
            height: submenu.implicitHeight
            opacity: Math.min(1, submenu.hScale * 1.5)

            radius: parent.radius
            color: root.transparentBackground
                ? Qt.alpha(Colours.palette.m3surfaceContainerLow, 0)
                : (GlobalConfig.appearance.pitchBlack
                    ? "#000000"
                    : Colours.palette.m3surfaceContainerLow)

            Flickable {
                id: submenuFlickable

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                contentWidth: width
                contentHeight: submenuColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                interactive: contentHeight > height

                ScrollBar.vertical: StyledScrollBar {
                    flickable: submenuFlickable
                }

                ColumnLayout {
                    id: submenuColumn

                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.submenuItems
                        delegate: rowComp
                    }
                }
            }
        }
    }

    Component {
        id: rowComp

        StyledRect {
            id: item

            required property int index
            required property MenuItem modelData
            readonly property bool inSubmenu: parent === submenuColumn
            // The entries are this module's MenuItem, which qmllint resolves to
            // qmllint disable missing-property
            readonly property var entries: modelData?.submenu ?? []
            // qmllint enable missing-property
            readonly property bool hasSubmenu: entries.length > 0
            readonly property bool active: modelData === root?.active || root?.submenuRow === item
            readonly property int firstIndex: inSubmenu ? root.submenuFirstVisibleIndex : root.firstVisibleIndex
            readonly property int lastIndex: inSubmenu ? root.submenuLastVisibleIndex : root.lastVisibleIndex

            visible: item.modelData ? item.modelData.visible : false

            Layout.fillWidth: true
            implicitWidth: menuOptionRow.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: !visible ? 0 : menuOptionRow.implicitHeight + Tokens.padding.medium * 2

            radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
            topLeftRadius: index === firstIndex ? Tokens.rounding.medium : radius
            topRightRadius: index === firstIndex ? Tokens.rounding.medium : radius
            bottomLeftRadius: index === lastIndex ? Tokens.rounding.medium : radius
            bottomRightRadius: index === lastIndex ? Tokens.rounding.medium : radius

            color: "transparent"

            Behavior on radius {
                Anim {}
            }

            StateLayer {
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius

                color: Colours.palette.m3onSurface
                disabled: !root.expanded
                onContainsMouseChanged: {
                    if (!containsMouse || item.inSubmenu)
                        return;
                    if (item.hasSubmenu)
                        root.openSubmenu(item, item.entries);
                    else
                        root.closeSubmenu();
                }
                onClicked: {
                    root.itemSelected(item.modelData);
                    if (item.hasSubmenu) {
                        root.openSubmenu(item, item.entries);
                        return;
                    }
                    root.active = item.modelData;
                    item.modelData.clicked();
                    root.close();
                }
            }

            RowLayout {
                id: menuOptionRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: item.modelData?.icon ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    text: item.modelData?.text ?? ""
                    color: Colours.palette.m3onSurface
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: Qt.AlignVCenter
                    active: item.modelData?.trailingIcon.length > 0 || item.hasSubmenu
                    visible: active

                    sourceComponent: MaterialIcon {
                        text: item.hasSubmenu ? "chevron_right" : item.modelData.trailingIcon
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
