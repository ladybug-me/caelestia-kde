import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Utilities panel")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Visible cards")
        }

        ToggleRow {
            first: true
            text: qsTr("Keep Awake")
            subtext: qsTr("Show the Keep Awake card")
            reset: ({ node: GlobalConfig.utilities, setting: "showKeepAwake" })
            checked: Config.utilities.showKeepAwake
            onToggled: GlobalConfig.utilities.showKeepAwake = checked
        }

        ToggleRow {
            text: qsTr("Timers")
            subtext: qsTr("Show the countdown timers card")
            reset: ({ node: GlobalConfig.utilities, setting: "showTimers" })
            checked: Config.utilities.showTimers
            onToggled: GlobalConfig.utilities.showTimers = checked
        }

        ToggleRow {
            text: qsTr("Screen Capture")
            subtext: qsTr("Show the screen capture card")
            reset: ({ node: GlobalConfig.utilities, setting: "showScreenRecorder" })
            checked: Config.utilities.showScreenRecorder
            onToggled: GlobalConfig.utilities.showScreenRecorder = checked
        }

        ToggleRow {
            text: qsTr("GIF Recorder")
            subtext: qsTr("Show the Record GIF option in the recorder menu")
            reset: ({ node: GlobalConfig.utilities, setting: "showGifRecorder" })
            checked: Config.utilities.showGifRecorder
            onToggled: GlobalConfig.utilities.showGifRecorder = checked
        }

        ToggleRow {
            text: qsTr("Quick Share")
            subtext: qsTr("Show the Quick Share card while it is enabled")
            reset: ({ node: GlobalConfig.utilities, setting: "showQuickShare" })
            checked: Config.utilities.showQuickShare
            onToggled: GlobalConfig.utilities.showQuickShare = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Quick Toggles")
            subtext: qsTr("Show the Quick Toggles card")
            reset: ({ node: GlobalConfig.utilities, setting: "showQuickToggles" })
            checked: Config.utilities.showQuickToggles
            onToggled: GlobalConfig.utilities.showQuickToggles = checked
        }
    }
}
