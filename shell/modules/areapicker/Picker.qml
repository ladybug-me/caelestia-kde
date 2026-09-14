pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import qs.components
import qs.components.effects
import qs.services
import qs.utils

MouseArea {
    id: root

    required property LazyLoader loader
    required property ShellScreen screen

    property bool onClient

    property real realBorderWidth: onClient ? (Kwin.options["general:border_size"] ?? 1) : 2
    property real realRounding: onClient ? (Kwin.options["decoration:rounding"] ?? 0) : 0

    property real ssx
    property real ssy

    property real sx: 0
    property real sy: 0
    property real ex: screen.width
    property real ey: screen.height

    property real rsx: Math.min(sx, ex)
    property real rsy: Math.min(sy, ey)
    property real sw: Math.abs(sx - ex)
    property real sh: Math.abs(sy - ey)

    property list<var> clients: {
        const mon = Kwin.monitorFor(screen);
        if (!mon)
            return [];

        const special = mon.lastIpcObject.specialWorkspace;
        const wsId = special.name ? special.id : mon.activeWorkspace.id;

        return Kwin.toplevels.values.filter(c => c.workspace?.id === wsId).sort((a, b) => {
            // Pinned first, then fullscreen, then floating, then any other
            const ac = a.lastIpcObject;
            const bc = b.lastIpcObject;
            return (bc.pinned - ac.pinned) || ((bc.fullscreen !== 0) - (ac.fullscreen !== 0)) || (bc.floating - ac.floating);
        });
    }

    function checkClientRects(x: real, y: real): void {
        for (const client of clients) {
            if (!client)
                continue;

            let {
                at: [cx, cy],
                size: [cw, ch]
            } = client.lastIpcObject;
            cx -= screen.x;
            cy -= screen.y;
            if (cx <= x && cy <= y && cx + cw >= x && cy + ch >= y) {
                onClient = true;
                sx = cx;
                sy = cy;
                ex = cx + cw;
                ey = cy + ch;
                break;
            }
        }
    }

    function save(): void {
        const isSearch = root.loader.searchMode;
        const tmpfile = isSearch
            ? Qt.resolvedUrl("file://" + Paths.runtimeTemp("search.png"))
            : Qt.resolvedUrl("file://" + Paths.runtimeTemp(`picker-${Quickshell.processId}-${Date.now()}.png`));
        CUtils.saveItem(screencopy, tmpfile, Qt.rect(Math.ceil(rsx), Math.ceil(rsy), Math.floor(sw), Math.floor(sh)), path => {
            if (isSearch) {
                Quickshell.execDetached(["touch", Paths.runtimeTemp("search.done")]);
            } else if (root.loader.clipboardOnly) {
                Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < " + path]);
                Quickshell.execDetached(["notify-send", "-a", "caelestia-cli", "-i", path, "Screenshot taken", "Screenshot copied to clipboard"]);
            } else {
                Quickshell.execDetached(["swappy", "-f", path]);
            }
            Audio.playCameraClick();
            closeAnim.start();
        });
    }

    onClientsChanged: checkClientRects(mouseX, mouseY)

    anchors.fill: parent
    opacity: 0
    hoverEnabled: true
    cursorShape: Qt.CrossCursor

    Component.onCompleted: {
        Kwin.extras.refreshOptions();

        // Break binding if frozen
        if (loader.freeze)
            clients = clients;

        opacity = 1;

        const c = clients[0];
        if (c) {
            const cx = c.lastIpcObject.at[0] - screen.x;
            const cy = c.lastIpcObject.at[1] - screen.y;
            onClient = true;
            sx = cx;
            sy = cy;
            ex = cx + c.lastIpcObject.size[0];
            ey = cy + c.lastIpcObject.size[1];
        } else {
            sx = screen.width / 2 - 100;
            sy = screen.height / 2 - 100;
            ex = screen.width / 2 + 100;
            ey = screen.height / 2 + 100;
        }
    }

    onPressed: event => {
        ssx = event.x;
        ssy = event.y;
    }

    onReleased: {
        if (closeAnim.running)
            return;

        if (root.loader.freeze) {
            save();
        } else {
            overlay.visible = border.visible = false;
            screencopy.visible = false;
            screencopy.active = true;
        }
    }

    onPositionChanged: event => {
        const x = event.x;
        const y = event.y;

        if (pressed) {
            onClient = false;
            sx = ssx;
            sy = ssy;
            ex = x;
            ey = y;
        } else {
            checkClientRects(x, y);
        }
    }

    focus: true
    Keys.onEscapePressed: closeAnim.start()

    SequentialAnimation {
        id: closeAnim

        PropertyAction {
            target: root.loader
            property: "closing"
            value: true
        }
        ParallelAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            Anim {
                target: root
                properties: "rsx,rsy"
                to: 0
            }
            Anim {
                target: root
                property: "sw"
                to: root.screen.width
            }
            Anim {
                target: root
                property: "sh"
                to: root.screen.height
            }
        }
        PropertyAction {
            target: root.loader
            property: "activeAsync"
            value: false
        }
    }

    Process {
        // hyprctl cursorpos is Hyprland-only; skip on KDE.
        running: false
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pos = JSON.parse(text);
                root.checkClientRects(pos.x - root.screen.x, pos.y - root.screen.y);
            }
        }
    }

    Loader {
        id: screencopy

        asynchronous: true
        anchors.fill: parent

        active: root.loader.freeze

        sourceComponent: ScreencopyView {
            captureSource: root.screen

            onHasContentChanged: {
                if (hasContent && !root.loader.freeze) {
                    overlay.visible = border.visible = true;
                    root.save();
                }
            }
        }
    }

    Rectangle {
        id: overlay

        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.rsx - border.width
            topMargin: root.rsy - border.width
        }

        width: root.sw + border.width * 2
        height: root.sh + border.width * 2
        
        color: "transparent"
        border.color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.3)
        border.width: Math.max(root.width, root.height)
        visible: false
    }

    Rectangle {
        id: border

        color: "transparent"
        radius: root.realRounding > 0 ? root.realRounding + root.realBorderWidth : 0
        border.width: root.realBorderWidth
        border.color: Colours.palette.m3primary

        x: root.rsx - root.realBorderWidth
        y: root.rsy - root.realBorderWidth
        implicitWidth: root.sw + root.realBorderWidth * 2
        implicitHeight: root.sh + root.realBorderWidth * 2

        Behavior on border.color {
            CAnim {}
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Behavior on rsx {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on rsy {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on sw {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on sh {
        enabled: !root.pressed

        Anim {}
    }
}
