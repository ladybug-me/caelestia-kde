pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.images
import qs.services
import qs.utils

StyledRect {
    id: root

    required property int index
    required property int activeWsId
    /// Screen this overview belongs to; window icons are limited to it.
    required property string screenName
    required property var occupied
    required property int groupOffset
    readonly property bool isWorkspace: true
    property real scaleFactor: 1.0
    property real swipeOffset: 0.0
    property bool isSwiping: false
    property var closingWindows: []
    readonly property int baseIndicatorSize: 120
    readonly property int baseWidth: 200
    readonly property int indicatorSize: Math.floor(baseIndicatorSize * scaleFactor)
    readonly property int size: implicitWidth
    readonly property int ws: groupOffset + index + 1
    readonly property int maxIcons: 8
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied
    property var kwinWindowList: Kwin.windowList
    readonly property bool active: activeWsId === ws
    readonly property real swipeWeight: {
        if (!isSwiping || swipeOffset === 0.0) return active ? 1.0 : 0.0;
        const activeIdx = activeWsId - 1;
        const targetIdx = swipeOffset > 0 ? activeIdx + 1 : activeIdx - 1;
        const t = Math.abs(swipeOffset);
        const myIdx = ws - 1;
        if (myIdx === activeIdx) return 1.0 - t;
        if (myIdx === targetIdx) return t;
        return 0.0;
    }
    property real smoothSwipeWeight: swipeWeight

    signal selected()
    signal reselected()

    // Prefer an icon extracted from the window's own _NET_WM_ICON, then fall
    // back to the themed desktop-entry lookup (same as the overview cards).
    function windowIconSource(client: var): string {
        if (!client)
            return "";
        const wp = WinIcons.paths[WinIcons.keyFor(client.class, client.pid ?? 0)];
        if (wp)
            return "file://" + wp;
        return client.iconName ? Icons.getAppIcon(client.iconName, "image-missing")
                               : (client.class ? Icons.getAppIcon(client.class, "image-missing") : "");
    }

    implicitWidth: Math.floor(baseWidth * scaleFactor)
    implicitHeight: indicatorSize
    radius: Tokens.rounding.large
    color: active ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 1) : (isOccupied ? Colours.tPalette.m3surfaceContainer : "transparent")
    border.color: isSwiping ? Qt.rgba(
        Colours.palette.m3primary.r * smoothSwipeWeight + Colours.tPalette.m3outlineVariant.r * (1.0 - smoothSwipeWeight),
        Colours.palette.m3primary.g * smoothSwipeWeight + Colours.tPalette.m3outlineVariant.g * (1.0 - smoothSwipeWeight),
        Colours.palette.m3primary.b * smoothSwipeWeight + Colours.tPalette.m3outlineVariant.b * (1.0 - smoothSwipeWeight),
        Colours.palette.m3primary.a * smoothSwipeWeight + Colours.tPalette.m3outlineVariant.a * (1.0 - smoothSwipeWeight))
        : (active ? Colours.palette.m3primary : Colours.tPalette.m3outlineVariant)
    border.width: active ? 2 : (isOccupied ? 0 : 2)
    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: Math.floor(baseWidth * scaleFactor)
    Layout.preferredHeight: indicatorSize
    Drag.active: workspaceDragHandler.active
    Drag.source: root
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    transform: Translate {
        x: workspaceDragHandler.active ? workspaceDragHandler.translation.x : 0
        y: workspaceDragHandler.active ? workspaceDragHandler.translation.y : 0
    }
    states: [
        State {
            when: workspaceDragHandler.active

            PropertyChanges {
                target: root
                opacity: 0.8
                z: 999
            }
        }
    ]

    Behavior on color { CAnim {} }
    Behavior on smoothSwipeWeight {
        enabled: root.isSwiping

        SmoothedAnimation {
            velocity: -1
            duration: 60
            easing.type: Easing.Linear
        }
    }
    DragHandler {
        id: workspaceDragHandler

        target: null
        onActiveChanged: {
            if (!active) {
                root.Drag.drop();
            }
        }
    }
    StateLayer {
        id: workspaceMouseArea

        anchors.fill: parent
        radius: parent.radius
        onClicked: {
            if (active) {
                reselected();
                // Close overview if reselected
                let p = parent;
                while (p) {
                    if (p.requestClose) {
                        p.requestClose();
                        break;
                    }
                    p = p.parent;
                }
            } else {
                const wId = Kwin.workspaces[root.ws - 1]?.id || root.ws.toString();
                Kwin.switchToWorkspace(wId, root.screenName);
                selected();
            }
        }
    }
    Item {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small
        width: Math.floor(28 * root.scaleFactor)
        height: Math.floor(28 * root.scaleFactor)
        z: 99
        opacity: 1.0
        enabled: true

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }
        StateLayer {
            id: closeBtn

            anchors.fill: parent
            radius: parent.width / 2
            onClicked: {
                const wId = Kwin.workspaces[root.ws - 1].id;
                if (wId)
                    Kwin.removeWorkspace(wId);
            }
        }
        MaterialIcon {
            anchors.centerIn: parent
            text: "close"
            fontStyle.pixelSize: Math.max(10, Math.floor(18 * root.scaleFactor))
            color: Colours.palette.m3onSurfaceVariant
        }
    }
    StyledText {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small
        text: root.ws.toString()
        font.pixelSize: 24
        font.weight: Font.Bold
        color: Colours.tPalette.m3onSurfaceVariant
        opacity: 0.3
    }
    DropArea {
        id: windowDropArea

        // Remembered because onExited carries no drag argument.
        property var hovering: null

        function clearHover(): void {
            if (windowDropArea.hovering) {
                windowDropArea.hovering.dropTargetScale = 0;
                windowDropArea.hovering = null;
            }
        }

        anchors.fill: parent
        onEntered: drag => {
            if (!drag.source || drag.source.clientAddress === undefined)
                return;
            // An icon dragged out of a thumbnail is a source too, and has no
            // preview to collapse -- it decides for itself, from how far it has
            // been lifted.
            if (!("dropTargetScale" in drag.source))
                return;
            // Nothing to preview when it is already here: a card hovering its
            // own workspace would shrink to say it is about to go somewhere it
            // already is.
            if (drag.source.wsId === root.ws)
                return;
            windowDropArea.hovering = drag.source;
            // Fit inside the thumbnail with a little room, so it reads as
            // landing in the slot rather than filling it exactly.
            drag.source.dropTargetScale = Math.min(width / Math.max(1, drag.source.width), height / Math.max(1, drag.source.height)) * 0.85;
        }
        onExited: windowDropArea.clearHover()
        onDropped: drop => {
            windowDropArea.clearHover();
            const sourceItem = drop.source;
            if (sourceItem && sourceItem.clientAddress) {
                if (sourceItem.wsId !== root.ws) {
                    sourceItem.visible = false;
                    Kwin.setWindowDesktop(sourceItem.clientAddress, root.ws);
                }
                drop.accept();
            }
        }
    }
    GridLayout {
        readonly property int count: repeater.count

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        rowSpacing: Tokens.padding.small
        columnSpacing: Tokens.padding.small
        columns: count <= 2 ? Math.max(1, count) : Math.ceil(count / 2)

        Repeater {
            id: repeater

            model: ScriptModel {
                values: {
                    const wsId = root.ws;
                    const _ = root.kwinWindowList;
                    let windows = [];
                    const wins = Kwin.windowsForWorkspace(wsId, false);
                    for (let i = 0; i < wins.length; ++i) {
                        const w = wins[i];
                        // windowsForWorkspace already filtered by workspace;
                        // this strip only shows its own screen.
                        if (w.output !== root.screenName)
                            continue;
                        if (!Kwin.isIgnoredWindow(w)) {
                            windows.push(w);
                        }
                    }

                    const maxIcons = root.maxIcons;
                    return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                }
            }
            delegate: StyledRect {
                id: iconDelegate

                required property var modelData
                required property int index
                readonly property string clientAddress: modelData.address || ""
                readonly property int wsId: root.ws
                /// Whether this icon has been pulled far enough up out of the
                /// strip to open into the window it stands for.
                ///
                /// Measured against where the drag started and switched on two
                /// thresholds rather than one. Driving it from the slots the drag
                /// passes over meant it flipped every time one was crossed, and
                /// each flip tore down and rebuilt the screencast -- the icon
                /// flickering between itself and the live view. A single
                /// threshold would do the same to anyone holding near it.
                property bool expanded: false
                readonly property real liftedBy: dragHandler.active ? iconDelegate.dragStartY - iconDelegate.y : 0
                readonly property real windowAspect: {
                    const w = modelData.width, h = modelData.height;
                    return (w > 0 && h > 0) ? w / h : 16 / 9;
                }
                property real dragStartX: 0
                property real dragStartY: 0
                property real dragStartWidth: 0
                property real dragStartHeight: 0
                property Item topLevel: null
                property bool closing: {
                    if (!root.closingWindows) return false;
                    for (let i = 0; i < root.closingWindows.length; i++) {
                        if (root.closingWindows[i] === modelData.address) return true;
                    }
                    return false;
                }

                Component.onCompleted: {
                    if (modelData && !DesktopEntries.heuristicLookup(modelData.iconName || modelData.class || ""))
                        WinIcons.request(modelData.class, modelData.title, modelData.pid ?? 0, modelData.address ? String(modelData.address) : "");
                }

                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerHigh
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.rowSpan: (repeater.count >= 3 && repeater.count % 2 !== 0 && index === 0) ? 2 : 1
                scale: closing ? 0.0 : 1.0
                opacity: closing ? 0.0 : 1.0
                

                Drag.active: dragHandler.active
                Drag.source: iconDelegate
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                states: [
                    State {
                        when: dragHandler.active

                        ParentChange {
                            target: iconDelegate
                            parent: topLevel
                            x: iconDelegate.dragStartX
                            y: iconDelegate.dragStartY
                        }
                        PropertyChanges {
                            target: iconDelegate
                            // Bound rather than set by ParentChange, so growing
                            // and shrinking follow the drag instead of being
                            // fixed once when it starts.
                            height: iconDelegate.expanded ? Math.round(360 / Math.max(0.2, iconDelegate.windowAspect)) : iconDelegate.dragStartHeight
                            opacity: 0.8
                            width: iconDelegate.expanded ? 360 : iconDelegate.dragStartWidth
                            z: 999
                        }
                    }
                ]

                onLiftedByChanged: {
                    if (!dragHandler.active)
                        iconDelegate.expanded = false;
                    else if (!iconDelegate.expanded && iconDelegate.liftedBy > 170)
                        iconDelegate.expanded = true;
                    else if (iconDelegate.expanded && iconDelegate.liftedBy < 100)
                        iconDelegate.expanded = false;
                }
                // Claimed while open so the card in the grid gives the stream
                // up; a node feeds one consumer.
                onExpandedChanged: Visibilities.streamClaim = iconDelegate.expanded ? iconDelegate.clientAddress : ""
                Component.onDestruction: {
                    if (iconDelegate.expanded)
                        Visibilities.streamClaim = "";
                }

                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


                DragHandler {
                    id: dragHandler

                    onActiveChanged: {
                        if (active) {
                            let tl = iconDelegate;
                            while (tl.parent) tl = tl.parent;
                            iconDelegate.topLevel = tl;
                            
                            if (tl) {
                                const p = iconDelegate.mapToItem(tl, 0, 0);
                                iconDelegate.dragStartX = p.x;
                                iconDelegate.dragStartY = p.y;
                            }
                            iconDelegate.dragStartWidth = iconDelegate.width;
                            iconDelegate.dragStartHeight = iconDelegate.height;
                        } else {
                            iconDelegate.Drag.drop();
                        }
                    }
                }
                WindowPreview {
                    // Collapsed it is just the icon; lifted out of the strip it
                    // opens into the window, which is what WindowPreview shows
                    // once a stream arrives. The icon it falls back to is the
                    // one the rest of the overview resolves, so a window with no
                    // desktop entry still shows its own.
                    active: iconDelegate.expanded
                    address: iconDelegate.clientAddress
                    anchors.fill: parent
                    fallbackIcon: root.windowIconSource(modelData)
                    fallbackScale: 0.6
                    sourceAspect: iconDelegate.windowAspect
                }
                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: {
                        if (root.active) {
                            if (modelData.address) {
                                Kwin.focusWindow(modelData.address);
                                
                                // Try to close overview by finding WindowGrid root
                                let p = parent;
                                while (p) {
                                    if (p.requestClose) {
                                        p.requestClose();
                                        break;
                                    }
                                    p = p.parent;
                                }
                            }
                        } else {
                            root.selected();
                        }
                    }
                }
            }
        }
    }
}
