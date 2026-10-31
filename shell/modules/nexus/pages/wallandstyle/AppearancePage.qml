pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.launcher.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var fontFamilies: {
        const families = Qt.fontFamilies();
        families.sort((a, b) => a.localeCompare(b));
        return families;
    }

    readonly property var fontPresets: [
        { label: qsTr("Follow system"), value: "" },
        { label: "Google Sans Flex", value: "GoogleSansFlex" },
        { label: "Rubik", value: "Rubik" }
    ]

    readonly property var monoPresets: [
        { label: qsTr("Follow system"), value: "" },
        { label: "CaskaydiaCove NF", value: "CaskaydiaCove NF" },
        { label: "JetBrainsMono Nerd Font", value: "JetBrainsMono Nerd Font" }
    ]

    readonly property var fontMenuModel: root.menuModel(root.fontPresets, GlobalConfig.appearance.font.body.family)
    readonly property var monoMenuModel: root.menuModel(root.monoPresets, GlobalConfig.appearance.font.mono.family)
    readonly property string fontLabel: root.labelFor(root.fontMenuModel, GlobalConfig.appearance.font.body.family)
    readonly property string monoLabel: root.labelFor(root.monoMenuModel, GlobalConfig.appearance.font.mono.family)

    function menuModel(presets: var, current: string): var {
        const items = [];
        if (current && !presets.some(p => p.value === current))
            items.push({ label: current, value: current });
        items.push(...presets);
        items.push({ label: qsTr("Choose system font…"), value: "__pick__" });
        return items;
    }

    function labelFor(items: var, current: string): string {
        const item = items.find(i => i.value === current);
        return item ? item.label : (current || qsTr("Follow system"));
    }

    function applyFont(family: string): void {
        GlobalConfig.appearance.font.headline.family = family;
        GlobalConfig.appearance.font.title.family = family;
        GlobalConfig.appearance.font.body.family = family;
        GlobalConfig.appearance.font.label.family = family;
    }

    function applyMonoFont(family: string): void {
        GlobalConfig.appearance.font.mono.family = family;
    }

    isSubPage: true
    title: qsTr("Theme & Effects")

    headerActions: [
        IconTextButton {
            text: qsTr("Restart Shell")
            icon: "restart_alt"
            type: TextButton.Filled
            onClicked: Launch.exec(["bash", "-c", `bash "${Quickshell.shellPath("scripts/restart_shell.sh")}"; sleep 1; caelestia shell nexus openPage ${PageDictionary.pageIdxFor("appearance")} 8`])
        },
        IconTextButton {
            id: resetBtn

            property bool armed: false
            readonly property bool dirty: {
                const nodes = [GlobalConfig.appearance, GlobalConfig.border, GlobalConfig.appearance.rounding, GlobalConfig.appearance.transparency, GlobalConfig.appearance.font, GlobalConfig.appearance.spacing, GlobalConfig.appearance.padding, GlobalConfig.appearance.anim.durations];
                return nodes.some(n => n.overrides.length > 0);
            }

            text: resetBtn.armed ? qsTr("Sure?") : qsTr("Reset settings")
            icon: "restart_alt"
            type: resetBtn.dirty ? TextButton.Filled : TextButton.Tonal
            enabled: resetBtn.dirty || resetBtn.armed
            onClicked: {
                if (resetBtn.armed) {
                    resetBtn.armed = false;
                    resetArmTimer.stop();
                    GlobalConfig.resetOption("appearance");
                    GlobalConfig.resetOption("border");
                } else {
                    resetBtn.armed = true;
                    resetArmTimer.start();
                }
            }

            Timer {
                id: resetArmTimer

                interval: 3000
                onTriggered: resetBtn.armed = false
            }
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        SectionHeader {
            first: true
            text: qsTr("Font")
        }

        Variants {
            id: fontVariants

            model: root.fontMenuModel

            MenuItem {
                required property var modelData

                text: modelData.label
                value: modelData.value
                icon: modelData.value === "__pick__" ? "search" : "font_download"
            }
        }

        SelectRow {
            first: true
            label: qsTr("Font")
            subtext: qsTr("Used by every text style in the shell")
            menuItems: fontVariants.instances
            active: menuItems.find(i => i.value === GlobalConfig.appearance.font.body.family) ?? null
            fallbackText: root.fontLabel
            onSelected: item => {
                if (item.value === "__pick__")
                    fontPicker.open = true;
                else
                    root.applyFont(item.value);
            }
        }

        FontPickerRow {
            id: fontPicker

            visible: false
        }

        SectionHeader {
            text: qsTr("Monospace font")
        }

        Variants {
            id: monoVariants

            model: root.monoMenuModel

            MenuItem {
                required property var modelData

                text: modelData.label
                value: modelData.value
                icon: modelData.value === "__pick__" ? "search" : "font_download"
            }
        }

        SelectRow {
            first: true
            last: true
            label: qsTr("Monospace font")
            subtext: qsTr("Used by code, terminal previews and fixed width labels")
            menuItems: monoVariants.instances
            active: menuItems.find(i => i.value === GlobalConfig.appearance.font.mono.family) ?? null
            fallbackText: root.monoLabel
            onSelected: item => {
                if (item.value === "__pick__")
                    monoPicker.open = true;
                else
                    root.applyMonoFont(item.value);
            }
        }

        FontPickerRow {
            id: monoPicker

            visible: false
            mono: true
        }

        SectionHeader {
            text: qsTr("Theme")
        }

        ColumnLayout {
            id: bbdxContainer

            property bool isBbdxEnabled: false

            spacing: 0

            ToggleRow {
                reset: ({ node: GlobalConfig.appearance, setting: "pitchBlack" })
                first: true
                text: qsTr("Bezel mode (Pitch black)")
                subtext: qsTr("Make the shell pitch black to blend with display bezels")
                checked: GlobalConfig.appearance.pitchBlack
                onToggled: GlobalConfig.appearance.pitchBlack = checked
                Layout.fillWidth: true
            }
            ToggleRow {
                reset: ({ node: GlobalConfig.appearance, setting: "islands" })
                text: qsTr("Islands")
                subtext: qsTr("Everything appears as its own floating widget (Very Experimental)")
                checked: GlobalConfig.appearance.islands
                onToggled: GlobalConfig.appearance.islands = checked
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
            }
            StepperRow {
                reset: ({ node: GlobalConfig.border, setting: "thickness" })
                label: qsTr("Border thickness")
                subtext: qsTr("Thickness of the shell border in pixels. Set to 0 for a borderless look")
                value: GlobalConfig.border.thickness
                from: 0
                to: 50
                stepSize: 1
                onMoved: v => GlobalConfig.border.thickness = v
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            StepperRow {
                reset: ({ node: GlobalConfig.appearance.rounding, setting: "scale" })
                label: qsTr("Corner radius scale")
                subtext: qsTr("Multiplies the shell's corner rounding")
                value: GlobalConfig.appearance.rounding.scale
                from: 0.5
                to: 2.0
                stepSize: 0.1
                onMoved: v => GlobalConfig.appearance.rounding.scale = v
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            ToggleRow {
                reset: ({ node: GlobalConfig.appearance.transparency, setting: "enabled" })
                text: qsTr("Transparency")
                subtext: qsTr("Enable transparency across the shell")
                checked: GlobalConfig.appearance.transparency.enabled
                onToggled: {
                    GlobalConfig.appearance.transparency.enabled = checked
                    if (!checked) {
                        GlobalConfig.appearance.blur = false
                    }
                }
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
            }
            StepperRow {
                reset: ({ node: GlobalConfig.appearance.transparency, setting: "base" })
                label: qsTr("Base opacity")
                value: GlobalConfig.appearance.transparency.base
                from: 0.0
                to: 1.0
                stepSize: 0.05
                enabled: GlobalConfig.appearance.transparency.enabled
                onMoved: v => GlobalConfig.appearance.transparency.base = v
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            StepperRow {
                reset: ({ node: GlobalConfig.appearance.transparency, setting: "layers" })
                label: qsTr("Layers opacity")
                subtext: qsTr("Requires shell restart")
                value: GlobalConfig.appearance.transparency.layers
                from: 0.0
                to: 1.0
                stepSize: 0.05
                enabled: GlobalConfig.appearance.transparency.enabled
                onMoved: v => GlobalConfig.appearance.transparency.layers = v
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            Process {
                id: bbdxCheck

                command: ["bash", "-c", "kreadconfig6 --file kwinrc --group Plugins --key better_blur_dxEnabled"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: bbdxContainer.isBbdxEnabled = text.trim() === "true"
                }
            }
            Process {
                id: bbdxFixProcess

                command: ["bash", Quickshell.shellDir + "/scripts/bbdx-window-classes.sh"]
            }
            ToggleRow {
                reset: ({ node: GlobalConfig.appearance, setting: "blur" })
                text: qsTr("Background Blur")
                subtext: parent.isBbdxEnabled ? qsTr("Disabling has no effect if Better Blur dx is enabled") : qsTr("Enable a frosted glass effect by blurring the background")
                checked: parent.isBbdxEnabled ? true : GlobalConfig.appearance.blur
                enabled: GlobalConfig.appearance.transparency.enabled && !parent.isBbdxEnabled
                onToggled: {
                    bbdxFixProcess.running = true;
                    GlobalConfig.appearance.blur = checked
                    if (GlobalConfig.appearance.transparency.enabled && checked) {
                        GlobalConfig.appearance.transparency.enabled = false
                        blurHackTimer.start()
                    }
                }

                Timer {
                    id: blurHackTimer

                    interval: 50
                    onTriggered: GlobalConfig.appearance.transparency.enabled = true
                }
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
            }
            ToggleRow {
                reset: ({ node: GlobalConfig.appearance, setting: "blurMask" })
                text: qsTr("High Quality Blur Masks")
                subtext: qsTr("Disable this to use high performance Wayland/KWin blur")
                checked: GlobalConfig.appearance.blurMask
                enabled: GlobalConfig.appearance.transparency.enabled && GlobalConfig.appearance.blur
                onToggled: GlobalConfig.appearance.blurMask = checked
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
            }
            Settings {
                id: blurSettings

                property int blurQuality: 20

                category: "Blur"
            }
            StepperRow {
                last: true
                reset: ({
                    customGet: () => blurSettings.blurQuality,
                    customSet: v => blurSettings.blurQuality = v,
                    customDef: 20
                })
                label: qsTr("Blur Corner Quality")
                subtext: qsTr("Increasing this can cause lags! Requires shell restart")
                value: blurSettings.blurQuality
                enabled: GlobalConfig.appearance.transparency.enabled && GlobalConfig.appearance.blur
                from: 1
                to: 100
                stepSize: 1
                onMoved: v => blurSettings.blurQuality = Math.round(v)
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            Layout.fillWidth: true
        }

        SectionHeader {
            text: qsTr("Scaling")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                first: true
                Layout.fillWidth: true
                text: qsTr("Follow system text size")
                subtext: qsTr("Match the text size set in KDE's settings")
                reset: ({ node: GlobalConfig.appearance.font, setting: "followSystemScale" })
                checked: GlobalConfig.appearance.font.followSystemScale
                onToggled: {
                    GlobalConfig.appearance.font.followSystemScale = checked;
                    GlobalConfig.save();
                }
            }

            StepperRow {
                reset: ({ node: GlobalConfig.appearance.font, setting: "scale" })
                Layout.fillWidth: true
                label: qsTr("Font scale")
                value: GlobalConfig.appearance.font.scale
                from: 0.5
                to: 2
                stepSize: 0.05
                onMoved: v => {
                    GlobalConfig.appearance.font.scale = v;
                    GlobalConfig.appearance.font.followSystemScale = false;
                    GlobalConfig.save();
                }
            }

            StepperRow {
                reset: ({ node: GlobalConfig.appearance.spacing, setting: "scale" })
                Layout.fillWidth: true
                label: qsTr("Spacing scale")
                value: GlobalConfig.appearance.spacing.scale
                from: 0.5
                to: 2
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.spacing.scale = v
            }

            StepperRow {
                last: true
                reset: ({ node: GlobalConfig.appearance.padding, setting: "scale" })
                Layout.fillWidth: true
                label: qsTr("Padding scale")
                value: GlobalConfig.appearance.padding.scale
                from: 0.5
                to: 2
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.padding.scale = v
            }
        }

        SectionHeader {
            text: qsTr("Animations")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                first: true
                Layout.fillWidth: true
                reset: ({ node: GlobalConfig.appearance.anim, setting: "enabled" })
                text: qsTr("Enable animations")
                subtext: qsTr("Toggle fluid animations across the shell")
                checked: GlobalConfig.appearance.anim.enabled
                onToggled: GlobalConfig.appearance.anim.enabled = checked
            }

            SelectRow {
                Layout.fillWidth: true
                enabled: GlobalConfig.appearance.anim.enabled
                label: qsTr("Animation preset")
                subtext: qsTr("Motion curves and timing profile")
                fallbackText: Animations.currentName
                fallbackIcon: "animation"
                menuItems: Animations.menuItems
                active: {
                    const items = Animations.menuItems || [];
                    for (let i = 0; i < items.length; i++) {
                        if (items[i].value === Animations.currentPath || items[i].text === Animations.currentName)
                            return items[i];
                    }
                    return items[0] || null;
                }
                onSelected: item => {
                    if (item && item.value !== undefined) {
                        Animations.applyPreset(item.value, item.text);
                    }
                }
            }

            StepperRow {
                last: true
                reset: ({ node: GlobalConfig.appearance.anim.durations, setting: "scale" })
                Layout.fillWidth: true
                enabled: GlobalConfig.appearance.anim.enabled
                label: qsTr("Animation speed scale")
                subtext: qsTr("Speed multiplier applied to all animation durations")
                value: GlobalConfig.appearance.anim.durations.scale
                from: 0.25
                to: 4
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.anim.durations.scale = v
            }
        }

        SectionHeader {
            text: qsTr("Corners & effects")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StepperRow {
                reset: ({ node: GlobalConfig.border, setting: "rounding" })
                first: true
                Layout.fillWidth: true
                label: qsTr("Border rounding")
                value: GlobalConfig.border.rounding
                from: 0
                to: 100
                stepSize: 1
                onMoved: v => GlobalConfig.border.rounding = v
            }

            StepperRow {
                reset: ({ node: GlobalConfig.border, setting: "smoothing" })
                Layout.fillWidth: true
                label: qsTr("Border smoothing")
                value: GlobalConfig.border.smoothing
                from: 0
                to: 100
                stepSize: 1
                onMoved: v => GlobalConfig.border.smoothing = v
            }

            StepperRow {
                reset: ({ node: GlobalConfig.appearance, setting: "deformScale" })
                last: true
                Layout.fillWidth: true
                label: qsTr("Blur deform")
                value: GlobalConfig.appearance.deformScale
                from: 0
                to: 1.5
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.deformScale = v
            }
        }
    }

    component FontPickerRow: DialogRowButton {
        id: picker

        property bool mono: false
        property var selectedItem: null

        rootParent: root.flickable
        icon: "font_download"
        label: qsTr("Choose a system font")
        header: picker.mono ? qsTr("Monospace fonts") : qsTr("System fonts")
        acceptLabel: qsTr("Apply")
        acceptAllowed: !!picker.selectedItem
        separateContent: true
        horizontalContentMargin: -Tokens.padding.small

        onOpenChanged: {
            if (open)
                picker.selectedItem = null;
        }

        onAccepted: {
            if (!picker.selectedItem)
                return;
            if (picker.mono)
                root.applyMonoFont(picker.selectedItem);
            else
                root.applyFont(picker.selectedItem);
            picker.selectedItem = null;
        }

        content: Component {
            VerticalFadeListView {
                spacing: 0
                topMargin: Tokens.padding.large
                bottomMargin: Tokens.padding.large

                model: root.fontFamilies

                delegate: StyledRect {
                    id: fontItem

                    required property string modelData

                    readonly property bool selected: picker.selectedItem === fontItem.modelData

                    anchors.left: ListView.view.contentItem.left
                    anchors.right: ListView.view.contentItem.right
                    anchors.margins: 1
                    implicitHeight: fontLabel.implicitHeight + Tokens.padding.medium * 2
                    radius: stateLayer.pressed ? Tokens.rounding.extraSmall : selected ? Tokens.rounding.largeIncreased : Tokens.rounding.medium
                    color: Qt.alpha(Colours.palette.m3tertiaryContainer, selected ? 1 : 0)

                    StateLayer {
                        id: stateLayer

                        anchors.fill: parent
                        radius: parent.radius

                        onClicked: picker.selectedItem = fontItem.modelData
                    }

                    StyledText {
                        id: fontLabel

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        text: fontItem.modelData
                        font.family: fontItem.modelData
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
