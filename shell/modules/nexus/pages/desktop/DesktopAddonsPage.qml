pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
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

    readonly property list<MenuItem> visualizerProfiles: [
        MenuItem {
            property string value: "double_reversed"

            text: qsTr("Double Reversed (default)")
        },
        MenuItem {
            property string value: "user"

            text: qsTr("User defined")
        },
        MenuItem {
            property string value: "single"

            text: qsTr("Single")
        },
        MenuItem {
            property string value: "circle"

            text: qsTr("Circle")
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
                Layout.fillWidth: true
                text: qsTr("Invert colors")
                reset: ({ node: GlobalConfig.background.desktopLyrics, setting: "invertColors" })
                checked: Config.background.desktopLyrics.invertColors
                onToggled: GlobalConfig.background.desktopLyrics.invertColors = checked
            }

            ToggleRow {
                last: true
                Layout.fillWidth: true
                text: qsTr("Auto-hide lyrics")
                subtext: qsTr("Hide lyrics when a window is open")
                reset: ({ node: GlobalConfig.background.desktopLyrics, setting: "autoHide" })
                checked: Config.background.desktopLyrics.autoHide
                onToggled: GlobalConfig.background.desktopLyrics.autoHide = checked
            }
        }

        SectionHeader {
            text: qsTr("Visualiser")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            InfoRow {
                first: true
                Layout.fillWidth: true
                visible: !PlasmaWidgets.hasVisualizer
                icon: "info"
                wrapSubtext: true
                label: qsTr("plasma-audio-visualizer not installed")
                subtext: qsTr("Download and install plasma-audio-visualizer to enable these settings.")
            }

            ToggleRow {
                first: PlasmaWidgets.hasVisualizer
                last: !Config.background.visualiser.enabled
                Layout.fillWidth: true
                enabled: PlasmaWidgets.hasVisualizer
                opacity: enabled ? 1 : 0.5
                text: qsTr("Enable Visualizer")
                subtext: qsTr("Show audio visualizer on desktop")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "enabled" })
                checked: Config.background.visualiser.enabled
                onToggled: {
                    PlasmaWidgets.setWidgetEnabled("visualizer", checked);
                }
            }

            SelectRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                visible: Config.background.visualiser.enabled
                enabled: PlasmaWidgets.hasVisualizer
                opacity: enabled ? 1 : 0.5
                label: qsTr("Profile")
                subtext: qsTr("Visualizer layout and style preset")
                menuItems: root.visualizerProfiles
                active: {
                    for (let i = 0; i < root.visualizerProfiles.length; i++) {
                        if (root.visualizerProfiles[i].value === (Config.background.visualiser.profile || "double_reversed"))
                            return root.visualizerProfiles[i];
                    }
                    return root.visualizerProfiles[0];
                }
                onSelected: item => {
                    PlasmaWidgets.setVisualizerProfile(item.value);
                }
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                visible: Config.background.visualiser.enabled
                enabled: PlasmaWidgets.hasVisualizer
                opacity: enabled ? 1 : 0.5
                text: qsTr("Auto-hide visualizer")
                subtext: qsTr("Hide visualizer when a window is maximized on active workspace")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "autoHide" })
                checked: Config.background.visualiser.autoHide
                onToggled: GlobalConfig.background.visualiser.autoHide = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                visible: Config.background.visualiser.enabled
                enabled: PlasmaWidgets.hasVisualizer && Config.background.visualiser.autoHide
                opacity: enabled ? 1 : 0.5
                text: qsTr("Hide on all monitors")
                subtext: qsTr("Also hide on all other monitors if disabled by a window")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "hideOnAllMonitors" })
                checked: Config.background.visualiser.hideOnAllMonitors
                onToggled: GlobalConfig.background.visualiser.hideOnAllMonitors = checked
            }

            InfoRow {
                last: true
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                visible: Config.background.visualiser.enabled && PlasmaWidgets.hasVisualizer
                icon: "info"
                wrapSubtext: true
                label: qsTr("Configure Visualizer")
                subtext: qsTr("Right click on desktop -> Edit Mode -> Right click visualizer -> Configure")
            }
        }

        SectionHeader {
            text: qsTr("Media shapes")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                first: true
                last: true
                Layout.fillWidth: true
                text: qsTr("Auto-hide media shapes")
                subtext: qsTr("Hide media shapes when a window is open")
                reset: ({ node: GlobalConfig.background.desktopShapes, setting: "autoHide" })
                checked: Config.background.desktopShapes.autoHide
                onToggled: GlobalConfig.background.desktopShapes.autoHide = checked
            }
        }
    }
}