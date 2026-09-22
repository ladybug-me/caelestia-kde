pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property bool isGlobalDragging: false

    property string globalDragSourceList: ""

    property int globalDragSourceIndex: -1

    property string globalDragHoveredList: ""

    property var pendingSaveEntries: []

    property real perfLoadStartedAt: 0

    property real perfSaveStartedAt: 0

    readonly property real zonePadding: Tokens.padding.medium

    readonly property real emptyZoneHeight: Math.max(root.height - 120, 72)

    property var componentMeta: ({
        "toggle_desktop_icons": { icon: "desktop_windows", name: qsTr("Desktop Icons") },
        "wallpaper_style": { icon: "wallpaper", name: qsTr("Wallpaper & style") },
        "next_wallpaper": { icon: "skip_next", name: qsTr("Next Wallpaper") },
        "system_settings": { icon: "settings", name: qsTr("System Settings") },
        "open_terminal": { icon: "terminal", name: qsTr("Open Terminal") },
        "add_shortcut": { icon: "add", name: qsTr("Add Shortcut...") }
    })

    function getModel(name) {
        if (name === "active") return activeModel;
        if (name === "library") return libraryModel;
        return null;
    }

    function collectEntries() {
        let newEntries = [];
        for (let i = 0; i < activeModel.count; i++) {
            if (!activeModel.get(i).isPlaceholder) {
                let r = activeModel.get(i).raw;
                r.enabled = true;
                newEntries.push(r);
            }
        }
        for (let i = 0; i < libraryModel.count; i++) {
            if (!libraryModel.get(i).isPlaceholder) {
                let r = libraryModel.get(i).raw;
                r.enabled = false;
                newEntries.push(r);
            }
        }
        return newEntries;
    }

    function applyEntries(entries) {
        let json = (!entries || entries.length === 0) ? ContextMenuStore.cloneEntries(ContextMenuStore.defaultEntries()) : ContextMenuStore.cloneEntries(entries);

        activeModel.clear();
        libraryModel.clear();

        for (let i = 0; i < json.length; i++) {
            let entry = json[i];
            if (entry.type === "custom") {
                root.componentMeta[entry.id] = { icon: entry.icon || "application-x-executable", name: entry.label };
            }
            if (entry.enabled) {
                activeModel.append({ "compId": entry.id, "isPlaceholder": false, "raw": entry });
            } else {
                libraryModel.append({ "compId": entry.id, "isPlaceholder": false, "raw": entry });
            }
        }

    }

    function flushSave() {
        if (!root.visible) return;
        const saveStartedAt = root.perfSaveStartedAt > 0 ? root.perfSaveStartedAt : Date.now();
        const payload = root.pendingSaveEntries.length > 0 ? root.pendingSaveEntries : collectEntries();
        ContextMenuStore.save(payload);
        root.componentMeta = root.componentMeta; // force update

        const saveMs = Date.now() - saveStartedAt;
        console.log("[perf][ContextMenuPage] save queued ms=" + saveMs + " entries=" + payload.length);
        root.perfSaveStartedAt = 0;
    }

    function save() {
        if (!root.visible) return;
        root.pendingSaveEntries = collectEntries();
        root.perfSaveStartedAt = Date.now();
        saveDebounce.restart();
    }

    function load(forceDisk) {
        root.perfLoadStartedAt = Date.now();
        ContextMenuStore.ensureLoaded(forceDisk === true);
        if (ContextMenuStore.loaded && !ContextMenuStore.loading) {
            root.applyEntries(ContextMenuStore.entries);
            const source = forceDisk === true ? "store_disk" : "store_cache";
            const loadMs = Date.now() - root.perfLoadStartedAt;
            console.log("[perf][ContextMenuPage] load source=" + source + " ms=" + loadMs + " entries=" + ContextMenuStore.entries.length);
            root.perfLoadStartedAt = 0;
        }
    }

    title: qsTr("Right Click Menu")
    isSubPage: true
    scrollable: true

    Component.onCompleted: load(true)

    RowLayout {
        id: mainLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        Connections {
            target: ContextMenuStore

            function onEntriesChanged() {
                root.applyEntries(ContextMenuStore.entries);
                if (root.perfLoadStartedAt > 0) {
                    const loadMs = Date.now() - root.perfLoadStartedAt;
                    console.log("[perf][ContextMenuPage] load source=store_update ms=" + loadMs + " entries=" + ContextMenuStore.entries.length);
                    root.perfLoadStartedAt = 0;
                }
            }
        }

        Timer {
            id: saveDebounce

            interval: 180
            repeat: false
            onTriggered: root.flushSave()
        }

        AddShortcutDialog {
            id: addShortcutDialog

            onSaved: (label, cmd, icon) => {
                let id = "custom_" + Date.now();
                libraryModel.append({
                    compId: id,
                    isPlaceholder: false,
                    raw: { id: id, type: "custom", label: label, command: cmd, icon: icon, enabled: false }
                });
                root.componentMeta[id] = { name: label, icon: icon };
                root.save();
            }
        }

        ListModel { id: activeModel }
        ListModel { id: libraryModel }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacing.medium

            Text {
                text: qsTr("Active menu items")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            Text {
                text: qsTr("Drag to rearrange or disable")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
            
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(root.emptyZoneHeight, activeList.contentHeight + root.zonePadding * 2)
                color: Colours.palette.m3surfaceContainer
                radius: Tokens.rounding.large
                
                Text {
                    text: qsTr("Empty Menu")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.small
                    visible: activeModel.count === 0 || (activeModel.count === 1 && activeModel.get(0).isPlaceholder)
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["component"]
                    onEntered: drag => {
                        let sourceItem = drag.source;
                        if (!sourceItem) return;
                        root.globalDragHoveredList = "active";
                        
                        if (sourceItem.sourceList !== "active") {
                            let hasPlaceholder = false;
                            for (let i = 0; i < activeModel.count; i++) {
                                if (activeModel.get(i).isPlaceholder) hasPlaceholder = true;
                            }
                            if (!hasPlaceholder) {
                                activeModel.append({ compId: sourceItem.compId, isPlaceholder: true, raw: sourceItem.raw });
                            }
                        }
                    }
                }

                ListView {
                    id: activeList

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    orientation: ListView.Vertical
                    spacing: Tokens.spacing.small
                    model: activeModel
                    clip: true

                    move: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    moveDisplaced: Transition { Anim { properties: "y"; type: Anim.FastSpatial } }
                    delegate: root.panelDelegate
                }
            }
        }

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
                        text: qsTr("Disabled items")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                TextButton {
                    id: addShortcutBtn

                    text: qsTr("Add Shortcut...")
                    type: TextButton.Filled
                    ToolTip.text: qsTr("Create a custom shortcut entry")
                    ToolTip.visible: hovered
                    onClicked: {
                        addShortcutDialog.targetItem = addShortcutBtn;
                        addShortcutDialog.open();
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(root.emptyZoneHeight, libList.contentHeight + root.zonePadding * 2)
                color: "transparent"
                
                Text {
                    text: qsTr("Empty")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurfaceVariant
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.small
                    visible: libraryModel.count === 0 || (libraryModel.count === 1 && libraryModel.get(0).isPlaceholder)
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["component"]
                    onEntered: drag => {
                        let sourceItem = drag.source;
                        if (!sourceItem) return;
                        
                        root.globalDragHoveredList = "library";
                        
                        if (sourceItem.sourceList !== "library") {
                            let hasPlaceholder = false;
                            for (let i = 0; i < libraryModel.count; i++) {
                                if (libraryModel.get(i).isPlaceholder) hasPlaceholder = true;
                            }
                            if (!hasPlaceholder) {
                                libraryModel.append({ compId: sourceItem.compId, isPlaceholder: true, raw: sourceItem.raw });
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

    property Component panelDelegate: Component {
        Item {
            id: delegateWrapper

            required property int index
            required property string compId
            required property bool isPlaceholder
            required property var raw

            property string sourceList: delegateWrapper.ListView.view.model === activeModel ? "active" : "library"

            width: ListView.view.width
            height: (root.isGlobalDragging && root.globalDragSourceList === sourceList && root.globalDragSourceIndex === index && root.globalDragHoveredList !== sourceList) ? 0 : 50
            visible: height > 0
            
            Behavior on height { Anim { type: Anim.FastSpatial } }
            
            property bool isDraggingThis: activeDragArea.drag.active

            z: isDraggingThis ? 100 : 1

            DropArea {
                anchors.fill: parent
                keys: ["component"]
                onEntered: drag => {
                    let sourceItem = drag.source;
                    if (!sourceItem) return;
                    
                    let from = -1;
                    let to = delegateWrapper.index;
                    let targetModel = root.getModel(sourceList);
                    
                    if (sourceItem.sourceList === sourceList) {
                        from = root.globalDragSourceIndex;
                    } else {
                        for (let i = 0; i < targetModel.count; i++) {
                            if (targetModel.get(i).isPlaceholder) { from = i; break; }
                        }
                    }
                    
                    if (from !== -1 && to !== -1 && from !== to) {
                        targetModel.move(from, to, 1);
                        if (sourceItem.sourceList === sourceList) {
                            root.globalDragSourceIndex = to;
                        }
                    }
                }
            }

            StyledRect {
                id: activeDelegate

                width: delegateWrapper.width
                height: 50
                color: isDraggingThis ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : (sourceList !== "library" ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainer)
                radius: Tokens.rounding.medium
                border.color: isDraggingThis ? Colours.palette.m3outline : (sourceList === "library" ? Colours.palette.m3outlineVariant : "transparent")
                border.width: isDraggingThis ? 2 : (sourceList === "library" ? 1 : 0)
                opacity: isPlaceholder ? 0.2 : 1.0

                MouseArea {
                    id: activeDragArea

                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: isPlaceholder ? null : activeDelegate
                    drag.axis: Drag.XAndYAxis
                    
                    onPressed: {
                        if (isPlaceholder) return;
                        root.isGlobalDragging = true;
                        root.globalDragSourceList = sourceList;
                        root.globalDragSourceIndex = index;
                        root.globalDragHoveredList = sourceList;
                    }
                    
                    onReleased: {
                        if (isPlaceholder) return;
                        
                        let finalHovered = root.globalDragHoveredList;
                        root.isGlobalDragging = false;
                        
                        let targetModel = root.getModel(finalHovered);
                        let sourceModel = root.getModel(sourceList);
                        
                        if (finalHovered !== sourceList && finalHovered !== "" && targetModel) {
                            let pIndex = -1;
                            for (let i = 0; i < targetModel.count; i++) {
                                if (targetModel.get(i).isPlaceholder) { pIndex = i; break; }
                            }
                            
                            if (pIndex !== -1) {
                                targetModel.remove(pIndex);
                                targetModel.insert(pIndex, { compId: compId, isPlaceholder: false, raw: raw });
                                sourceModel.remove(root.globalDragSourceIndex);
                            }
                        }
                        
                        for (let i = activeModel.count - 1; i >= 0; i--) {
                            if (activeModel.get(i).isPlaceholder) activeModel.remove(i);
                        }
                        for (let i = libraryModel.count - 1; i >= 0; i--) {
                            if (libraryModel.get(i).isPlaceholder) libraryModel.remove(i);
                        }
                        
                        activeDelegate.x = 0;
                        activeDelegate.y = 0;
                        save();
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
                        text: root.componentMeta[compId]?.icon || "application-x-executable"
                        color: sourceList !== "library" ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    }
                    
                    Text {
                        Layout.fillWidth: true
                        text: root.componentMeta[compId]?.name || "Unknown Component"
                        font: Tokens.font.body.small
                        color: sourceList !== "library" ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                    
                    TextButton {
                        visible: raw.type === "custom"
                        text: qsTr("Delete")
                        type: TextButton.Filled
                        z: 100
                        onClicked: {
                            if (sourceList === "active") activeModel.remove(index);
                            else libraryModel.remove(index);
                            root.save();
                        }
                    }

                    MaterialIcon {
                        text: "drag_indicator"
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

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
            }
        }
    }
}
