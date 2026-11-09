import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("On-screen sliders")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Sliders")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            subtext: qsTr("Show the on-screen sliders")
            reset: ({ node: GlobalConfig.osd, setting: "enabled" })
            checked: Config.osd.enabled
            onToggled: GlobalConfig.osd.enabled = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Show the volume slider")
            reset: ({ node: GlobalConfig.osd, setting: "enableVolume" })
            checked: Config.osd.enableVolume
            onToggled: GlobalConfig.osd.enableVolume = checked
        }

        ToggleRow {
            text: qsTr("Microphone")
            subtext: qsTr("Show the microphone slider")
            reset: ({ node: GlobalConfig.osd, setting: "enableMicrophone" })
            checked: Config.osd.enableMicrophone
            onToggled: GlobalConfig.osd.enableMicrophone = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Brightness")
            subtext: qsTr("Show the brightness slider")
            reset: ({ node: GlobalConfig.osd, setting: "enableBrightness" })
            checked: Config.osd.enableBrightness
            onToggled: GlobalConfig.osd.enableBrightness = checked
        }

        SectionHeader {
            text: qsTr("Edge trigger")
        }

        StepperRow {
            first: true
            label: qsTr("Depth")
            subtext: qsTr("Distance from the screen edge")
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
            subtext: qsTr("Portion of the edge that responds")
            reset: ({ node: GlobalConfig.osd, setting: "hoverWidth" })
            value: Config.osd.hoverWidth
            from: 10
            to: 100
            stepSize: 5
            onMoved: value => GlobalConfig.osd.hoverWidth = value
        }

        SectionHeader {
            text: qsTr("Behavior")
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Hide delay")
            subtext: qsTr("Seconds before the slider hides")
            reset: ({ node: GlobalConfig.osd, setting: "hideDelay" })
            value: Config.osd.hideDelay / 1000
            from: 1
            to: 10
            stepSize: 1
            onMoved: value => GlobalConfig.osd.hideDelay = Math.round(value * 1000)
        }
    }
}
