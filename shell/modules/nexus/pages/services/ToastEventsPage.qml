import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Toast events")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("System")
        }

        ToggleRow {
            first: true
            text: qsTr("Charging changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "chargingChanged" })
            checked: GlobalConfig.utilities.toasts.chargingChanged
            onToggled: GlobalConfig.utilities.toasts.chargingChanged = checked
        }

        ToggleRow {
            text: qsTr("Game mode changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "gameModeChanged" })
            checked: GlobalConfig.utilities.toasts.gameModeChanged
            onToggled: GlobalConfig.utilities.toasts.gameModeChanged = checked
        }

        ToggleRow {
            text: qsTr("Night light changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "nightLightChanged" })
            checked: GlobalConfig.utilities.toasts.nightLightChanged
            onToggled: GlobalConfig.utilities.toasts.nightLightChanged = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Configuration loaded")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "configLoaded" })
            checked: GlobalConfig.utilities.toasts.configLoaded
            onToggled: GlobalConfig.utilities.toasts.configLoaded = checked
        }

        SectionHeader {
            text: qsTr("Audio")
        }

        ToggleRow {
            first: true
            text: qsTr("Audio output changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "audioOutputChanged" })
            checked: GlobalConfig.utilities.toasts.audioOutputChanged
            onToggled: GlobalConfig.utilities.toasts.audioOutputChanged = checked
        }

        ToggleRow {
            text: qsTr("Audio input changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "audioInputChanged" })
            checked: GlobalConfig.utilities.toasts.audioInputChanged
            onToggled: GlobalConfig.utilities.toasts.audioInputChanged = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Now playing")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "nowPlaying" })
            checked: GlobalConfig.utilities.toasts.nowPlaying
            onToggled: GlobalConfig.utilities.toasts.nowPlaying = checked
        }

        SectionHeader {
            text: qsTr("Input")
        }

        ToggleRow {
            first: true
            text: qsTr("Caps lock changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "capsLockChanged" })
            checked: GlobalConfig.utilities.toasts.capsLockChanged
            onToggled: GlobalConfig.utilities.toasts.capsLockChanged = checked
        }

        ToggleRow {
            text: qsTr("Num lock changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "numLockChanged" })
            checked: GlobalConfig.utilities.toasts.numLockChanged
            onToggled: GlobalConfig.utilities.toasts.numLockChanged = checked
        }

        ToggleRow {
            text: qsTr("Keyboard layout changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "kbLayoutChanged" })
            checked: GlobalConfig.utilities.toasts.kbLayoutChanged
            onToggled: GlobalConfig.utilities.toasts.kbLayoutChanged = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Keyboard layout limit")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "kbLimit" })
            checked: GlobalConfig.utilities.toasts.kbLimit
            onToggled: GlobalConfig.utilities.toasts.kbLimit = checked
        }

        SectionHeader {
            text: qsTr("Other")
        }

        ToggleRow {
            first: true
            text: qsTr("Do not disturb changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "dndChanged" })
            checked: GlobalConfig.utilities.toasts.dndChanged
            onToggled: GlobalConfig.utilities.toasts.dndChanged = checked
        }

        ToggleRow {
            text: qsTr("VPN changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "vpnChanged" })
            checked: GlobalConfig.utilities.toasts.vpnChanged
            onToggled: GlobalConfig.utilities.toasts.vpnChanged = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Clipboard changes")
            reset: ({ node: GlobalConfig.utilities.toasts, setting: "clipboardChanged" })
            checked: GlobalConfig.utilities.toasts.clipboardChanged
            onToggled: GlobalConfig.utilities.toasts.clipboardChanged = checked
        }
    }
}
