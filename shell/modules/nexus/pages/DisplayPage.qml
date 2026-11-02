pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> scaleItems: [
        MenuItem {
            text: "100%"
            value: "1"
        },
        MenuItem {
            text: "125%"
            value: "1.25"
        },
        MenuItem {
            text: "150%"
            value: "1.5"
        },
        MenuItem {
            text: "160%"
            value: "1.6"
        },
        MenuItem {
            text: "170%"
            value: "1.7"
        },
        MenuItem {
            text: "175%"
            value: "1.75"
        },
        MenuItem {
            text: "200%"
            value: "2"
        },
        MenuItem {
            text: "250%"
            value: "2.5"
        },
        MenuItem {
            text: "300%"
            value: "3"
        }
    ]

    readonly property list<MenuItem> rotationItems: [
        MenuItem {
            text: qsTr("Normal")
            value: 1
        },
        MenuItem {
            text: qsTr("Left")
            value: 2
        },
        MenuItem {
            text: qsTr("Upside down")
            value: 4
        },
        MenuItem {
            text: qsTr("Right")
            value: 8
        }
    ]

    /// A scale or rotation the menu does not list leaves `active` empty on purpose: the
    /// button then shows what the screen really is instead of the nearest preset.
    function scaleItem(output: var): MenuItem {
        const value = String(output.scale);
        return root.scaleItems.find(item => item.value === value) ?? null;
    }

    function rotationItem(output: var): MenuItem {
        return root.rotationItems.find(item => item.value === output.rotation) ?? null;
    }

    function currentModeLabel(output: var): string {
        const mode = Displays.modesFor(output).find(candidate => String(candidate.id) === String(output.currentModeId));
        return mode ? Displays.modeLabel(mode) : qsTr("Unknown mode");
    }

    title: qsTr("Displays")

    // The layout can be changed from System Settings while Nexus is closed, so the page
    // asks KScreen again when it is shown instead of trusting what it read last time.
    Component.onCompleted: Displays.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            visible: !Displays.available
            text: qsTr("This machine has no kscreen-doctor, so the shell can neither read nor change the screen setup. Install Plasma's kscreen package to manage displays here.")
            color: Colours.palette.m3onSurfaceVariant
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }

        Repeater {
            model: Displays.connected

            delegate: ColumnLayout {
                id: outputSection

                required property var modelData
                required property int index

                readonly property var output: outputSection.modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: index === 0
                    text: outputSection.output.enabled ? outputSection.output.name : qsTr("%1 (off)").arg(outputSection.output.name)
                }

                ToggleRow {
                    first: true
                    text: qsTr("Enabled")
                    subtext: Displays.enabled.length > 1 || !outputSection.output.enabled ? qsTr("Drives a picture for this screen") : qsTr("The last enabled screen has to stay on")
                    checked: outputSection.output.enabled
                    enabled: Displays.enabled.length > 1 || !outputSection.output.enabled
                    onToggled: Displays.setEnabled(outputSection.output.name, checked)
                }

                NavRow {
                    icon: "aspect_ratio"
                    label: qsTr("Resolution & refresh rate")
                    status: root.currentModeLabel(outputSection.output)
                    onClicked: {
                        root.nState.selectedOutput = outputSection.output.name;
                        root.nState.openSubPage(1);
                    }
                }

                SelectRow {
                    label: qsTr("Scale")
                    subtext: qsTr("How large everything is drawn")
                    menuItems: root.scaleItems
                    active: root.scaleItem(outputSection.output)
                    fallbackText: `${Math.round(outputSection.output.scale * 100)}%`
                    onSelected: item => Displays.setScale(outputSection.output.name, Number(item.value))
                }

                SelectRow {
                    label: qsTr("Rotation")
                    subtext: qsTr("Turn the picture to match how the screen stands")
                    menuItems: root.rotationItems
                    active: root.rotationItem(outputSection.output)
                    fallbackText: Displays.rotationName(outputSection.output.rotation)
                    last: !Displays.supportsHdr(outputSection.output)
                    onSelected: item => Displays.setRotation(outputSection.output.name, item.value)
                }

                ToggleRow {
                    last: true
                    visible: Displays.supportsHdr(outputSection.output)
                    text: qsTr("HDR")
                    subtext: qsTr("High dynamic range, and the wide colour gamut that goes with it")
                    checked: outputSection.output.hdr
                    onToggled: Displays.setHdr(outputSection.output.name, checked)
                }
            }
        }

        SectionHeader {
            text: qsTr("Input")
        }

        NavRow {
            first: true
            icon: "mouse"
            label: qsTr("Mouse & touchpad")
            status: qsTr("Speed, tap to click, natural scrolling")
            onClicked: Launch.kcm("kcm_touchpad")
        }

        NavRow {
            last: true
            icon: "keyboard"
            label: qsTr("Keyboard")
            status: qsTr("Repeat rate, layouts, advanced settings")
            onClicked: Launch.kcm("kcm_keyboard")
        }
    }
}
