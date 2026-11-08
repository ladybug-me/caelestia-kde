pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<string> bundledSounds: [
        "aidos.wav",
        "Aldebaran.wav",
        "Altair.wav",
        "Antares.wav",
        "arcturus.wav",
        "Ariel.wav",
        "Beat_Box_Android.wav",
        "Bees_Knees.wav",
        "Betelgeuse.wav",
        "Canopus.wav",
        "Capella.wav",
        "Carme.wav",
        "Castor.wav",
        "Ceres.wav",
        "CetiAlpha.wav",
        "Cheeper.wav",
        "circios.wav",
        "Cricket.wav",
        "Deneb.wav",
        "Doink.wav",
        "Drip.wav",
        "Elara.wav",
        "Electra.wav",
        "Europa.wav",
        "Fomalhaut.wav",
        "Heaven.wav",
        "Hojus.wav",
        "horkos.wav",
        "hypnos1.wav",
        "Iapetus.wav",
        "IM_Me.wav",
        "Io.wav",
        "kratos1.wav",
        "kratos2.wav",
        "Lalande.wav",
        "Merope.wav",
        "Mira.wav",
        "moonbeam.wav",
        "nomos1.wav",
        "nomos2.wav",
        "ouranos.wav",
        "phantasos.wav",
        "pixiedust.wav",
        "pizzicato.wav",
        "Plastic_Pipe.wav",
        "Polaris.wav",
        "Pollux.wav",
        "poros.wav",
        "Procyon.wav",
        "Proxima.wav",
        "regulus.wav",
        "Rhea.wav",
        "Salacia.wav",
        "ShortCircuit.wav",
        "sirius.wav",
        "Sirrah.wav",
        "SpaceSeed.wav",
        "Star_Struck.wav",
        "TaDa.wav",
        "Tethys.wav",
        "thrasos1.wav",
        "Tinkerbell.wav",
        "Titan.wav",
        "tweeters.wav",
        "Upsilon.wav",
        "vega.wav"
    ]
    property var soundList: {
        const current = GlobalConfig.audio.sounds.notificationSound;
        if (current && !bundledSounds.includes(current))
            return [current, ...bundledSounds];
        return bundledSounds;
    }

    function soundDisplayName(fileName: string): string {
        if (!fileName)
            return qsTr("Default");
        const base = fileName.replace(/\.[^/.]+$/, "").replace(/_/g, " ");
        if (fileName === "Iapetus.wav" || base === "Iapetus")
            return qsTr("%1 (default)").arg(base);
        return base;
    }

    title: qsTr("Sounds")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Variants {
            id: soundVariants

            model: root.soundList

            MenuItem {
                required property string modelData

                text: root.soundDisplayName(modelData)
                value: modelData
            }
        }

        Timer {
            id: notifPreviewTimer

            interval: 400
            onTriggered: Audio.playNotification()
        }

        Timer {
            id: sfxPreviewTimer

            interval: 400
            onTriggered: Audio.playEffectTick()
        }

        SectionHeader {
            first: true
            text: qsTr("Notifications")
        }

        StepperRow {
            first: true
            label: qsTr("Notification volume")
            subtext: Math.round(value * 100) + "%"
            value: GlobalConfig.audio.sounds.notificationVolume
            from: 0.0
            to: 1.0
            stepSize: 0.05
            reset: ({ node: GlobalConfig.audio.sounds, setting: "notificationVolume" })
            onMoved: value => {
                GlobalConfig.audio.sounds.notificationVolume = value;
                notifPreviewTimer.restart();
            }
        }

        SelectRow {
            label: qsTr("Notification sound")
            subtext: qsTr("Sound played for incoming toasts and alerts")
            menuItems: soundVariants.instances
            active: menuItems.find(i => i.value === GlobalConfig.audio.sounds.notificationSound) ?? null
            fallbackText: root.soundDisplayName(GlobalConfig.audio.sounds.notificationSound)
            onSelected: item => {
                GlobalConfig.audio.sounds.notificationSound = item.value;
                Audio.playNotification();
            }
        }

        RowButton {
            last: true
            icon: "play_arrow"
            text: qsTr("Preview sound")
            subtext: qsTr("Play current notification sound")
            disabled: GlobalConfig.audio.sounds.notificationVolume === 0
            onClicked: Audio.playNotification()
        }

        SectionHeader {
            text: qsTr("Interface")
        }

        ToggleRow {
            first: true
            text: qsTr("Enable sound effects")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "enabled" })
            checked: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.enabled = checked
        }

        StepperRow {
            label: qsTr("Sound effect volume")
            subtext: Math.round(value * 100) + "%"
            value: GlobalConfig.audio.sounds.sfxVolume
            from: 0.0
            to: 1.0
            stepSize: 0.05
            reset: ({ node: GlobalConfig.audio.sounds, setting: "sfxVolume" })
            enabled: GlobalConfig.audio.sounds.enabled
            opacity: enabled ? 1 : 0.5
            onMoved: value => {
                GlobalConfig.audio.sounds.sfxVolume = value;
                sfxPreviewTimer.restart();
            }
        }

        ToggleRow {
            text: qsTr("Camera click")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "cameraClick" })
            checked: GlobalConfig.audio.sounds.cameraClick
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.cameraClick = checked
        }

        ToggleRow {
            text: qsTr("Volume tick")
            reset: ({ node: GlobalConfig.audio.sounds, setting: "effectTick" })
            checked: GlobalConfig.audio.sounds.effectTick
            enabled: GlobalConfig.audio.sounds.enabled
            onToggled: GlobalConfig.audio.sounds.effectTick = checked
        }

        ToggleRow {
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
