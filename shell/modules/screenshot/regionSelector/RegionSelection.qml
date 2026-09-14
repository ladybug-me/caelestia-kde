import ".."
import "../../../components/controls"
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Services
import qs.services
import qs.utils

PanelWindow {
    id: root

    visible: false
    color: "transparent"
    WlrLayershell.namespace: "osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    


    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SelectionMode { RectCorners, Circle }

    enum Phase { Select, Post }

    property var action: ScreenshotAction.SnipAction.Copy

    property var selectionMode: RegionSelection.SelectionMode.RectCorners

    property var phase: RegionSelection.Phase.Select

    signal dismiss()

    // Reset per-session state when the overlay is closed
    onDismiss: {
        root.snapshotWorkspaceId = 0;
        root.snapshotWorkspaceUuid = "";
        root.lastHoverFocusedAddress = "";
    }

    // Styles
    property string screenshotDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/caelestia-screenshot`

    property color overlayColor: Qt.rgba("#000000".r, "#000000".g, "#000000".b, 1.0 - 0.4)

    property color brightSecondary: Colours.palette.m3secondary

    property color selectionBorderColor: brightSecondary

    property color selectionFillColor: "#33ffffff"

    property color windowBorderColor: brightSecondary

    property color windowFillColor: Qt.rgba(windowBorderColor.r, windowBorderColor.g, windowBorderColor.b, 1.0 - 0.85)

    property color onBorderColor: "#ff000000"

    property real targetRegionOpacity: 0.6

    // Vars for indicators
    // Snapshot of the active workspace when the overlay opened — used to filter
    // windows so that hover-focus actions never cause workspace switching that
    // would update this filter mid-session.
    property int snapshotWorkspaceId: 0
    property string snapshotWorkspaceUuid: ""

    readonly property var windows: {
        // Prefer the snapshotted workspace (set when overlay opens) so that
        // focusWindow() calls during hover cannot cause the filter to shift.
        const useSnapshot = root.snapshotWorkspaceId > 0 || root.snapshotWorkspaceUuid !== "";
        const target = useSnapshot
            ? (root.snapshotWorkspaceUuid !== "" ? root.snapshotWorkspaceUuid : root.snapshotWorkspaceId)
            : (true ? Kwin.activeWsId : 0);

        // windowsForWorkspace owns the workspace-field semantics (numeric id /
        // uuid, -1 = all workspaces), so hover-focus cannot drift the filter.
        const arr = Array.from(true
            ? Kwin.windowsForWorkspace(target)
            : []);

        return arr.sort((a, b) => {
            // Sort floating=true windows before others
            if (a.floating === b.floating) return 0;
            return a.floating ? -1 : 1;
        });
    }

    // Screen & interaction vars
    readonly property real monitorScale: (frozenImage.sourceSize.width > 0 && root.screen.width > 0) ? (frozenImage.sourceSize.width / root.screen.width) : (screen.devicePixelRatio || 1.0)

    readonly property real monitorOffsetX: screen.x || 0

    readonly property real monitorOffsetY: screen.y || 0

    property string activeWorkspaceId: ""

    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}.png`

    property real dragStartX: 0

    property real dragStartY: 0

    property real draggingX: 0

    property real draggingY: 0

    property real dragDiffX: 0

    property real dragDiffY: 0

    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)

    property bool dragging: false

    property var points: []

    property var mouseButton: null

    readonly property var windowRegions: RegionFunctions.filterWindowRegionsByLayers(
        root.windows,
        []
    ).map(window => {
        return {
            at: [window.x - root.monitorOffsetX, window.y - root.monitorOffsetY],
            size: [window.width, window.height],
            class: window.class,
            title: window.title,
            address: window.address || "",
        }
    })

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)

    property bool showWindowOutlines: false

    property bool enableWindowRegions: showWindowOutlines && !isCircleSelection

    // Target
    property real targetedRegionX: -1

    property real targetedRegionY: -1

    property real targetedRegionWidth: 0

    property real targetedRegionHeight: 0

    // The address (uuid) of the window currently under the cursor in window-outline mode
    property string targetedWindowAddress: ""

    // Tracks the last window we focused on hover — avoids redundant focus calls
    property string lastHoverFocusedAddress: ""

    // Debounce timer: focus the hovered window shortly after the mouse enters it
    Timer {
        id: focusHoverTimer

        interval: 120
        repeat: false
        onTriggered: {
            if (root.showWindowOutlines && root.targetedWindowAddress
                    && root.targetedWindowAddress !== root.lastHoverFocusedAddress) {
                // Verify the window is still on the current workspace before focusing
                const stillVisible = root.windowRegions.some(
                    r => r.address === root.targetedWindowAddress
                );
                if (stillVisible) {
                    Kwin.focusWindow(root.targetedWindowAddress);
                    root.lastHoverFocusedAddress = root.targetedWindowAddress;
                }
            }
        }
    }

    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }

    function setRegionToTargeted() {
        const padding = 0; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function updateTargetedRegion(x, y) {
        // Window regions — pick the smallest (most specific) window containing the cursor
        let clickedWindow = null;
        let smallestArea = Infinity;
        for (const region of root.windowRegions) {
            if (region.at[0] <= x && x <= region.at[0] + region.size[0]
                    && region.at[1] <= y && y <= region.at[1] + region.size[1]) {
                const area = region.size[0] * region.size[1];
                if (area < smallestArea) {
                    smallestArea = area;
                    clickedWindow = region;
                }
            }
        }
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            const newAddr = clickedWindow.address || "";
            if (root.showWindowOutlines && newAddr && newAddr !== root.targetedWindowAddress) {
                root.targetedWindowAddress = newAddr;
                focusHoverTimer.restart();
            } else {
                root.targetedWindowAddress = newAddr;
            }
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
        root.targetedWindowAddress = "";
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)

    property real regionHeight: Math.abs(draggingY - dragStartY)

    property real regionX: Math.min(dragStartX, draggingX)

    property real regionY: Math.min(dragStartY, draggingY)

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc

        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            // Refresh the shared recorder probe so the stop-before-snip check
            // below sees the freshest state.
            Recorder.probeRecording();
            root.preparationDone = true;
        }
    }

    property bool isRecording: root.action === ScreenshotAction.SnipAction.Record || root.action === ScreenshotAction.SnipAction.RecordWithSound

    // A recording is already active: entering region-select toggles it off.
    property bool recordingShouldStop: root.isRecording && Recorder.running

    property bool preparationDone: false

    property bool regionConfirmPending: false

    property string frozenImageSource: ""

    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Launch.exec([Paths.bin("caelestia-record")]);
            root.dismiss();
            return;
        }
        root.frozenImageSource = "file://" + root.screenshotPath;
        // Freeze the workspace context so hover-focus never shifts the filter
const snapId = Kwin.activeWsId;
root.snapshotWorkspaceId = snapId;
const snapIdx = snapId > 0 ? snapId - 1 : 0;
root.snapshotWorkspaceUuid = Kwin.workspaces[snapIdx]
    ? Kwin.workspaces[snapIdx].id : "";
    
        root.visible = true;
        mouseArea.forceActiveFocus();
    }

    Component.onDestruction: {
        if (!root.screenshotConsumed) {
            Quickshell.execDetached(["rm", "-f", root.screenshotPath]);
        }
    }

    property bool screenshotConsumed: false

    // Execution after selection
    function snip() {
        root.screenshotConsumed = true;

        // Clamp region to screen bounds
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Adjust action
        if (root.action === ScreenshotAction.SnipAction.Copy || root.action === ScreenshotAction.SnipAction.Edit) {
            root.action = root.mouseButton === Qt.RightButton ? ScreenshotAction.SnipAction.Edit : ScreenshotAction.SnipAction.Copy;
        }

        const command = ScreenshotAction.getCommand(
            root.regionX * root.monitorScale, //
            root.regionY * root.monitorScale, //
            root.regionWidth * root.monitorScale,//
            root.regionHeight * root.monitorScale, //
            root.screenshotPath, //
            root.action
        )
        Quickshell.execDetached(command);
        if (root.action == ScreenshotAction.SnipAction.Record || root.action == ScreenshotAction.SnipAction.RecordWithSound) {
            root.phase = RegionSelection.Phase.Post
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        } else {
            root.dismiss();
        }
    }

    // Window screenshot via spectacle — focuses the target window then calls spectacle -b -a
    function snipWindow(windowAddress) {
        root.screenshotConsumed = true;

        const saveDir = `${Paths.absolutePath("~/Pictures/Screenshots")}`;
        const saveFile = `${saveDir}/screenshot-$(date +%Y-%m-%d_%H.%M.%S).png`;

        // Determine spectacle flags based on action
        let spectacleFlags = "-b -a -n";
        if (root.mouseButton === Qt.RightButton || root.action === ScreenshotAction.SnipAction.Edit) {
            spectacleFlags = "-b -a -n -e"; // exclude decorations on right-click (edit)
        }

        const tmpFile = Paths.runtimeTemp(`snip-window-${Date.now()}.png`);
        const actionScript = ScreenshotAction.getScript(
            0, 0, 99999, 99999, tmpFile, root.action, saveDir
        );

        const command = [
            "bash", "-c",
            `set -euo pipefail; ` +
            `spectacle ${spectacleFlags} -o '${tmpFile}' && ${actionScript}`
        ];

        // Focus the window, dismiss overlay, then shoot after a short delay
        if (windowAddress) {
            Kwin.focusWindow(windowAddress);
        }
        root.dismiss();
        // Small delay so the window has time to come to front before spectacle fires
        Qt.callLater(() => { Quickshell.execDetached(command); });
    }

    // Only clickable in Selection phase
    mask: Region {
        item: switch(root.phase) {
            case RegionSelection.Phase.Select: return mouseArea;
            case RegionSelection.Phase.Post: return null;
        }
    }

    Image { // For freezing
        id: frozenImage

        anchors.fill: parent
        source: root.frozenImageSource
        cache: false
        // In window-outline mode hide the frozen frame so the live desktop shows through
        visible: root.phase === RegionSelection.Phase.Select && !root.showWindowOutlines
    }

    GlobalShortcut {
        name: "caelestia_screenshot_escape"
        key: root.visible ? "Escape" : ""
        onActivated: root.dismiss()
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        focus: root.visible
        cursorShape: root.showWindowOutlines
            ? (root.targetedRegionValid() ? Qt.PointingHandCursor : Qt.ArrowCursor)
            : (root.draggedAway ? Qt.ArrowCursor : Qt.CrossCursor)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        // Controls
        onPressed: (mouse) => {
            mouse.accepted = true;
            root.mouseButton = mouse.button;
            if (root.showWindowOutlines) return;
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragging = true;
        }
        onReleased: (mouse) => {
            if (root.showWindowOutlines) {
                if (root.targetedWindowAddress) {
                    root.snipWindow(root.targetedWindowAddress);
                } else if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                    root.snip();
                }
                return;
            }

            root.dragging = false;
            // Detect if it was a click -> Try to select targeted region
            if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                }
            }
            // Circle dragging?
            else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = 0 + 2 / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
            }

            root.snip();
        }
        onPositionChanged: (mouse) => {
            root.updateTargetedRegion(mouse.x, mouse.y);
            if (root.showWindowOutlines || !root.dragging) return;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            root.points.push({ x: mouse.x, y: mouse.y });
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: !root.showWindowOutlines && root.selectionMode === RegionSelection.SelectionMode.RectCorners
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: mouseArea.mouseX
                mouseY: mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: !root.showWindowOutlines && root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            z: 9999
            active: !root.showWindowOutlines && root.phase === RegionSelection.Phase.Select && root.visible
            x: mouseArea.mouseX
            y: mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                        return root.windowRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: targeted ? 99 : 2

                required property var modelData
                clientDimensions: modelData
                showIcon: true
                text: modelData.title || modelData["class"] || ""
                iconName: modelData["class"] || ""
                targeted: !root.draggedAway && //
                    (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])
                opacity: root.draggedAway ? 0 : (root.targetedRegionValid() && !targeted ? 0 : root.targetRegionOpacity)
                borderColor: root.windowBorderColor
                // Fade alpha to 0 instead of the literal "transparent" string,
                // which would animate RGB through black via TargetRegion's
                // Behavior on color.
                fillColor: targeted ? root.windowFillColor : Qt.alpha(root.windowFillColor, 0)
                radius: 12
            }
        }

        // Controls
        Row {
            id: regionSelectionControls

            z: 10
            visible: root.phase === RegionSelection.Phase.Select
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0

            Connections {
                target: root

                function onVisibleChanged() {
                    if (!visible) return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
            Behavior on anchors.bottomMargin {
                animation: NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
            }

            spacing: 6

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                Synchronizer on selectionMode {
                    property alias source: root.selectionMode
                }
                Synchronizer on showWindowOutlines {
                    property alias source: root.showWindowOutlines
                }

                onDismiss: root.dismiss();
            }
            IconButton {
                id: fullscreenBtn

                anchors.verticalCenter: parent.verticalCenter
                icon: "fullscreen"
                onClicked: {
                    root.regionX = 0;
                    root.regionY = 0;
                    root.regionWidth = root.screen.width;
                    root.regionHeight = root.screen.height;
                    root.snip();
                }

                Tooltip {
                    target: fullscreenBtn
                    text: qsTr("Full Screen Screenshot")
                }
            }
            // Confirm snip button — appears after a region is drawn
            IconButton {
                id: confirmBtn

                anchors.verticalCenter: parent.verticalCenter
                visible: root.regionConfirmPending
                icon: "check"
                onClicked: root.snip();

                Tooltip {
                    target: confirmBtn
                    text: qsTr("Snip selected region (Enter)")
                }
            }
            IconButton {
                id: closeBtn

                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                onClicked: {
                    if (root.regionConfirmPending) {
                        // Reset selection — let user redraw
                        root.regionConfirmPending = false;
                        root.regionWidth = 0;
                        root.regionHeight = 0;
                    } else {
                        root.dismiss();
                    }
                }

                Tooltip {
                    target: closeBtn
                    text: root.regionConfirmPending ? qsTr("Clear selection") : qsTr("Close")
                }
            }
        }

    }
}
