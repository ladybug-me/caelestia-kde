pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Live preview pane: a scaled-down screen rectangle showing how windows will be
// arranged under the current Krohnkite layout and gap settings.
Item {
    id: root

    property string layout: "BTree"
    property int windowCount: 4
    property real gapBetween: 8
    property real gapTop: 8
    property real gapBottom: 8
    property real gapLeft: 8
    property real gapRight: 8

    Layout.fillWidth: true
    implicitHeight: Math.round(width * 9 / 16) + headerRow.implicitHeight + 8

    function computeRects(layoutName, n, gapB, gapT, gapBo, gapL, gapR) {
        const sx = screen.width;
        const sy = screen.height;
        if (sx <= 0 || sy <= 0) return [];

        const W = 1.0;
        const H = 1.0;

        const gl = gapL / sx;
        const gr = gapR / sx;
        const gt = gapT / sy;
        const gb = gapBo / sy;
        const gx = gapB / sx;
        const gy = gapB / sy;

        const x0 = gl;
        const y0 = gt;
        const iw = W - gl - gr;
        const ih = H - gt - gb;

        if (n <= 0 || iw <= 0 || ih <= 0) return [];

        const rects = [];

        switch (layoutName) {

        case "Quarter": {
            const cols = Math.ceil(Math.sqrt(n));
            const rows = Math.ceil(n / cols);
            const cw = (iw - gx * (cols - 1)) / cols;
            const ch = (ih - gy * (rows - 1)) / rows;
            for (let i = 0; i < n; i++) {
                const col = i % cols;
                const row = Math.floor(i / cols);
                rects.push({ x: x0 + col * (cw + gx), y: y0 + row * (ch + gy), w: Math.max(0, cw), h: Math.max(0, ch) });
            }
            break;
        }

        case "Columns": {
            const cw = (iw - gx * (n - 1)) / n;
            for (let i = 0; i < n; i++)
                rects.push({ x: x0 + i * (cw + gx), y: y0, w: Math.max(0, cw), h: ih });
            break;
        }

        case "Spread": {
            const rh = (ih - gy * (n - 1)) / n;
            for (let i = 0; i < n; i++)
                rects.push({ x: x0, y: y0 + i * (rh + gy), w: iw, h: Math.max(0, rh) });
            break;
        }

        case "Monocle": {
            for (let i = 0; i < n; i++) {
                const off = i * 0.012;
                rects.push({ x: x0 + off, y: y0 + off,
                              w: Math.max(0, iw - off * 2),
                              h: Math.max(0, ih - off * 2) });
            }
            break;
        }

        case "Floating": {
            const ww = iw * 0.56;
            const wh = ih * 0.56;
            for (let i = 0; i < n; i++) {
                const angle = (i / n) * Math.PI * 2;
                const cx = x0 + iw / 2 - ww / 2 + Math.cos(angle) * iw * 0.16;
                const cy = y0 + ih / 2 - wh / 2 + Math.sin(angle) * ih * 0.16;
                rects.push({ x: cx, y: cy, w: ww, h: wh });
            }
            break;
        }

        case "Stair": {
            const max_off = Math.min(iw, ih) * 0.22;
            const ww = iw - max_off;
            const wh = ih - max_off;
            for (let i = 0; i < n; i++) {
                const off = (i / Math.max(n - 1, 1)) * max_off;
                rects.push({ x: x0 + off, y: y0 + off, w: Math.max(0, ww), h: Math.max(0, wh) });
            }
            break;
        }

        case "Cascade": {
            const step = Math.min(iw, ih) * 0.14;
            const ww = iw * 0.72;
            const wh = ih * 0.72;
            for (let i = 0; i < n; i++)
                rects.push({ x: x0 + i * step, y: y0 + i * step, w: ww, h: wh });
            break;
        }

        case "Stacked": {
            const masterW = iw * 0.55;
            const slaveW = iw - masterW - gx;
            rects.push({ x: x0, y: y0, w: masterW, h: ih });
            const rest = n - 1;
            if (rest > 0) {
                const sh = (ih - gy * (rest - 1)) / rest;
                for (let i = 0; i < rest; i++)
                    rects.push({ x: x0 + masterW + gx, y: y0 + i * (sh + gy), w: Math.max(0, slaveW), h: Math.max(0, sh) });
            }
            break;
        }

        case "ThreeColumn": {
            if (n === 1) { rects.push({ x: x0, y: y0, w: iw, h: ih }); break; }
            const masterW = iw * 0.4;
            const sideW = (iw - masterW - gx * 2) / 2;
            const leftN = Math.ceil((n - 1) / 2);
            const rightN = n - 1 - leftN;
            rects.push({ x: x0 + sideW + gx, y: y0, w: masterW, h: ih });
            if (leftN > 0) {
                const lh = (ih - gy * (leftN - 1)) / leftN;
                for (let i = 0; i < leftN; i++)
                    rects.push({ x: x0, y: y0 + i * (lh + gy), w: Math.max(0, sideW), h: Math.max(0, lh) });
            }
            if (rightN > 0) {
                const rh2 = (ih - gy * (rightN - 1)) / rightN;
                for (let i = 0; i < rightN; i++)
                    rects.push({ x: x0 + sideW + masterW + gx * 2, y: y0 + i * (rh2 + gy), w: Math.max(0, sideW), h: Math.max(0, rh2) });
            }
            break;
        }

        case "Tile": {
            if (n === 1) { rects.push({ x: x0, y: y0, w: iw, h: ih }); break; }
            const masterW2 = iw * 0.55;
            const slaveW2 = iw - masterW2 - gx;
            rects.push({ x: x0, y: y0, w: masterW2, h: ih });
            const rest2 = n - 1;
            const sh2 = (ih - gy * (rest2 - 1)) / rest2;
            for (let i = 0; i < rest2; i++)
                rects.push({ x: x0 + masterW2 + gx, y: y0 + i * (sh2 + gy), w: Math.max(0, slaveW2), h: Math.max(0, sh2) });
            break;
        }

        case "BTree": {
            function btreeSplit(rect, count, vertical) {
                if (count === 1) { rects.push(rect); return; }
                const half = Math.floor(count / 2);
                if (vertical) {
                    const hw = (rect.w - gx) / 2;
                    btreeSplit({ x: rect.x, y: rect.y, w: Math.max(0, hw), h: rect.h }, half, !vertical);
                    btreeSplit({ x: rect.x + hw + gx, y: rect.y, w: Math.max(0, hw), h: rect.h }, count - half, !vertical);
                } else {
                    const hh = (rect.h - gy) / 2;
                    btreeSplit({ x: rect.x, y: rect.y, w: rect.w, h: Math.max(0, hh) }, half, !vertical);
                    btreeSplit({ x: rect.x, y: rect.y + hh + gy, w: rect.w, h: Math.max(0, hh) }, count - half, !vertical);
                }
            }
            btreeSplit({ x: x0, y: y0, w: iw, h: ih }, n, true);
            break;
        }

        case "Spiral": {
            function spiralSplit(rect, count, dir) {
                if (count === 1) { rects.push(rect); return; }
                switch (dir % 4) {
                    case 0: {
                        const hw = (rect.w - gx) * 0.55;
                        rects.push({ x: rect.x, y: rect.y, w: Math.max(0, hw), h: rect.h });
                        spiralSplit({ x: rect.x + hw + gx, y: rect.y, w: Math.max(0, rect.w - hw - gx), h: rect.h }, count - 1, dir + 1);
                        break;
                    }
                    case 1: {
                        const hh = (rect.h - gy) * 0.55;
                        rects.push({ x: rect.x, y: rect.y, w: rect.w, h: Math.max(0, hh) });
                        spiralSplit({ x: rect.x, y: rect.y + hh + gy, w: rect.w, h: Math.max(0, rect.h - hh - gy) }, count - 1, dir + 1);
                        break;
                    }
                    case 2: {
                        const hw2 = (rect.w - gx) * 0.45;
                        rects.push({ x: rect.x + hw2 + gx, y: rect.y, w: Math.max(0, rect.w - hw2 - gx), h: rect.h });
                        spiralSplit({ x: rect.x, y: rect.y, w: Math.max(0, hw2), h: rect.h }, count - 1, dir + 1);
                        break;
                    }
                    case 3: {
                        const hh2 = (rect.h - gy) * 0.45;
                        rects.push({ x: rect.x, y: rect.y + hh2 + gy, w: rect.w, h: Math.max(0, rect.h - hh2 - gy) });
                        spiralSplit({ x: rect.x, y: rect.y, w: rect.w, h: Math.max(0, hh2) }, count - 1, dir + 1);
                        break;
                    }
                }
            }
            spiralSplit({ x: x0, y: y0, w: iw, h: ih }, n, 0);
            break;
        }

        default: {
            const cols2 = Math.ceil(Math.sqrt(n));
            const rows2 = Math.ceil(n / cols2);
            const cw3 = (iw - gx * (cols2 - 1)) / cols2;
            const ch3 = (ih - gy * (rows2 - 1)) / rows2;
            for (let i = 0; i < n; i++) {
                const col = i % cols2;
                const row = Math.floor(i / cols2);
                rects.push({ x: x0 + col * (cw3 + gx), y: y0 + row * (ch3 + gy), w: Math.max(0, cw3), h: Math.max(0, ch3) });
            }
        }
        }

        return rects;
    }

    property var windowRects: []

    function refresh() {
        windowRects = computeRects(
            root.layout, root.windowCount,
            root.gapBetween, root.gapTop, root.gapBottom,
            root.gapLeft, root.gapRight
        );
    }

    onLayoutChanged: Qt.callLater(refresh)
    onWindowCountChanged: Qt.callLater(refresh)
    onGapBetweenChanged: Qt.callLater(refresh)
    onGapTopChanged: Qt.callLater(refresh)
    onGapBottomChanged: Qt.callLater(refresh)
    onGapLeftChanged: Qt.callLater(refresh)
    onGapRightChanged: Qt.callLater(refresh)

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            id: headerRow
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Layout Preview")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            StyledText {
                text: qsTr("Windows:")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                Layout.rightMargin: Tokens.spacing.small
            }

            StyledRect {
                implicitWidth: countLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: countLabel.implicitHeight + Tokens.padding.small
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerHigh

                StyledText {
                    id: countLabel

                    anchors.centerIn: parent
                    text: root.windowCount.toString()
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurface
                }
            }

            IconButton {
                icon: "remove"
                type: IconButton.Text
                onClicked: root.windowCount = Math.max(1, root.windowCount - 1)
            }

            IconButton {
                icon: "add"
                type: IconButton.Text
                onClicked: root.windowCount = Math.min(8, root.windowCount + 1)
            }
        }

        StyledClippingRect {
            id: screen

            Layout.fillWidth: true
            implicitHeight: Math.round(width * 9 / 16)
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainerHigh
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.color: Qt.alpha(Colours.palette.m3outline, 0.35)
                border.width: 1
                z: 10
            }

            onWidthChanged: Qt.callLater(root.refresh)

            onHeightChanged: Qt.callLater(root.refresh)

            Component.onCompleted: Qt.callLater(root.refresh)

            Rectangle {
                x: 0; y: 0; width: screen.width; height: root.gapTop
                color: Qt.alpha(Colours.palette.m3primary, 0.10)

                Behavior on height { Anim { type: Anim.FastSpatial } }
            }
            Rectangle {
                x: 0; y: screen.height - root.gapBottom; width: screen.width; height: root.gapBottom
                color: Qt.alpha(Colours.palette.m3primary, 0.10)

                Behavior on height { Anim { type: Anim.FastSpatial } }
                Behavior on y { Anim { type: Anim.FastSpatial } }
            }
            Rectangle {
                x: 0; y: 0; width: root.gapLeft; height: screen.height
                color: Qt.alpha(Colours.palette.m3primary, 0.10)

                Behavior on width { Anim { type: Anim.FastSpatial } }
            }
            Rectangle {
                x: screen.width - root.gapRight; y: 0; width: root.gapRight; height: screen.height
                color: Qt.alpha(Colours.palette.m3primary, 0.10)

                Behavior on width { Anim { type: Anim.FastSpatial } }
                Behavior on x { Anim { type: Anim.FastSpatial } }
            }

            Repeater {
                id: windowRepeater

                model: root.windowCount

                delegate: StyledRect {
                    id: winRect

                    required property int index

                    property var geo: root.windowRects[index] ?? { x: 0.05, y: 0.05, w: 0.9, h: 0.9 }

                    x: Math.round(geo.x * screen.width)
                    y: Math.round(geo.y * screen.height)
                    width: Math.max(2, Math.round(geo.w * screen.width))
                    height: Math.max(2, Math.round(geo.h * screen.height))
                    radius: Tokens.rounding.extraLarge

                    color: winRect.index === 0
                        ? Qt.alpha(Colours.palette.m3primaryContainer, 0.85)
                        : Qt.alpha(Colours.palette.m3secondaryContainer, 0.80)

                    Behavior on x      { Anim { type: Anim.FastSpatial } }
                    Behavior on y      { Anim { type: Anim.FastSpatial } }
                    Behavior on width  { Anim { type: Anim.FastSpatial } }
                    Behavior on height { Anim { type: Anim.FastSpatial } }
                    Behavior on color  { CAnim {} }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.color: winRect.index === 0
                            ? Qt.alpha(Colours.palette.m3primary, 0.45)
                            : Qt.alpha(Colours.palette.m3outline, 0.25)
                        border.width: 1
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: (winRect.index + 1).toString()
                        font: Tokens.font.label.small
                        color: winRect.index === 0
                            ? Colours.palette.m3onPrimaryContainer
                            : Colours.palette.m3onSecondaryContainer
                        opacity: 0.75
                    }
                }
            }


            //     StyledText {
            //         id: badgeLabel
            //         anchors.centerIn: parent
            //         text: root.layout
            //         font: Tokens.font.label.small
            //         color: Colours.palette.m3onSurface
            //     }
            // }
        }
    }
}
