pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.bar.components as BarComponents
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var componentMeta: {
        "logo": { icon: "rocket_launch", name: qsTr("Logo") },
        "workspaces": { icon: "workspaces", name: qsTr("Workspaces") },
        "github": {
            icon: "commit",
            name: qsTr("GitHub"),
            available: BarComponents.GithubStore.available,
            unavailableText: qsTr("GitHub token not detected")
        },
        "greeter": { icon: "waving_hand", name: qsTr("Greeter") },
        "activeWindow": { icon: "waving_hand", name: qsTr("Greeter") },
        "tray": { icon: "expand_more", name: qsTr("System tray") },
        "updateIndicator": { icon: "update", name: qsTr("Updates") },
        "clock": { icon: "schedule", name: qsTr("Clock") },
        "statusIcons": { icon: "wifi", name: qsTr("Status icons") },
        "kbLayoutIndicator": { icon: "keyboard", name: qsTr("Keyboard layout") },
        "notificationsIndicator": { icon: "notifications", name: qsTr("Notifications") },
        "perfCpu": { icon: "memory", name: qsTr("CPU"), available: Cpu.name.length > 0, unavailableText: qsTr("CPU sensor not detected") },
        "perfMemory": { icon: "memory_alt", name: qsTr("Memory"), available: Memory.total > 1, unavailableText: qsTr("Memory sensor not detected") },
        "perfStorage": { icon: "hard_disk", name: qsTr("Storage"), available: Storage.disks.length > 0, unavailableText: qsTr("Storage disks not detected") },
        "perfNetwork": { icon: "swap_vert", name: qsTr("Network") },
        "perfGpu": { icon: "desktop_windows", name: qsTr("GPU"), available: Gpu.type !== Gpu.None, unavailableText: qsTr("GPU not detected") },
        "perfBattery": { icon: "battery_full", name: qsTr("Battery"), available: UPower.displayDevice.isLaptopBattery, unavailableText: qsTr("Battery not detected") },
        "dock": { icon: "apps", name: qsTr("Dock") },
        "showDesktop": { icon: "keyboard_double_arrow_down", name: qsTr("Show Desktop") },
        "power": { icon: "power_settings_new", name: qsTr("Power menu") }
    }
    property bool isGlobalDragging: false
    property string globalDragCompId: ""
    property string globalDragSourceList: ""
    property string globalDragHoveredList: ""
    readonly property real zonePadding: Tokens.padding.medium
    readonly property real emptyZoneHeight: 72
    property Component panelDelegate: Component {
        Item {
            id: delegateWrapper

            required property int index
            required property string compId
            required property bool isPlaceholder

            readonly property bool isAvailable: (componentMeta[compId]?.available ?? true)
            readonly property string sourceList: {
                if (ListView.view === leftList) return "left";
                if (ListView.view === middleList) return "middle";
                if (ListView.view === rightList) return "right";
                return "library";
            }
            readonly property bool isDraggingThis: activeDragArea.drag.active

            width: ListView.view ? ListView.view.width : 0
            height: (root.isGlobalDragging && root.globalDragSourceList === sourceList && root.globalDragCompId === compId && root.globalDragHoveredList !== sourceList) ? 0 : 50
            visible: height > 0
            z: isDraggingThis ? 100 : 1

            Behavior on height { Anim { type: Anim.FastSpatial } }

            DropArea {
                anchors.fill: parent
                keys: ["component"]
                onEntered: drag => {
                    let sourceItem = drag.source;
                    if (!sourceItem) return;

                    let to = delegateWrapper.index;
                    let targetModel = root.getModel(sourceList);
                    if (!targetModel) return;

                    if (sourceItem.sourceList === sourceList) {
                        let from = root.findItemIndex(targetModel, root.globalDragCompId);
                        if (from !== -1 && to !== -1 && from !== to) {
                            targetModel.move(from, to, 1);
                        }
                    } else {
                        let phIndex = -1;
                        for (let i = 0; i < targetModel.count; i++) {
                            if (targetModel.get(i).isPlaceholder) {
                                phIndex = i;
                                break;
                            }
                        }
                        if (phIndex !== -1 && to !== -1 && phIndex !== to) {
                            targetModel.move(phIndex, to, 1);
                        }
                    }
                }
            }

            ConnectedRect {
                id: activeDelegate

                width: delegateWrapper.width
                height: 50
                radius: Tokens.rounding.medium
                color: isPlaceholder ? "transparent" : (sourceList !== "library" ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLowest)
                border.width: isPlaceholder ? 1 : 0
                border.color: Colours.palette.m3outline
                opacity: isPlaceholder ? 0.2 : (delegateWrapper.isAvailable ? 1.0 : 0.6)
                scale: 1.0
                Drag.active: activeDragArea.drag.active
                Drag.source: delegateWrapper
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                Drag.keys: ["component"]
                states: State {
                    when: activeDragArea.drag.active

                    ParentChange { target: activeDelegate; parent: root.flickable.contentItem }
                    PropertyChanges { target: activeDelegate; scale: 1.05 }
                }

                Behavior on scale { Anim { type: Anim.FastSpatial } }

                MouseArea {
                    id: activeDragArea

                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: activeDelegate
                    drag.axis: Drag.XAndYAxis
                    cursorShape: Qt.PointingHandCursor
                    enabled: !isPlaceholder

                    onPressed: {
                        root.globalDragCompId = compId;
                        root.globalDragSourceList = sourceList;
                        root.globalDragHoveredList = sourceList;
                    }

                    onPositionChanged: {
                        if (activeDragArea.drag.active && !root.isGlobalDragging) {
                            root.isGlobalDragging = true;
                        }
                    }

                    onReleased: {
                        let draggedId = root.globalDragCompId;
                        let srcList = root.globalDragSourceList;
                        let hovList = root.globalDragHoveredList;

                        root.isGlobalDragging = false;
                        root.globalDragCompId = "";
                        root.globalDragSourceList = "";
                        root.globalDragHoveredList = "";

                        if (draggedId !== "" && srcList !== "" && hovList !== "" && srcList !== hovList) {
                            let srcModel = root.getModel(srcList);
                            let dstModel = root.getModel(hovList);

                            if (srcModel && dstModel) {
                                let srcIdx = root.findItemIndex(srcModel, draggedId);
                                let phIndex = -1;
                                for (let i = 0; i < dstModel.count; i++) {
                                    if (dstModel.get(i).isPlaceholder) {
                                        phIndex = i;
                                        break;
                                    }
                                }

                                if (srcIdx !== -1) {
                                    srcModel.remove(srcIdx);
                                    if (phIndex !== -1) {
                                        dstModel.set(phIndex, { compId: draggedId, isPlaceholder: false });
                                    } else {
                                        dstModel.append({ compId: draggedId, isPlaceholder: false });
                                    }
                                }
                            }
                        }

                        root.clearAllPlaceholders();
                        activeDelegate.x = 0;
                        activeDelegate.y = 0;
                        save();
                    }

                    onCanceled: {
                        root.isGlobalDragging = false;
                        root.globalDragCompId = "";
                        root.globalDragSourceList = "";
                        root.globalDragHoveredList = "";
                        root.clearAllPlaceholders();
                        activeDelegate.x = 0;
                        activeDelegate.y = 0;
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    acceptedButtons: Qt.NoButton
                    color: Colours.palette.m3onSurface
                    opacity: activeDragArea.containsMouse && !isPlaceholder && !isDraggingThis ? 0.08 : 0

                    Behavior on opacity { Anim { type: Anim.FastEffects } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small
                    visible: !isPlaceholder

                    MaterialIcon {
                        text: componentMeta[compId]?.icon ?? "widgets"
                        color: sourceList !== "library" ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const base = componentMeta[compId]?.name ?? compId;
                            if (delegateWrapper.isAvailable)
                                return base;
                            const reason = componentMeta[compId]?.unavailableText ?? qsTr("Not detected");
                            return `${base} (${reason})`;
                        }
                        font: Tokens.font.body.small
                        color: sourceList !== "library" ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }

                    IconButton {
                        visible: sourceList === "library"
                        icon: "add"
                        type: IconButton.Text
                        ToolTip.text: qsTr("Add to right zone")
                        ToolTip.visible: hovered
                        onClicked: root.moveItemToZone(compId, "right")
                    }

                    IconButton {
                        visible: sourceList !== "library"
                        icon: "close"
                        type: IconButton.Text
                        ToolTip.text: qsTr("Disable component")
                        ToolTip.visible: hovered
                        onClicked: root.moveItemToZone(compId, "library")
                    }

                    MaterialIcon {
                        text: "drag_indicator"
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }

    function getModel(name: string): ListModel {
        if (name === "left") return leftModel;
        if (name === "middle") return middleModel;
        if (name === "right") return rightModel;
        if (name === "library") return libraryModel;
        return null;
    }

    function findItemIndex(model: ListModel, compId: string): int {
        if (!model) return -1;
        for (let i = 0; i < model.count; i++) {
            let item = model.get(i);
            if (item && item.compId === compId && !item.isPlaceholder)
                return i;
        }
        return -1;
    }

    function clearPlaceholders(exceptModelName: string): void {
        const listNames = ["left", "middle", "right", "library"];
        for (let name of listNames) {
            if (name === exceptModelName) continue;
            let model = getModel(name);
            if (model) {
                for (let i = model.count - 1; i >= 0; i--) {
                    if (model.get(i).isPlaceholder)
                        model.remove(i);
                }
            }
        }
    }

    function clearAllPlaceholders(): void {
        clearPlaceholders("");
    }

    function moveItemToZone(compId: string, targetZone: string): void {
        const listNames = ["left", "middle", "right", "library"];
        let foundSource = "";
        let foundIdx = -1;

        for (let name of listNames) {
            let model = getModel(name);
            let idx = findItemIndex(model, compId);
            if (idx !== -1) {
                foundSource = name;
                foundIdx = idx;
                break;
            }
        }

        if (foundIdx === -1 || foundSource === targetZone) return;

        let srcModel = getModel(foundSource);
        let dstModel = getModel(targetZone);
        if (srcModel && dstModel) {
            srcModel.remove(foundIdx);
            dstModel.append({ compId: compId, isPlaceholder: false });
            save();
        }
    }

    function load(): void {
        let entries = Config.bar.entries;
        leftModel.clear();
        middleModel.clear();
        rightModel.clear();
        libraryModel.clear();

        let activeCounts = {};
        for (let i = 0; i < entries.length; i++) {
            let entry = entries[i];
            if (entry.id === "spacer") continue;

            activeCounts[entry.id] = (activeCounts[entry.id] || 0) + 1;

            if (entry.enabled) {
                let zone = entry.zone || "left";
                if (zone === "left") leftModel.append({ "compId": entry.id, "isPlaceholder": false });
                else if (zone === "middle") middleModel.append({ "compId": entry.id, "isPlaceholder": false });
                else if (zone === "right") rightModel.append({ "compId": entry.id, "isPlaceholder": false });
            } else {
                libraryModel.append({ "compId": entry.id, "isPlaceholder": false });
            }
        }

        for (let key in componentMeta) {
            if (!activeCounts[key]) {
                libraryModel.append({ "compId": key, "isPlaceholder": false });
            }
        }
    }

    function defaultEntries(): var {
        return [
            { id: "logo", enabled: true, zone: "left" },
            { id: "workspaces", enabled: true, zone: "left" },
            { id: "activeWindow", enabled: true, zone: "left" },
            { id: "dock", enabled: true, zone: "middle" },
            { id: "tray", enabled: true, zone: "right" },
            { id: "updateIndicator", enabled: true, zone: "right" },
            { id: "github", enabled: false, zone: "right" },
            { id: "clock", enabled: true, zone: "right" },
            { id: "statusIcons", enabled: true, zone: "right" },
            { id: "kbLayoutIndicator", enabled: false, zone: "right" },
            { id: "notificationsIndicator", enabled: false, zone: "right" },
            { id: "perfCpu", enabled: false, zone: "right" },
            { id: "perfMemory", enabled: false, zone: "right" },
            { id: "perfStorage", enabled: false, zone: "right" },
            { id: "perfNetwork", enabled: false, zone: "right" },
            { id: "perfGpu", enabled: false, zone: "right" },
            { id: "perfBattery", enabled: false, zone: "right" },
            { id: "showDesktop", enabled: true, zone: "right" },
            { id: "power", enabled: true, zone: "right" }
        ];
    }

    function resetToDefaults(): void {
        const entries = defaultEntries();
        GlobalConfig.bar.entries = entries;

        leftModel.clear();
        middleModel.clear();
        rightModel.clear();
        libraryModel.clear();

        for (const entry of entries) {
            if (!entry.enabled) {
                libraryModel.append({ compId: entry.id, isPlaceholder: false });
                continue;
            }

            const zone = entry.zone || "left";
            if (zone === "left")
                leftModel.append({ compId: entry.id, isPlaceholder: false });
            else if (zone === "middle")
                middleModel.append({ compId: entry.id, isPlaceholder: false });
            else
                rightModel.append({ compId: entry.id, isPlaceholder: false });
        }
    }

    function save(): void {
        let newEntries = [];

        for (let i = 0; i < leftModel.count; i++) {
            if (!leftModel.get(i).isPlaceholder) {
                newEntries.push({ id: leftModel.get(i).compId, enabled: true, zone: "left" });
            }
        }
        for (let i = 0; i < middleModel.count; i++) {
            if (!middleModel.get(i).isPlaceholder) {
                newEntries.push({ id: middleModel.get(i).compId, enabled: true, zone: "middle" });
            }
        }
        for (let i = 0; i < rightModel.count; i++) {
            if (!rightModel.get(i).isPlaceholder) {
                newEntries.push({ id: rightModel.get(i).compId, enabled: true, zone: "right" });
            }
        }
        for (let i = 0; i < libraryModel.count; i++) {
            if (!libraryModel.get(i).isPlaceholder) {
                newEntries.push({ id: libraryModel.get(i).compId, enabled: false, zone: "left" });
            }
        }

        GlobalConfig.bar.entries = newEntries;
    }

    title: qsTr("Toggle & rearrange")
    isSubPage: true
    scrollable: true

    Component.onCompleted: load()

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        ListModel { id: leftModel }
        ListModel { id: middleModel }
        ListModel { id: rightModel }
        ListModel { id: libraryModel }

        // Left Side: Active Components Zones
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacing.medium

            Text {
                text: qsTr("Active components")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            Text {
                text: qsTr("Drag to rearrange or disable")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            // Left Zone
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(root.emptyZoneHeight, leftList.contentHeight + root.zonePadding * 2)
                color: Colours.palette.m3surfaceContainer
                radius: Tokens.rounding.large

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.small
                    text: qsTr("Left Zone")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                    visible: leftModel.count === 0 || (leftModel.count === 1 && leftModel.get(0).isPlaceholder)
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["component"]
                    onEntered: drag => {
                        let sourceItem = drag.source;
                        if (!sourceItem) return;
                        root.globalDragHoveredList = "left";
                        root.clearPlaceholders("left");

                        if (sourceItem.sourceList !== "left") {
                            let hasPlaceholder = false;
                            for (let i = 0; i < leftModel.count; i++) {
                                if (leftModel.get(i).isPlaceholder) {
                                    hasPlaceholder = true;
                                    break;
                                }
                            }
                            if (!hasPlaceholder) {
                                leftModel.append({ compId: root.globalDragCompId, isPlaceholder: true });
                            }
                        }
                    }
                }

                ListView {
                    id: leftList

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    orientation: ListView.Vertical
                    spacing: Tokens.spacing.small
                    model: leftModel
                    clip: true
                    move: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    moveDisplaced: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    delegate: root.panelDelegate
                }
            }

            // Middle Zone
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(root.emptyZoneHeight, middleList.contentHeight + root.zonePadding * 2)
                color: Colours.palette.m3surfaceContainer
                radius: Tokens.rounding.large

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.small
                    text: qsTr("Middle Zone")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                    visible: middleModel.count === 0 || (middleModel.count === 1 && middleModel.get(0).isPlaceholder)
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["component"]
                    onEntered: drag => {
                        let sourceItem = drag.source;
                        if (!sourceItem) return;
                        root.globalDragHoveredList = "middle";
                        root.clearPlaceholders("middle");

                        if (sourceItem.sourceList !== "middle") {
                            let hasPlaceholder = false;
                            for (let i = 0; i < middleModel.count; i++) {
                                if (middleModel.get(i).isPlaceholder) {
                                    hasPlaceholder = true;
                                    break;
                                }
                            }
                            if (!hasPlaceholder) {
                                middleModel.append({ compId: root.globalDragCompId, isPlaceholder: true });
                            }
                        }
                    }
                }

                ListView {
                    id: middleList

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    orientation: ListView.Vertical
                    spacing: Tokens.spacing.small
                    model: middleModel
                    clip: true
                    move: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    moveDisplaced: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    delegate: root.panelDelegate
                }
            }

            // Right Zone
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(root.emptyZoneHeight, rightList.contentHeight + root.zonePadding * 2)
                color: Colours.palette.m3surfaceContainer
                radius: Tokens.rounding.large

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.small
                    text: qsTr("Right Zone")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                    visible: rightModel.count === 0 || (rightModel.count === 1 && rightModel.get(0).isPlaceholder)
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["component"]
                    onEntered: drag => {
                        let sourceItem = drag.source;
                        if (!sourceItem) return;
                        root.globalDragHoveredList = "right";
                        root.clearPlaceholders("right");

                        if (sourceItem.sourceList !== "right") {
                            let hasPlaceholder = false;
                            for (let i = 0; i < rightModel.count; i++) {
                                if (rightModel.get(i).isPlaceholder) {
                                    hasPlaceholder = true;
                                    break;
                                }
                            }
                            if (!hasPlaceholder) {
                                rightModel.append({ compId: root.globalDragCompId, isPlaceholder: true });
                            }
                        }
                    }
                }

                ListView {
                    id: rightList

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    orientation: ListView.Vertical
                    spacing: Tokens.spacing.small
                    model: rightModel
                    clip: true
                    move: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    moveDisplaced: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    delegate: root.panelDelegate
                }
            }
        }

        // Right Side: Library
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: qsTr("Library")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    Text {
                        text: qsTr("Disabled components")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                TextButton {
                    text: qsTr("RESET")
                    type: TextButton.Filled
                    ToolTip.text: qsTr("Restore the default taskbar component layout")
                    ToolTip.visible: hovered
                    onClicked: root.resetToDefaults()
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(root.emptyZoneHeight, libList.contentHeight + root.zonePadding * 2)
                color: "transparent"

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.small
                    text: qsTr("Empty")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                    visible: libraryModel.count === 0 || (libraryModel.count === 1 && libraryModel.get(0).isPlaceholder)
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["component"]
                    onEntered: drag => {
                        let sourceItem = drag.source;
                        if (!sourceItem) return;

                        root.globalDragHoveredList = "library";
                        root.clearPlaceholders("library");

                        if (sourceItem.sourceList !== "library") {
                            let hasPlaceholder = false;
                            for (let i = 0; i < libraryModel.count; i++) {
                                if (libraryModel.get(i).isPlaceholder) {
                                    hasPlaceholder = true;
                                    break;
                                }
                            }
                            if (!hasPlaceholder) {
                                libraryModel.append({ compId: root.globalDragCompId, isPlaceholder: true });
                            }
                        }
                    }
                }

                ListView {
                    id: libList

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    orientation: ListView.Vertical
                    spacing: Tokens.spacing.small
                    model: libraryModel
                    clip: true
                    move: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    moveDisplaced: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    delegate: root.panelDelegate
                }
            }
        }
    }
}
