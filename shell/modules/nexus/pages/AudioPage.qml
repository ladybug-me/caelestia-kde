pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Audio")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Output")
        }

        SliderRow {
            first: true
            icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            label: qsTr("Output")
            valueLabel: Math.round(value * 100) + "%"
            value: Audio.volume
            enabled: !Audio.muted
            onMoved: v => Audio.setVolume(v)
            onReleased: v => Audio.playEffectTick()
        }

        ToggleRow {
            text: qsTr("Muted")
            checked: Audio.muted
            onToggled: Audio.setStreamMuted(Audio.sink, checked)
        }

        ToggleRow {
            text: qsTr("Show Inactive Devices")
            checked: Audio.showInactiveDevices
            onToggled: Audio.showInactiveDevices = checked
        }

        AudioDeviceList {
            nodes: Audio.sinks
            currentId: Audio.sink?.id ?? -1
            iconName: "speaker"
            placeholderIcon: "speaker"
            placeholderText: qsTr("No output devices")
            onSelected: node => Audio.setAudioSink(node)
        }

        SectionHeader {
            text: qsTr("Input")
        }

        SliderRow {
            first: true
            icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
            label: qsTr("Input")
            valueLabel: Math.round(value * 100) + "%"
            value: Audio.sourceVolume
            enabled: !Audio.sourceMuted
            onMoved: v => Audio.setSourceVolume(v)
            onReleased: v => Audio.playEffectTick()
        }

        ToggleRow {
            text: qsTr("Muted")
            checked: Audio.sourceMuted
            onToggled: Audio.setStreamMuted(Audio.source, checked)
        }

        AudioDeviceList {
            nodes: Audio.sources
            currentId: Audio.source?.id ?? -1
            iconName: "mic"
            placeholderIcon: "mic_off"
            placeholderText: qsTr("No input devices")
            onSelected: node => Audio.setAudioSource(node)
        }

        SectionHeader {
            text: qsTr("Device Profiles")
        }

        Repeater {
            model: Audio.cards

            delegate: SplitButtonRow {
                id: cardRow

                required property var model
                readonly property var card: model.PulseObject
                readonly property var availableProfiles: card?.profiles ? card.profiles.filter(p => p.availability !== 2 || card.profiles.indexOf(p) === card.activeProfileIndex) : []

                label: AudioBackend.cardDescription(card) || card?.properties?.["device.description"] || model.description || card?.name || qsTr("Unknown Device")
                menuItems: profileVariants.instances
                active: menuItems.find(item => item.modelData === cardRow.card?.profiles?.[cardRow.card?.activeProfileIndex] || item.text === cardRow.card?.profiles?.[cardRow.card?.activeProfileIndex]?.description) ?? null

                Variants {
                    id: profileVariants

                    model: cardRow.availableProfiles

                    MenuItem {
                        required property var modelData

                        text: modelData.description
                        onClicked: cardRow.card.activeProfileIndex = cardRow.card.profiles.indexOf(modelData)
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Apps")
        }

        NavRow {
            first: true
            last: true
            icon: "tune"
            label: qsTr("App volumes")
            status: Audio.appStreams.length === 0 ? qsTr("No apps playing audio") : Audio.appStreams.length === 1 ? qsTr("1 app playing audio") : qsTr("%1 apps playing audio").arg(Audio.appStreams.length)
            onClicked: root.nState.openSubPage("appVolumes")
        }

        SectionHeader {
            text: qsTr("Customization")
        }

        NavRow {
            first: true
            icon: "volume_up"
            label: qsTr("Sound effects")
            status: qsTr("Feedback sounds and volume")
            onClicked: root.nState.openSubPage("soundEffects")
        }

        NavRow {
            last: true
            icon: "notifications_off"
            label: qsTr("Muted notification apps")
            status: qsTr("Applications that send nothing, or send without a sound")
            onClicked: root.nState.openSubPage("notificationSilencing")
        }
    }
}
