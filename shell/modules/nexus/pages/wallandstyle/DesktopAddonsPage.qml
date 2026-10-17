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
                last: true
                text: qsTr("Auto-hide lyrics")
                subtext: qsTr("Hide lyrics when a window is open")
                reset: ({ node: GlobalConfig.background.desktopLyrics, setting: "autoHide" })
                checked: Config.background.desktopLyrics.autoHide
                onToggled: GlobalConfig.background.desktopLyrics.autoHide = checked
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
                last: !Config.background.visualiser.enabled
                Layout.fillWidth: true
                text: qsTr("Enable Visualizer")
                subtext: qsTr("Show audio visualizer on desktop")
                reset: ({ node: GlobalConfig.background.visualiser, setting: "enabled" })
                checked: Config.background.visualiser.enabled
                onToggled: {
                    PlasmaWidgets.setWidgetEnabled("visualizer", checked);
                }
            }

            InfoRow {
                last: true
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                visible: Config.background.visualiser.enabled
                icon: "info"
                wrapSubtext: true
                label: qsTr("Configure Visualizer")
                subtext: qsTr("Right click on desktop -> Edit Mode -> Right click visualizer -> Configure")
            }
        }
    }
}
