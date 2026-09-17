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
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property var fonts: [
        { label: qsTr("San Francisco Pro"), family: "SF Pro", mono: false },
        { label: qsTr("Google Sans Flex"), family: "GoogleSansFlex", mono: false },
    ]

    property var monoFonts: [
        { label: qsTr("SF Mono"), family: "SF Mono", mono: true },
        { label: qsTr("CaskaydiaCove NF"), family: "CaskaydiaCove NF", mono: true },
    ]

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
            onClicked: Launch.exec(["bash", "-c", `bash "${Quickshell.shellPath("scripts/restart_shell.sh")}"; sleep 1; caelestia shell nexus openPage 0 8`])
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.padding.large
        }

        SectionHeader {
            first: true
            text: qsTr("Font")
        }

        Repeater {
            model: root.fonts

            FontCard {}
        }

        SectionHeader {
            text: qsTr("Monospace font")
        }

        Repeater {
            model: root.monoFonts

            FontCard {}
        }

        ColumnLayout {
            id: bbdxContainer

            property bool isBbdxEnabled: false

            spacing: 0

            ToggleRow {
                first: true
                text: qsTr("Bezel mode (Pitch black)")
                subtext: qsTr("Make the shell pitch black to blend with display bezels")
                checked: GlobalConfig.appearance.pitchBlack
                onToggled: GlobalConfig.appearance.pitchBlack = checked
                Layout.fillWidth: true
            }
            ToggleRow {
                text: qsTr("Islands")
                subtext: qsTr("Everything appears as its own floating widget (Very Experimental)")
                checked: GlobalConfig.appearance.islands
                onToggled: GlobalConfig.appearance.islands = checked
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
            }
            StepperRow {
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
            SliderRow {
                label: qsTr("Base opacity")
                valueLabel: Math.round(value * 100) + "%"
                value: GlobalConfig.appearance.transparency.base
                enabled: GlobalConfig.appearance.transparency.enabled
                onMoved: v => GlobalConfig.appearance.transparency.base = v
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            SliderRow {
                label: qsTr("Layers opacity")
                subtext: qsTr("Requires shell restart")
                valueLabel: Math.round(value * 100) + "%"
                value: GlobalConfig.appearance.transparency.layers
                enabled: GlobalConfig.appearance.transparency.enabled
                onMoved: v => GlobalConfig.appearance.transparency.layers = v
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            }
            ToggleRow {
                text: qsTr("Ambient color mode")
                subtext: qsTr("YouTube-style ambient light glow on window previews and popups")
                checked: GlobalConfig.appearance.ambientColor
                onToggled: GlobalConfig.appearance.ambientColor = checked
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
            }
            SliderRow {
                label: qsTr("Ambient glow opacity")
                valueLabel: Math.round(value * 100) + "%"
                value: GlobalConfig.appearance.ambientOpacity
                enabled: GlobalConfig.appearance.ambientColor
                onMoved: v => GlobalConfig.appearance.ambientOpacity = v
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

                command: ["bash", "-c", `
                    IS_ENABLED=$(kreadconfig6 --file kwinrc --group Plugins --key better_blur_dxEnabled)
                    if [ "$IS_ENABLED" = "true" ]; then
                        BLUR_MATCHING=$(kreadconfig6 --file kwinrc --group Effect-better-blur-dx --key BlurMatching)
                        BLUR_NON_MATCHING=$(kreadconfig6 --file kwinrc --group Effect-better-blur-dx --key BlurNonMatching)
                        WINDOW_CLASSES=$(kreadconfig6 --file kwinrc --group Effect-better-blur-dx --key WindowClasses)
                        if [ -z "$BLUR_MATCHING" ]; then BLUR_MATCHING="true"; fi
                        if [ -z "$BLUR_NON_MATCHING" ]; then BLUR_NON_MATCHING="false"; fi
                        MODIFIED=false
                        if [ "$BLUR_MATCHING" = "true" ] && [ "$BLUR_NON_MATCHING" = "false" ]; then
                            if echo "$WINDOW_CLASSES" | grep -q '\\bquickshell\\b'; then
                                NEW_CLASSES=$(echo "$WINDOW_CLASSES" | sed -E 's/\\bquickshell\\b//g' | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
                                kwriteconfig6 --file kwinrc --group Effect-better-blur-dx --key WindowClasses "$NEW_CLASSES"
                                MODIFIED=true
                            fi
                        elif [ "$BLUR_MATCHING" = "false" ] && [ "$BLUR_NON_MATCHING" = "true" ]; then
                            if ! echo "$WINDOW_CLASSES" | grep -q '\\bquickshell\\b'; then
                                if [ -z "$WINDOW_CLASSES" ]; then
                                    NEW_CLASSES="quickshell"
                                elif echo "$WINDOW_CLASSES" | grep -q ','; then
                                    NEW_CLASSES="$WINDOW_CLASSES,quickshell"
                                else
                                    NEW_CLASSES="$WINDOW_CLASSES"$'\n'"quickshell"
                                fi
                                kwriteconfig6 --file kwinrc --group Effect-better-blur-dx --key WindowClasses "$NEW_CLASSES"
                                MODIFIED=true
                            fi
                        fi
                        if [ "$MODIFIED" = "true" ]; then
                            qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
                            qdbus6 org.kde.KWin /Effects reconfigureEffect better_blur_dx 2>/dev/null || true
                        fi
                    fi
                `]
            }
            ToggleRow {
                text: qsTr("Background Blur")
                subtext: parent.isBbdxEnabled ? qsTr("Disabling has no effect if Better Blur dx is enabled") : qsTr("Enable a frosted glass effect by blurring the background")
                checked: parent.isBbdxEnabled ? true : GlobalConfig.appearance.blur
                enabled: GlobalConfig.appearance.transparency.enabled && !parent.isBbdxEnabled
                onToggled: {
                    bbdxFixProcess.running = true;
                    GlobalConfig.appearance.blur = checked
                    if (GlobalConfig.appearance.transparency.enabled && checked) {
                        // Hack to force Quickshell blur region to update when enabling blur
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

            StepperRow {
                first: true
                Layout.fillWidth: true
                label: qsTr("Font scale")
                value: GlobalConfig.appearance.font.scale
                from: 0.5
                to: 2
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.font.scale = v
            }

            StepperRow {
                Layout.fillWidth: true
                label: qsTr("Spacing scale")
                value: GlobalConfig.appearance.spacing.scale
                from: 0.5
                to: 2
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.spacing.scale = v
            }

            StepperRow {
                Layout.fillWidth: true
                label: qsTr("Padding scale")
                value: GlobalConfig.appearance.padding.scale
                from: 0.5
                to: 2
                stepSize: 0.05
                onMoved: v => GlobalConfig.appearance.padding.scale = v
            }

            StepperRow {
                last: true
                Layout.fillWidth: true
                label: qsTr("Animation speed scale")
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
                Layout.fillWidth: true
                label: qsTr("Border smoothing")
                value: GlobalConfig.border.smoothing
                from: 0
                to: 100
                stepSize: 1
                onMoved: v => GlobalConfig.border.smoothing = v
            }

            StepperRow {
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

    component FontCard: StyledRect {
        id: fontCard

        required property var modelData

        readonly property bool selected: modelData.mono
            ? GlobalConfig.appearance.font.mono.family === modelData.family
            : GlobalConfig.appearance.font.body.family === modelData.family

        Layout.fillWidth: true
        implicitHeight: fontRow.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        border.width: selected ? 2 : 1
        border.color: selected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

        StateLayer {
            radius: parent.radius
            onClicked: fontCard.modelData.mono ? root.applyMonoFont(fontCard.modelData.family) : root.applyFont(fontCard.modelData.family)
        }

        RowLayout {
            id: fontRow

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.large

            StyledText {
                Layout.fillWidth: true
                text: fontCard.modelData.label
                font: Tokens.font.body.medium
                color: fontCard.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                visible: fontCard.selected
                text: "check"
                color: Colours.palette.m3onSecondaryContainer
                fontStyle: Tokens.font.icon.large
            }
        }
    }
}
