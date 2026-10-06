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
            checked: Config.utilities.showKeepAwake
            onToggled: GlobalConfig.utilities.showKeepAwake = checked
        }

        ToggleRow {
            text: qsTr("Screen Capture")
            subtext: qsTr("Show the screen capture card")
            checked: Config.utilities.showScreenRecorder
            onToggled: GlobalConfig.utilities.showScreenRecorder = checked
        }

        ToggleRow {
            text: qsTr("GIF Recorder")
            subtext: qsTr("Show the Record GIF option in the recorder menu")
            checked: Config.utilities.showGifRecorder
            onToggled: GlobalConfig.utilities.showGifRecorder = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Quick Toggles")
            subtext: qsTr("Show the Quick Toggles card")
            checked: Config.utilities.showQuickToggles
            onToggled: GlobalConfig.utilities.showQuickToggles = checked
        }
    }
}