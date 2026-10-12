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
                text: qsTr("Auto-hide media shapes")
                subtext: qsTr("Hide media shapes when a window is open")
                reset: ({ node: GlobalConfig.background.desktopShapes, setting: "autoHide" })
                checked: Config.background.desktopShapes.autoHide
                onToggled: GlobalConfig.background.desktopShapes.autoHide = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                text: qsTr("Auto-hide lyrics")
                subtext: qsTr("Hide lyrics when a window is open")
                reset: ({ node: GlobalConfig.background.desktopLyrics, setting: "autoHide" })
                checked: Config.background.desktopLyrics.autoHide
                onToggled: GlobalConfig.background.desktopLyrics.autoHide = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                last: !Config.background.visualiser.enabled
                text: qsTr("Background visualiser")
                subtext: qsTr("Show music visualiser on wallpaper (May consume more power)")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "enabled" })
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
                reset: ({ node: GlobalConfig.background.visualiser, setting: "autoHide" })
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
                reset: ({ node: GlobalConfig.background.visualiser, setting: "hideOnAllMonitors" })
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

            ToggleRow {
                first: true
                last: true
                Layout.fillWidth: true
                text: qsTr("Invert colors")
                reset: ({ node: GlobalConfig.background.desktopClock, setting: "invertColors" })
                checked: Config.background.desktopClock.invertColors
                onToggled: GlobalConfig.background.desktopClock.invertColors = checked
            }
        }

        SectionHeader {
            text: qsTr("Desktop lyrics")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            SelectRow {
                first: true
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

            ToggleRow {
                last: true
                Layout.fillWidth: true
                text: qsTr("Invert colors")
                reset: ({ node: GlobalConfig.background.desktopLyrics, setting: "invertColors" })
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
                reset: ({ node: GlobalConfig.background.visualiser, setting: "blur" })
                checked: Config.background.visualiser.blur
                onToggled: GlobalConfig.background.visualiser.blur = checked
            }

            StepperRow {
                Layout.fillWidth: true
                label: qsTr("Rounding")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "rounding" })
                value: Config.background.visualiser.rounding
                from: 0
                to: 1
                stepSize: 0.05
                onMoved: v => GlobalConfig.background.visualiser.rounding = v
            }

            StepperRow {
                Layout.fillWidth: true
                label: qsTr("Spacing")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "spacing" })
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
                reset: ({ node: GlobalConfig.background.visualiser, setting: "size" })
                value: Config.background.visualiser.size
                from: 0.25
                to: 1.25
                stepSize: 0.05
                onMoved: v => GlobalConfig.background.visualiser.size = v
            }
        }
    }
}
