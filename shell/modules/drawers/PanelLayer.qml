pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.utils
import qs.modules.bar as Bar

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property Panels panels
    required property Bar.BarWrapper primaryBar
    required property bool hasFullscreen
    required property bool hidden
    required property real borderThickness
    required property var blobGroup

    readonly property int thickness: root.primaryBar.contentWidth
    readonly property bool panelsVisible: root.panelRects.length > 0 && !root.hidden
    readonly property alias edges: edgesObject
    readonly property alias reservations: reservationsObject
    readonly property alias frameEdges: frameEdgesObject
    readonly property var screenPanels: {
        const panels = GlobalConfig.bar.panels?.values ?? [];
        const shown = [];

        for (let i = 0; i < panels.length; ++i) {
            const panel = panels[i];

            if (panel.enabled === false)
                continue;
            if ((panel.screens ?? []).length > 0 && !Strings.testRegexList(panel.screens, screen.name))
                continue;
            shown.push({
                panel,
                index: i
            });
        }

        return shown;
    }
    readonly property int panelInset: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
    readonly property var panelRects: {
        const rects = [];

        for (const entry of root.screenPanels) {
            const panel = entry.panel;
            const edge = panel.position ?? "top";
            const horizontal = edge === "top" || edge === "bottom";
            const total = horizontal ? root.width : root.height;
            const usable = Math.max(0, total - root.panelInset * 2);
            const percent = Math.max(0, Math.min(100, panel.lengthPercent ?? 100));
            const full = percent >= 100;
            const length = full ? usable : Math.round(usable * percent / 100);

            if (length <= 0)
                continue;

            const align = panel.align ?? "center";
            const along = full || align === "center" ? Math.round((total - length) / 2) : (align === "end" ? total - root.panelInset - length : root.panelInset);
            const thickness = root.thickness;

            rects.push({
                panel,
                panelIndex: entry.index,
                edge,
                horizontal,
                full,
                x: horizontal ? along : edge === "left" ? root.panelInset : root.width - root.panelInset - thickness,
                y: horizontal ? (edge === "top" ? root.panelInset : root.height - root.panelInset - thickness) : along,
                width: horizontal ? length : thickness,
                height: horizontal ? thickness : length
            });
        }

        return rects;
    }
    readonly property var bands: root.bandsOf(!GlobalConfig.appearance.islands)
    readonly property var strips: {
        const list = [];

        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band && !band.full)
                list.push(band.strip);
        }

        return list;
    }
    function bandAt(x: real, y: real): var {
        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band && band.contains(band.mapFromItem(null, x, y)))
                return band;
        }

        return null;
    }
    function resetHover(): void {
        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band)
                band.resetHover();
        }
    }
    function thicknessOn(side: string): real {
        let thickness = 0;

        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band && band.full && band.edge === side)
                thickness = Math.max(thickness, band.thickness);
        }

        return thickness;
    }
    function takesSpaceOn(side: string): bool {
        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band && band.edge === side && band.takesSpace)
                return true;
        }

        return false;
    }
    function bandsOf(partialOnly = false): var {
        const bands = [];

        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band && (!partialOnly || !band.full))
                bands.push(band);
        }

        return bands;
    }
    function updateReveal(x: real, y: real, pressed: bool, dragStart: point, dragX: real, dragY: real): void {
        if (!root.panelsVisible) return;

        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (!band || band.persistent) continue;

            if (band.revealOnHover) {
                if (band.inStrip(x, y))
                    band.hovered = true;

                continue;
            }

            if (pressed && band.inStrip(dragStart.x, dragStart.y)) {
                const inward = band.horizontal ? (band.edge === "top" ? dragY : -dragY) : (band.edge === "left" ? dragX : -dragX);

                if (inward > Config.bar.dragThreshold)
                    band.pulled = true;
                else if (inward < -Config.bar.dragThreshold)
                    band.pulled = false;
            }
        }
    }
    function clearReveal(): void {
        for (let i = 0; i < panelRepeater.count; i++) {
            const band = panelRepeater.itemAt(i);

            if (band)
                band.hovered = false;
        }
    }

    anchors.fill: parent
    visible: root.panelsVisible

    Repeater {
        model: root.bands

        delegate: BlobRect {
            required property var modelData

            group: root.panelsVisible && !modelData.islandAway ? root.blobGroup : null
            visible: root.panelsVisible && !modelData.islandAway
            x: modelData.x
            y: modelData.y
            implicitWidth: modelData.width
            implicitHeight: modelData.height
            radius: Tokens.rounding.extraLarge
            deformScale: (GlobalConfig.appearance.blurMask || !GlobalConfig.appearance.transparency.enabled) ? ((0.1 * Config.appearance.deformScale) / 10000) : 0
            Config.screen: root.screen.name
        }
    }
    Repeater {
        id: panelRepeater

        model: root.panelRects

        delegate: Item {
            id: band

            required property var modelData

            readonly property string edge: modelData.edge
            readonly property bool horizontal: modelData.horizontal
            readonly property bool full: modelData.full
            readonly property bool persistent: modelData.panel.persistent !== false
            readonly property bool revealOnHover: modelData.panel.showOnHover !== false
            property bool hovered
            property bool pulled
            readonly property bool revealed: band.persistent || band.hovered || band.pulled
            readonly property real hiddenThickness: Config.border.thickness
            readonly property real thickness: band.horizontal ? band.height : band.width
            readonly property bool islandAway: !band.revealed && band.thickness <= band.hiddenThickness + 0.5
            readonly property real triggerThickness: Math.max(Config.border.minThickness, band.thickness)
            readonly property bool takesSpace: band.persistent || band.pulled
            readonly property var revealedRect: ({
                x: modelData.x,
                y: modelData.y,
                width: modelData.width,
                height: modelData.height
            })
            readonly property var restingRect: band.horizontal ? ({
                x: modelData.x,
                y: band.edge === "top" ? 0 : root.height - Config.border.thickness,
                width: modelData.width,
                height: Config.border.thickness
            }) : ({
                x: band.edge === "left" ? 0 : root.width - Config.border.thickness,
                y: modelData.y,
                width: Config.border.thickness,
                height: modelData.height
            })

            readonly property real popoutInset: {
                const host = band.edge === "top" ? panels.topMargin : band.edge === "bottom" ? panels.bottomMargin : band.edge === "left" ? panels.leftMargin : panels.rightMargin;
                const inner = band.horizontal ? (band.edge === "top" ? band.y + band.height : root.height - band.y) : (band.edge === "left" ? band.x + band.width : root.width - band.x);

                return Math.max(0, inner - host);
            }
            readonly property var strip: stripRegion

            function inStrip(x: real, y: real): bool {
                const along = band.horizontal ? x >= band.x && x <= band.x + band.width : y >= band.y && y <= band.y + band.height;

                if (!along) return false;

                return band.horizontal ? (band.edge === "top" ? y <= band.triggerThickness : y >= root.height - band.triggerThickness) : (band.edge === "left" ? x <= band.triggerThickness : x >= root.width - band.triggerThickness);
            }

            function setOrigin(): void {
                panels.popouts.setOrigin(band.edge, band.popoutInset, band.modelData.panelIndex);
            }
            function checkPopout(x: real, y: real): void {
                bandBar.checkPopout(band.horizontal ? x - band.x : y - band.y);
            }
            function resetHover(): void {
                bandBar.resetHover();
            }
            function handleWheel(x: real, y: real, angleDelta: point): void {
                bandBar.handleWheel(band.horizontal ? x - band.x : y - band.y, angleDelta);
            }

            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height

            clip: true
            visible: band.horizontal ? band.height > Config.border.thickness : band.width > Config.border.thickness

            states: State {
                name: "hidden"
                when: !band.revealed

                PropertyChanges {
                    target: band

                    x: band.horizontal ? band.modelData.x : (band.edge === "left" ? 0 : root.width - band.hiddenThickness)
                    y: band.horizontal ? (band.edge === "top" ? 0 : root.height - band.hiddenThickness) : band.modelData.y
                    width: band.horizontal ? band.modelData.width : band.hiddenThickness
                    height: band.horizontal ? band.hiddenThickness : band.modelData.height

                    opacity: 0
                }
            }
            transitions: [
                Transition {
                    from: ""
                    to: "hidden"

                    Anim {
                        target: band
                        property: band.horizontal ? "height" : "width"
                        type: Anim.Emphasized
                    }
                    Anim {
                        target: band
                        property: band.horizontal ? "y" : "x"
                        type: Anim.Emphasized
                    }
                    Anim {
                        target: band
                        property: "opacity"
                        type: Anim.Emphasized
                    }
                },
                Transition {
                    from: "hidden"
                    to: ""

                    Anim {
                        target: band
                        property: band.horizontal ? "height" : "width"
                        type: Anim.DefaultSpatial
                    }
                    Anim {
                        target: band
                        property: band.horizontal ? "y" : "x"
                        type: Anim.DefaultSpatial
                    }
                    Anim {
                        target: band
                        property: "opacity"
                        type: Anim.DefaultSpatial
                    }
                }
            ]

            Region {
                id: stripRegion

                x: band.revealed ? band.revealedRect.x : band.restingRect.x
                y: band.revealed ? band.revealedRect.y : band.restingRect.y
                width: band.revealed ? band.revealedRect.width : band.restingRect.width
                height: band.revealed ? band.revealedRect.height : band.restingRect.height
            }
            Bar.Bar {
                id: bandBar

                anchors.fill: parent
                anchors.topMargin: band.horizontal ? 0 : root.primaryBar.padding
                anchors.bottomMargin: band.horizontal ? 0 : root.primaryBar.padding
                anchors.leftMargin: band.horizontal ? root.primaryBar.padding : 0
                anchors.rightMargin: band.horizontal ? root.primaryBar.padding : 0

                position: band.edge
                panelIndex: band.modelData.panelIndex
                panelInset: band.popoutInset
                entries: band.modelData.panel.entries
                screen: root.screen
                visibilities: root.visibilities
                popouts: panels.popouts
                fullscreen: root.hasFullscreen
            }
        }
    }

    FrameEdges {
        id: edgesObject

        left: root.hidden ? 0 : root.thicknessOn("left")
        right: root.hidden ? 0 : root.thicknessOn("right")
        top: root.hidden ? 0 : root.thicknessOn("top")
        bottom: root.hidden ? 0 : root.thicknessOn("bottom")
    }
    FrameEdges {
        id: frameEdgesObject

        left: Math.max(root.primaryBar.position === "left" ? root.thickness : 0, root.borderThickness, root.edges.left)
        right: Math.max(root.primaryBar.position === "right" ? root.thickness : 0, root.borderThickness, root.edges.right)
        top: Math.max(root.primaryBar.position === "top" ? root.thickness : 0, root.borderThickness, root.edges.top)
        bottom: Math.max(root.primaryBar.position === "bottom" ? root.thickness : 0, root.borderThickness, root.edges.bottom)
    }
    FrameEdges {
        id: reservationsObject

        left: root.takesSpaceOn("left") ? root.thickness : 0
        right: root.takesSpaceOn("right") ? root.thickness : 0
        top: root.takesSpaceOn("top") ? root.thickness : 0
        bottom: root.takesSpaceOn("bottom") ? root.thickness : 0
    }
}
