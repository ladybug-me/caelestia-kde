pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var connectivityToggles: [
        { id: "wifi", label: qsTr("Wi-Fi") },
        { id: "hotspot", label: qsTr("Hotspot") },
        { id: "bluetooth", label: qsTr("Bluetooth") },
        { id: "vpn", label: qsTr("VPN") },
    ]
    readonly property var toolToggles: [
        { id: "settings", label: qsTr("Settings") },
        { id: "colorpicker", label: qsTr("Color Picker") },
        { id: "wallpaper", label: qsTr("Wallpaper") },
        { id: "badapple", label: qsTr("Bad Apple") },
    ]
    readonly property var systemToggles: [
        { id: "mic", label: qsTr("Microphone") },
        { id: "dnd", label: qsTr("Do Not Disturb") },
        { id: "gameMode", label: qsTr("Game Mode") },
        { id: "pauseWallpaper", label: qsTr("Pause Wallpaper") },
        { id: "nightlight", label: qsTr("Night Light") },
        { id: "easyeffects", label: qsTr("EasyEffects") },
        { id: "restartShell", label: qsTr("Restart Shell") },
    ]

    title: qsTr("Quick toggles")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Connectivity")
        }

        Repeater {
            id: connectivityRepeater

            model: root.connectivityToggles

            delegate: QuickToggleRow {
                first: index === 0
                last: index === connectivityRepeater.count - 1
            }
        }

        SectionHeader {
            text: qsTr("Tools")
        }

        Repeater {
            id: toolRepeater

            model: root.toolToggles

            delegate: QuickToggleRow {
                first: index === 0
                last: index === toolRepeater.count - 1
            }
        }

        SectionHeader {
            text: qsTr("System")
        }

        Repeater {
            id: systemRepeater

            model: root.systemToggles

            delegate: QuickToggleRow {
                first: index === 0
                last: index === systemRepeater.count - 1
            }
        }
    }

    component QuickToggleRow: ToggleRow {
        required property var modelData
        required property int index

        text: modelData.label
        checked: {
            const toggles = Config.utilities.quickToggles || [];
            const toggle = toggles.find(item => item.id === modelData.id);
            return toggle ? toggle.enabled !== false : true;
        }
        onToggled: {
            const toggles = JSON.parse(JSON.stringify(GlobalConfig.utilities.quickToggles || []));
            const toggleIndex = toggles.findIndex(item => item.id === modelData.id);
            if (toggleIndex >= 0) {
                toggles[toggleIndex].enabled = checked;
            } else {
                toggles.push({ id: modelData.id, enabled: checked });
            }
            GlobalConfig.utilities.quickToggles = toggles;
        }
    }
}