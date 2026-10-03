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
    readonly property var orderedIds: {
        const labels = {};
        root.allToggleDefs.forEach(d => {
            labels[d.id] = d.label;
        });
        const stored = Config.utilities.quickToggles || [];
        const known = stored.filter(t => t.id in labels).map(t => t.id);
        const knownSet = new Set(known);
        const missing = root.allToggleDefs.filter(d => !knownSet.has(d.id)).map(d => d.id);
        return [...known, ...missing];
    }

    function toggleLabel(id: string): string {
        const def = root.allToggleDefs.find(d => d.id === id);
        return def ? def.label : id;
    }

    function toggleEnabled(id: string): bool {
        const stored = Config.utilities.quickToggles || [];
        const found = stored.find(t => t.id === id);
        return found ? found.enabled !== false : true;
    }

    function writeOrder(ids: var): void {
        GlobalConfig.utilities.quickToggles = ids.map(id => ({
                    id: id,
                    enabled: root.toggleEnabled(id)
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
            function labelFor(item: var): string {
                return root.toggleLabel(item);
            }

            function toggledFor(item: var): bool {
                return root.toggleEnabled(item);
            }

            visible: root.customOrder
            allowRemove: false
            values: root.orderedIds
            onItemMoved: (from, to) => {
                const ids = [...root.orderedIds];
                const moved = ids.splice(from, 1)[0];
                ids.splice(to, 0, moved);
                root.writeOrder(ids);
            }
            onItemToggled: (index, checked) => {
                const stored = Config.utilities.quickToggles || [];
                const id = root.orderedIds[index];
                const entry = stored.find(t => t.id === id);
                if (entry) {
                    const list = stored.map(t => ({
                                id: t.id,
                                enabled: t.id === id ? checked : (t.enabled !== false)
                            }));
                    GlobalConfig.utilities.quickToggles = list;
                } else {
                    GlobalConfig.utilities.quickToggles = [...stored.map(t => ({
                                id: t.id,
                                enabled: t.enabled !== false
                            })), {
                            id: id,
                            enabled: checked
                        }];
                }
            }
        }

        SectionHeader {
            visible: !root.customOrder
            first: true
            text: qsTr("Connectivity")
        }

        Repeater {
            id: connectivityRepeater

            model: root.customOrder ? [] : root.connectivityToggles


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

            model: root.customOrder ? [] : root.toolToggles


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

            model: root.customOrder ? [] : root.systemToggles


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