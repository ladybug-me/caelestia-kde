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

    readonly property var allToggleDefs: [...root.connectivityToggles, ...root.toolToggles, ...root.systemToggles]
    readonly property bool customOrder: Config.utilities.quickTogglesCustomOrder ?? false
    readonly property var orderedToggles: {
        const labels = {};
        root.allToggleDefs.forEach(d => {
            labels[d.id] = d.label;
        });
        const stored = Config.utilities.quickToggles || [];
        const known = stored.filter(t => t.id in labels);
        const knownIds = new Set(known.map(t => t.id));
        const missing = root.allToggleDefs.filter(d => !knownIds.has(d.id)).map(d => ({
                    id: d.id,
                    enabled: true
                }));
        return [...known, ...missing].map(t => ({
                    id: t.id,
                    label: labels[t.id],
                    enabled: t.enabled !== false
                }));
    }

    function saveToggles(list: var): void {
        GlobalConfig.utilities.quickToggles = list.map(t => ({
                    id: t.id,
                    enabled: t.enabled
                }));
    }

    title: qsTr("Quick toggles")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Custom order")
            subtext: qsTr("Rearrange toggles with drag handles")
            checked: root.customOrder
            onToggled: {
                GlobalConfig.utilities.quickTogglesCustomOrder = checked;
            }
        }

        ListEditor {
            visible: root.customOrder
            allowRemove: false
            values: root.orderedToggles
            onItemMoved: (from, to) => {
                const list = [...root.orderedToggles];
                const moved = list.splice(from, 1)[0];
                list.splice(to, 0, moved);
                root.saveToggles(list);
            }
            onItemToggled: (index, checked) => {
                const list = [...root.orderedToggles];
                list[index] = {
                    id: list[index].id,
                    label: list[index].label,
                    enabled: checked
                };
                root.saveToggles(list);
            }
        }

        SectionHeader {
            visible: !root.customOrder
            first: true
            text: qsTr("Connectivity")
        }

        Repeater {
            id: connectivityRepeater

            visible: !root.customOrder

            model: root.connectivityToggles

            delegate: QuickToggleRow {
                first: index === 0
                last: index === connectivityRepeater.count - 1
            }
        }

        SectionHeader {
            visible: !root.customOrder
            text: qsTr("Tools")
        }

        Repeater {
            id: toolRepeater

            visible: !root.customOrder

            model: root.toolToggles

            delegate: QuickToggleRow {
                first: index === 0
                last: index === toolRepeater.count - 1
            }
        }

        SectionHeader {
            visible: !root.customOrder
            text: qsTr("System")
        }

        Repeater {
            id: systemRepeater

            visible: !root.customOrder

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