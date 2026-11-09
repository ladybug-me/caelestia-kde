import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Sound effects")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            text: qsTr("Enable sound effects")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "enabled" })
            checked: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.enabled = checked
        }

        SliderRow {
            last: true
            icon: "volume_up"
            label: qsTr("Sound effect volume")
            valueLabel: Math.round(value * 100) + "%"
            value: GlobalConfig.audio.sounds.sfxVolume
            enabled: GlobalConfig.audio.sounds.enabled
            onMoved: value => GlobalConfig.audio.sounds.sfxVolume = value
            onReleased: value => Audio.playEffectTick()
        }

        SectionHeader {
            text: qsTr("Feedback")
        }

        ToggleRow {
            first: true
            text: qsTr("Camera click")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "cameraClick" })
            checked: GlobalConfig.audio.sounds.cameraClick
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.cameraClick = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Volume tick")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "effectTick" })
            checked: GlobalConfig.audio.sounds.effectTick
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.effectTick = checked
        }

        SectionHeader {
            text: qsTr("System")
        }

        ToggleRow {
            first: true
            text: qsTr("Charging started")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "chargingStarted" })
            checked: GlobalConfig.audio.sounds.chargingStarted
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.chargingStarted = checked
        }

        ToggleRow {
            text: qsTr("Screen lock")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "lock" })
            checked: GlobalConfig.audio.sounds.lock
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.lock = checked
        }

        ToggleRow {
            text: qsTr("Screen unlock")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "unlock" })
            checked: GlobalConfig.audio.sounds.unlock
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.unlock = checked
        }

        ToggleRow {
            text: qsTr("Low battery")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "lowBattery" })
            checked: GlobalConfig.audio.sounds.lowBattery
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.lowBattery = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Screen recording")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "screenRecord" })
            checked: GlobalConfig.audio.sounds.screenRecord
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.screenRecord = checked
        }
    }
}
