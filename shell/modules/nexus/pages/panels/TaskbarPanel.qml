pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.utils
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

    // Whether any connected screen carries a per-monitor position override.
    // The per-monitor section stays visible while this is true, so an
    // override can never end up hidden on a single-monitor setup.
    readonly property bool hasPositionOverrides: {
        let overridden = false;
        for (let i = 0; i < Screens.screens.length; i++) {
            const screenConfig = GlobalConfig.forScreen(Screens.screens[i].name);
            if (screenConfig && screenConfig.bar.isOverride("position")) {
                overridden = true;
                break;
            }
        }
        return overridden;
    }

    function itemForPosition(pos: string): MenuItem {
        for (let i = 0; i < root.positionItems.length; i++) {
            if (root.positionItems[i].value === pos)
                return root.positionItems[i];
        }
        return root.positionItems[0];
    }

    // Choosing a global position is authoritative: drop every per-monitor
    // position override so all connected monitors follow the global edge
    // again, mirroring how the desktop page applies its global toggles.
    function resetScreenPositionOverrides(): void {
        for (let i = 0; i < Screens.screens.length; i++) {
            const screenConfig = GlobalConfig.forScreen(Screens.screens[i].name);
            if (screenConfig)
                screenConfig.bar.resetOption("position");
        }
    }

    title: qsTr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: qsTr("Behavior")
        }

        ToggleRow {
            first: true
            text: qsTr("Persistent")
            subtext: qsTr("Keep the bar visible at all times")
            checked: GlobalConfig.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: qsTr("Dodge windows")
            subtext: qsTr("Retract the bar while a window covers it, and let windows sit underneath")
            enabled: GlobalConfig.bar.persistent
            checked: GlobalConfig.bar.dodgeWindows
            onToggled: GlobalConfig.bar.dodgeWindows = checked
        }

        ToggleRow {
            text: qsTr("Dodge focused window only")
            subtext: qsTr("Ignore background windows over the bar, and dodge only what you are using")
            enabled: GlobalConfig.bar.persistent && GlobalConfig.bar.dodgeWindows
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
            checked: GlobalConfig.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            value: GlobalConfig.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        SectionHeader {
            visible: Screens.screens.length > 1 || root.hasPositionOverrides
            text: qsTr("Per-monitor position")
        }

        Repeater {
            id: perMonitorRepeater

            model: Screens.screens.length > 1 || root.hasPositionOverrides ? Screens.screens : []

            SelectRow {
                required property var modelData
                required property int index

                readonly property var screenConfig: GlobalConfig.forScreen(modelData.name)
                readonly property bool hasOverride: screenConfig ? screenConfig.bar.isOverride("position") : false

                first: index === 0
                last: index === perMonitorRepeater.count - 1
                Layout.fillWidth: true
                label: modelData.name
                subtext: hasOverride ? qsTr("Overridden for this monitor") : qsTr("Using global position")
                active: root.itemForPosition(screenConfig ? screenConfig.bar.position : GlobalConfig.bar.position)
                menuItems: hasOverride ? root.positionItems.concat(root.useGlobalItems) : root.positionItems
                onSelected: item => {
                    if (!screenConfig)
                        return;
                    if (item === root.useGlobalItems[0])
                        screenConfig.bar.resetOption("position");
                    else
                        screenConfig.bar.position = item.value;
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
            value: GlobalConfig.bar.scale
            from: 0.6
            to: 1.6
            stepSize: 0.05
            onMoved: v => GlobalConfig.bar.scale = v
        }

        StepperRow {
            label: qsTr("Preview scale")
            subtext: qsTr("Scales taskbar hover previews")
            value: GlobalConfig.bar.previewScale
            from: 0.5
            to: 1.6
            stepSize: 0.05
            onMoved: v => GlobalConfig.bar.previewScale = v
        }

        ToggleRow {
            text: qsTr("Live window previews")
            subtext: qsTr("Live thumbnails in hover/overview/alt-tab. Disable if screen sharing or camera in other apps (e.g. Vesktop) freezes")
            checked: GlobalConfig.bar.livePreviews
            onToggled: GlobalConfig.bar.livePreviews = checked
        }

        ToggleRow {
            text: qsTr("Scale with bar size")
            subtext: qsTr("Multiply the preview scale with the bar scale")
            checked: GlobalConfig.bar.previewScaleWithBar
            onToggled: GlobalConfig.bar.previewScaleWithBar = checked
        }

        StepperRow {
            label: qsTr("Font scaling offset")
            subtext: qsTr("Scales the text size across taskbar popouts")
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

        // Components
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

        // Scroll actions
        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            first: true
            text: qsTr("Workspaces")
            subtext: qsTr("Scroll over the workspace indicator to switch workspaces")
            checked: GlobalConfig.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Scroll on the top half of the bar to adjust volume")
            checked: GlobalConfig.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Brightness")
            subtext: qsTr("Scroll on the bottom half of the bar to adjust brightness")
            checked: GlobalConfig.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}
