pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.osd.floating

PageBase {
    id: root

    readonly property list<MenuItem> styleItems: [
        MenuItem {
            property string value: "default"

            text: qsTr("Default (Edge Drawer)")
        },
        MenuItem {
            property string value: "pill"

            text: qsTr("Pill / Dynamic Island")
        },
        MenuItem {
            property string value: "compact"

            text: qsTr("Compact Slider")
        },
        MenuItem {
            property string value: "radial"

            text: qsTr("Radial Dial HUD")
        },
        MenuItem {
            property string value: "card"

            text: qsTr("Elevated Card")
        },
        MenuItem {
            property string value: "bar"

            text: qsTr("Minimal Bar")
        }
    ]

    readonly property list<MenuItem> positionItems: [
        MenuItem {
            property string value: "bottom"

            text: qsTr("Bottom Center")
        },
        MenuItem {
            property string value: "top"

            text: qsTr("Top Center")
        },
        MenuItem {
            property string value: "center"

            text: qsTr("Center")
        },
        MenuItem {
            property string value: "right"

            text: qsTr("Right Side")
        },
        MenuItem {
            property string value: "left"

            text: qsTr("Left Side")
        }
    ]

    title: qsTr("OSD")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Design & Style")
        }

        SelectRow {
            first: true
            label: qsTr("Design")
            subtext: qsTr("Visual style for hardware buttons (volume, brightness)")
            menuItems: root.styleItems
            active: {
                for (let i = 0; i < root.styleItems.length; i++) {
                    if (root.styleItems[i].value === GlobalConfig.osd.style)
                        return root.styleItems[i];
                }
                return root.styleItems[0];
            }
            fallbackIcon: "tune"
            onSelected: item => GlobalConfig.osd.style = item.value
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 140

            OsdPreview {
                anchors.centerIn: parent
                style: GlobalConfig.osd.style
            }
        }

        RowButton {
            icon: "play_arrow"
            text: qsTr("Test OSD on screen")
            subtext: qsTr("Trigger a live test of the current OSD design")
            onClicked: Audio.volumeChanged()
        }

        SelectRow {
            last: true
            visible: GlobalConfig.osd.style !== "default"
            label: qsTr("Position")
            subtext: qsTr("Screen placement for the floating indicator")
            menuItems: root.positionItems
            active: {
                for (let i = 0; i < root.positionItems.length; i++) {
                    if (root.positionItems[i].value === GlobalConfig.osd.position)
                        return root.positionItems[i];
                }
                return root.positionItems[0];
            }
            fallbackIcon: "dashboard_customize"
            onSelected: item => GlobalConfig.osd.position = item.value
        }

        SectionHeader {
            text: qsTr("Monitors")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            subtext: qsTr("Enable on-screen display popups")
            reset: ({ node: GlobalConfig.osd, setting: "enabled" })
            checked: Config.osd.enabled
            onToggled: GlobalConfig.osd.enabled = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the edge drawer when the cursor reaches the screen edge")
            reset: ({ node: GlobalConfig.osd, setting: "showOnHover" })
            checked: Config.osd.showOnHover
            onToggled: GlobalConfig.osd.showOnHover = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Show indicator on speaker volume changes")
            reset: ({ node: GlobalConfig.osd, setting: "enableVolume" })
            checked: Config.osd.enableVolume
            onToggled: GlobalConfig.osd.enableVolume = checked
        }

        ToggleRow {
            text: qsTr("Microphone")
            subtext: qsTr("Show indicator on microphone volume changes")
            reset: ({ node: GlobalConfig.osd, setting: "enableMicrophone" })
            checked: Config.osd.enableMicrophone
            onToggled: GlobalConfig.osd.enableMicrophone = checked
        }

        ToggleRow {
            text: qsTr("Brightness")
            subtext: qsTr("Show indicator on display brightness changes")
            reset: ({ node: GlobalConfig.osd, setting: "enableBrightness" })
            checked: Config.osd.enableBrightness
            onToggled: GlobalConfig.osd.enableBrightness = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Show in fullscreen")
            subtext: qsTr("Display indicator over fullscreen applications")
            reset: ({ node: GlobalConfig.osd, setting: "showInFullscreen" })
            checked: Config.osd.showInFullscreen
            onToggled: GlobalConfig.osd.showInFullscreen = checked
        }

        SectionHeader {
            text: qsTr("Timing")
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Hide delay")
            subtext: qsTr("Seconds before the indicator hides")
            reset: ({ node: GlobalConfig.osd, setting: "hideDelay" })
            value: Config.osd.hideDelay / 1000
            from: 1
            to: 10
            stepSize: 1
            onMoved: value => GlobalConfig.osd.hideDelay = Math.round(value * 1000)
        }

        SectionHeader {
            text: qsTr("Edge Drawer (Mouse Trigger)")
        }

        StepperRow {
            first: true
            label: qsTr("Depth")
            subtext: qsTr("Distance from the screen edge to trigger the drawer")
            reset: ({ node: GlobalConfig.osd, setting: "hoverThickness" })
            value: Config.osd.hoverThickness
            from: 1
            to: 100
            stepSize: 1
            onMoved: value => GlobalConfig.osd.hoverThickness = value
        }

        StepperRow {
            last: true
            label: qsTr("Height")
            subtext: qsTr("Portion of the edge that responds to hover")
            reset: ({ node: GlobalConfig.osd, setting: "hoverWidth" })
            value: Config.osd.hoverWidth
            from: 10
            to: 100
            stepSize: 5
            onMoved: value => GlobalConfig.osd.hoverWidth = value
        }
    }
}
