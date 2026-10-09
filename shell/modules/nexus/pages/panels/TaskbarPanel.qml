pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> positionItems: [
        MenuItem {
            property string value: "top"

            text: qsTr("Top")
        },
        MenuItem {
            property string value: "bottom"

            text: qsTr("Bottom")
        },
        MenuItem {
            property string value: "left"

            text: qsTr("Left")
        },
        MenuItem {
            property string value: "right"

            text: qsTr("Right")
        }
    ]

    readonly property list<MenuItem> useGlobalItems: [
        MenuItem {
            text: qsTr("Use global position")
            activeText: root.itemForPosition(GlobalConfig.bar.position).activeText
        }
    ]

    readonly property list<ShellScreen> perMonitorRows: {
        if (Screens.screens.length > 1)
            return Screens.screens;
        return Screens.screens.filter(s => GlobalConfig.forScreen(s.name).bar.overrides.includes("position"));
    }

    // Positions already used by the primary bar (global bar.position) AND existing overlay bars
    readonly property var occupiedPositions: (() => {
        const pos = [];
        if (GlobalConfig.bar.position)
            pos.push(GlobalConfig.bar.position);
        // Add positions from enabled overlay bars
        const overlayBars = GlobalConfig.bar.bars.values.filter(b => b && b.enabled !== false);
        for (let i = 0; i < overlayBars.length; i++) {
            const p = overlayBars[i].position || "bottom";
            if (!pos.includes(p))
                pos.push(p);
        }
        return pos;
    })()

    // Available positions for new overlay panels
    readonly property var availableOverlayPositions: root.positionItems.filter(item => !root.occupiedPositions.includes(item.value))

    function itemForPosition(pos: string): MenuItem {
        for (let i = 0; i < root.positionItems.length; i++) {
            if (root.positionItems[i].value === pos)
                return root.positionItems[i];
        }
        return root.positionItems[0];
    }

    function resetScreenPositionOverrides(): void {
        for (let i = 0; i < Quickshell.screens.length; i++)
            GlobalConfig.forScreen(Quickshell.screens[i].name).bar.resetOption("position");
    }

    function freePanelName(base: string): string {
        const taken = GlobalConfig.bar.bars.values.map(b => b.name);
        let name = base;
        let n = 1;
        while (taken.includes(name)) {
            n++;
            name = base + " " + n;
        }
        return name;
    }

    title: qsTr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Behavior")
        }

        ToggleRow {
            first: true
            text: qsTr("Persistent")
            subtext: qsTr("Keep the bar visible at all times")
            reset: ({ node: GlobalConfig.bar, setting: "persistent" })
            checked: GlobalConfig.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: qsTr("Dodge windows")
            subtext: qsTr("Retract the bar while a window covers it, and let windows sit underneath")
            enabled: GlobalConfig.bar.persistent
            reset: ({ node: GlobalConfig.bar, setting: "dodgeWindows" })
            checked: GlobalConfig.bar.dodgeWindows
            onToggled: GlobalConfig.bar.dodgeWindows = checked
        }

        ToggleRow {
            text: qsTr("Dodge focused window only")
            subtext: qsTr("Ignore background windows over the bar, and dodge only what you are using")
            enabled: GlobalConfig.bar.persistent && GlobalConfig.bar.dodgeWindows
            reset: ({ node: GlobalConfig.bar, setting: "dodgeFocusedOnly" })
            checked: GlobalConfig.bar.dodgeFocusedOnly
            onToggled: GlobalConfig.bar.dodgeFocusedOnly = checked
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Position")
            subtext: qsTr("Screen edge to place the bar on")
            active: root.itemForPosition(GlobalConfig.bar.position)
            menuItems: root.positionItems
            onSelected: item => {
                GlobalConfig.bar.position = item.value;
                root.resetScreenPositionOverrides();
            }
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the bar when the cursor reaches the screen edge")
            reset: ({ node: GlobalConfig.bar, setting: "showOnHover" })
            checked: GlobalConfig.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            reset: ({ node: GlobalConfig.bar, setting: "dragThreshold" })
            value: GlobalConfig.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        SectionHeader {
            visible: root.perMonitorRows.length > 0
            text: qsTr("Per-monitor position")
        }

        Repeater {
            id: perMonitorRepeater

            model: root.perMonitorRows

            SelectRow {
                required property var modelData
                required property int index

                readonly property var screenConfig: GlobalConfig.forScreen(modelData.name)
                readonly property bool hasOverride: screenConfig.bar.overrides.includes("position")

                first: index === 0
                last: index === perMonitorRepeater.count - 1
                Layout.fillWidth: true
                label: modelData.name
                subtext: hasOverride ? qsTr("Overridden for this monitor") : qsTr("Using global position")
                active: root.itemForPosition(screenConfig.bar.position)
                menuItems: hasOverride ? root.positionItems.concat(root.useGlobalItems) : root.positionItems
                onSelected: item => {
                    if (item === root.useGlobalItems[0])
                        screenConfig.bar.resetOption("position");
                    else
                        screenConfig.bar.position = item.value;
                }
            }
        }

        SectionHeader {
            text: qsTr("Extra panels")
        }

        ListEditor {
            function labelFor(item: var): string {
                return item.name || qsTr("Panel");
            }

            function toggledFor(item: var): bool {
                return item.enabled;
            }

            first: true
            allowEdit: true
            values: GlobalConfig.bar.bars.values
            onItemMoved: (from, to) => GlobalConfig.bar.bars.move(from, to)
            onItemRemoved: index => GlobalConfig.bar.bars.remove(index)
            onItemToggled: (index, checked) => GlobalConfig.bar.bars.at(index).enabled = checked
            onItemClicked: index => {
                root.nState.editingPanelIndex = index;
                root.nState.openSubPage(PageDictionary.subPageIdxFor("panels/taskbar/BarPanelEditor.qml"));
            }
        }

        DialogSelectButton {
            rootParent: root.flickable
            icon: "add"
            label: qsTr("Add panel")
            header: qsTr("Add new panel")
            acceptLabel: qsTr("Add")
            model: root.availableOverlayPositions.map(item => ({
                        id: item.value,
                        label: item.text
                    }))
            enabled: root.availableOverlayPositions.length > 0
            onAccepted: {
                if (selectedItem) {
                    const label = (root.positionItems.find(item => item.value === selectedItem) ?? root.positionItems[0]).text;
                    GlobalConfig.bar.bars.insert({
                        name: root.freePanelName(label + " " + qsTr("panel")),
                        position: selectedItem,
                        enabled: true,
                        entries: []
                    });
                }
            }
        }

        SectionHeader {
            text: qsTr("Scaling")
        }

        StepperRow {
            first: true
            label: qsTr("Bar scale")
            subtext: qsTr("Scales taskbar thickness and component sizing")
            reset: ({ node: GlobalConfig.bar, setting: "scale" })
            value: GlobalConfig.bar.scale
            from: 0.6
            to: 1.6
            stepSize: 0.05
            onMoved: v => GlobalConfig.bar.scale = v
        }

        StepperRow {
            label: qsTr("Preview scale")
            subtext: qsTr("Scales taskbar hover previews")
            reset: ({ node: GlobalConfig.bar, setting: "previewScale" })
            value: GlobalConfig.bar.previewScale
            from: 0.5
            to: 1.6
            stepSize: 0.05
            onMoved: v => GlobalConfig.bar.previewScale = v
        }

        ToggleRow {
            text: qsTr("Live window previews")
            subtext: qsTr("Live thumbnails in hover/overview/alt-tab. Disable if screen sharing or camera in other apps (e.g. Vesktop) freezes")
            reset: ({ node: GlobalConfig.bar, setting: "livePreviews" })
            checked: GlobalConfig.bar.livePreviews
            onToggled: GlobalConfig.bar.livePreviews = checked
        }

        ToggleRow {
            text: qsTr("Scale with bar size")
            subtext: qsTr("Multiply the preview scale with the bar scale")
            reset: ({ node: GlobalConfig.bar, setting: "previewScaleWithBar" })
            checked: GlobalConfig.bar.previewScaleWithBar
            onToggled: GlobalConfig.bar.previewScaleWithBar = checked
        }

        StepperRow {
            label: qsTr("Font scaling offset")
            subtext: qsTr("Scales the text size across taskbar popouts")
            reset: ({ node: GlobalConfig.bar, setting: "fontScaleOffset" })
            value: GlobalConfig.bar.fontScaleOffset
            from: -1.0; to: 1.0; stepSize: 0.05
            onMoved: v => GlobalConfig.bar.fontScaleOffset = v
        }

        NavRow {
            last: true
            icon: "aspect_ratio"
            label: qsTr("Per-element scaling offsets")
            status: qsTr("Customize scale and font for each popout type")
            onClicked: root.nState.openSubPage(14)
        }

        SectionHeader {
            text: qsTr("Components")
        }

        NavRow {
            first: true
            icon: "view_agenda"
            label: qsTr("Toggle & Rearrange")
            status: qsTr("Add, remove or reorder components")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            last: true
            icon: "tune"
            label: qsTr("Elements & Modules")
            status: qsTr("Workspaces, tray, status icons, clock, dock and more")
            onClicked: root.nState.openSubPage(15)
        }

        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            first: true
            text: qsTr("Workspaces")
            subtext: qsTr("Scroll over the workspace indicator to switch workspaces")
            reset: ({ node: GlobalConfig.bar.scrollActions, setting: "workspaces" })
            checked: GlobalConfig.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Scroll on the top half of the bar to adjust volume")
            reset: ({ node: GlobalConfig.bar.scrollActions, setting: "volume" })
            checked: GlobalConfig.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Brightness")
            subtext: qsTr("Scroll on the bottom half of the bar to adjust brightness")
            reset: ({ node: GlobalConfig.bar.scrollActions, setting: "brightness" })
            checked: GlobalConfig.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}
