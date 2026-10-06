pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> positionItems: [
        MenuItem {
            property string value: "top-left"

            text: qsTr("Top left")
        },
        MenuItem {
            property string value: "top-center"

            text: qsTr("Top center")
        },
        MenuItem {
            property string value: "top-right"

            text: qsTr("Top right")
        },
        MenuItem {
            property string value: "center"

            text: qsTr("Center")
        },
        MenuItem {
            property string value: "bottom-left"

            text: qsTr("Bottom left")
        },
        MenuItem {
            property string value: "bottom-center"

            text: qsTr("Bottom center")
        },
        MenuItem {
            property string value: "bottom-right"

            text: qsTr("Bottom right")
        }
    ]

    readonly property list<MenuItem> alignmentItems: [
        MenuItem {
            property int value: 0

            text: qsTr("Left")
        },
        MenuItem {
            property int value: 1

            text: qsTr("Center")
        },
        MenuItem {
            property int value: 2

            text: qsTr("Right")
        }
    ]

    isSubPage: true
    title: qsTr("Desktop Addons")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.padding.large
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                Layout.fillWidth: true
                first: true
                text: qsTr("Desktop clock")
                checked: Config.background.desktopClock.enabled
                onToggled: GlobalConfig.background.desktopClock.enabled = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                text: qsTr("Desktop media shapes")
                checked: Config.background.desktopShapes.enabled
                onToggled: {
                    GlobalConfig.background.desktopShapes.enabled = checked;
                    if (!checked)
                        GlobalConfig.background.desktopShapes.autoHide = false;
                }
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                visible: Config.background.desktopShapes.enabled
                text: qsTr("Auto-hide media shapes")
                subtext: qsTr("Hide media shapes when a window is open")
                checked: Config.background.desktopShapes.autoHide
                onToggled: GlobalConfig.background.desktopShapes.autoHide = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                text: qsTr("Desktop lyrics")
                checked: Config.background.desktopLyrics.enabled
                onToggled: {
                    GlobalConfig.background.desktopLyrics.enabled = checked;
                    if (!checked)
                        GlobalConfig.background.desktopLyrics.autoHide = false;
                }
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                visible: Config.background.desktopLyrics.enabled
                text: qsTr("Auto-hide lyrics")
                subtext: qsTr("Hide lyrics when a window is open")
                checked: Config.background.desktopLyrics.autoHide
                onToggled: GlobalConfig.background.desktopLyrics.autoHide = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                last: !Config.background.visualiser.enabled
                text: qsTr("Background visualiser")
                subtext: qsTr("Show music visualiser on wallpaper (May consume more power)")
                checked: Config.background.visualiser.enabled
                onToggled: {
                    GlobalConfig.background.visualiser.enabled = checked;
                    if (!checked)
                        GlobalConfig.background.visualiser.autoHide = false;
                }
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                visible: Config.background.visualiser.enabled
                text: qsTr("Auto-hide visualiser")
                subtext: qsTr("Hide visualiser when a window is fullscreen")
                checked: Config.background.visualiser.autoHide
                onToggled: GlobalConfig.background.visualiser.autoHide = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                last: true
                visible: Config.background.visualiser.enabled
                text: qsTr("Hide on all monitors")
                subtext: qsTr("Also hide on all other monitors if disabled by a window")
                checked: Config.background.visualiser.hideOnAllMonitors
                enabled: Config.background.visualiser.autoHide
                onToggled: GlobalConfig.background.visualiser.hideOnAllMonitors = checked
            }
        }

        SectionHeader {
            text: qsTr("Desktop clock")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StepperRow {
                first: true
                Layout.fillWidth: true
                label: qsTr("Scale")
                value: Config.background.desktopClock.scale
                from: 0.5
                to: 3
                stepSize: 0.1
                onMoved: v => GlobalConfig.background.desktopClock.scale = v
            }

            SelectRow {
                Layout.fillWidth: true
                label: qsTr("Position")
                active: {
                    const pos = Config.background.desktopClock.position;
                    const normPos = pos === "middle-center" ? "center" : pos;
                    for (let i = 0; i < root.positionItems.length; i++) {
                        if (root.positionItems[i].value === normPos)
                            return root.positionItems[i];
                    }
                    return root.positionItems[6];
                }
                menuItems: root.positionItems
                onSelected: item => GlobalConfig.background.desktopClock.position = item.value
            }

            SliderRow {
                Layout.fillWidth: true
                label: qsTr("Horizontal offset")
                valueLabel: Math.round((value * 0.2 - 0.1) * 100) + "%"
                value: Config.background.desktopClock.offsetX / 0.2 + 0.5
                onMoved: v => GlobalConfig.background.desktopClock.offsetX = v * 0.2 - 0.1
            }

            SliderRow {
                Layout.fillWidth: true
                label: qsTr("Vertical offset")
                valueLabel: Math.round((value * 0.2 - 0.1) * 100) + "%"
                value: Config.background.desktopClock.offsetY / 0.2 + 0.5
                onMoved: v => GlobalConfig.background.desktopClock.offsetY = v * 0.2 - 0.1
            }

            ToggleRow {
                last: true
                Layout.fillWidth: true
                text: qsTr("Invert colors")
                checked: Config.background.desktopClock.invertColors
                onToggled: GlobalConfig.background.desktopClock.invertColors = checked
            }
        }

        SectionHeader {
            text: qsTr("Desktop media shapes")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StepperRow {
                first: true
                Layout.fillWidth: true
                label: qsTr("Scale")
                value: Config.background.desktopShapes.scale
                from: 0.5
                to: 3
                stepSize: 0.1
                onMoved: v => GlobalConfig.background.desktopShapes.scale = v
            }

            SelectRow {
                last: true
                Layout.fillWidth: true
                label: qsTr("Position")
                active: {
                    const pos = Config.background.desktopShapes.position;
                    const normPos = pos === "middle-center" ? "center" : pos;
                    for (let i = 0; i < root.positionItems.length; i++) {
                        if (root.positionItems[i].value === normPos)
                            return root.positionItems[i];
                    }
                    return root.positionItems[5];
                }
                menuItems: root.positionItems
                onSelected: item => GlobalConfig.background.desktopShapes.position = item.value
            }
        }

        SectionHeader {
            text: qsTr("Desktop lyrics")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StepperRow {
                first: true
                Layout.fillWidth: true
                label: qsTr("Scale")
                value: Config.background.desktopLyrics.scale
                from: 0.5
                to: 3
                stepSize: 0.1
                onMoved: v => GlobalConfig.background.desktopLyrics.scale = v
            }

            SelectRow {
                Layout.fillWidth: true
                label: qsTr("Position")
                active: {
                    const pos = Config.background.desktopLyrics.position;
                    const normPos = pos === "middle-center" ? "center" : pos;
                    for (let i = 0; i < root.positionItems.length; i++) {
                        if (root.positionItems[i].value === normPos)
                            return root.positionItems[i];
                    }
                    return root.positionItems[5];
                }
                menuItems: root.positionItems
                onSelected: item => GlobalConfig.background.desktopLyrics.position = item.value
            }

            SelectRow {
                Layout.fillWidth: true
                label: qsTr("Alignment")
                active: {
                    for (let i = 0; i < root.alignmentItems.length; i++) {
                        if (root.alignmentItems[i].value === Config.background.desktopLyrics.alignment)
                            return root.alignmentItems[i];
                    }
                    return root.alignmentItems[1];
                }
                menuItems: root.alignmentItems
                onSelected: item => GlobalConfig.background.desktopLyrics.alignment = item.value
            }

            SliderRow {
                Layout.fillWidth: true
                label: qsTr("Horizontal offset")
                valueLabel: Math.round((value * 0.2 - 0.1) * 100) + "%"
                value: Config.background.desktopLyrics.offsetX / 0.2 + 0.5
                onMoved: v => GlobalConfig.background.desktopLyrics.offsetX = v * 0.2 - 0.1
            }

            SliderRow {
                Layout.fillWidth: true
                label: qsTr("Vertical offset")
                valueLabel: Math.round((value * 0.2 - 0.1) * 100) + "%"
                value: Config.background.desktopLyrics.offsetY / 0.2 + 0.5
                onMoved: v => GlobalConfig.background.desktopLyrics.offsetY = v * 0.2 - 0.1
            }

            ToggleRow {
                last: true
                Layout.fillWidth: true
                text: qsTr("Invert colors")
                checked: Config.background.desktopLyrics.invertColors
                onToggled: GlobalConfig.background.desktopLyrics.invertColors = checked
            }
        }

        SectionHeader {
            text: qsTr("Visualiser")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                first: true
                Layout.fillWidth: true
                text: qsTr("Blur")
                checked: Config.background.visualiser.blur
                onToggled: GlobalConfig.background.visualiser.blur = checked
            }

            StepperRow {
                Layout.fillWidth: true
                label: qsTr("Rounding")
                value: Config.background.visualiser.rounding
                from: 0
                to: 1
                stepSize: 0.05
                onMoved: v => GlobalConfig.background.visualiser.rounding = v
            }

            StepperRow {
                Layout.fillWidth: true
                label: qsTr("Spacing")
                value: Config.background.visualiser.spacing
                from: 0.5
                to: 3
                stepSize: 0.1
                onMoved: v => GlobalConfig.background.visualiser.spacing = v
            }

            StepperRow {
                last: true
                Layout.fillWidth: true
                label: qsTr("Size")
                subtext: qsTr("Column width multiplier, lower values leave more room in the middle")
                value: Config.background.visualiser.size
                from: 0.25
                to: 1.25
                stepSize: 0.05
                onMoved: v => GlobalConfig.background.visualiser.size = v
            }
        }
    }
}
