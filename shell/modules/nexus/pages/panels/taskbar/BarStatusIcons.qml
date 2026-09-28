pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var builtinIcons: ({
            lockStatus: qsTr("Lock keys"),
            kbLayout: qsTr("Keyboard layout"),
            audio: qsTr("Speakers"),
            microphone: qsTr("Microphone"),
            network: qsTr("Network"),
            ethernet: qsTr("Ethernet"),
            bluetooth: qsTr("Bluetooth"),
            battery: qsTr("Battery"),
            peripheralBattery: qsTr("Peripheral battery"),
            nightlight: qsTr("Night light"),
            notifications: qsTr("Notifications")
        })
    readonly property var addableIcons: {
        const present = Config.bar.statusIcons.values.map(entry => entry.id);
        return Object.keys(root.builtinIcons).filter(id => !present.includes(id)).map(id => ({ id: id, label: root.builtinIcons[id] }));
    }

    title: qsTr("Status icons")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Visible icons")
        }

        ListEditor {
            function labelFor(item: var): string {
                return root.builtinIcons[item.id] ?? item.id;
            }

            function toggledFor(item: var): bool {
                return item.enabled;
            }

            z: 1
            first: true
            values: Config.bar.statusIcons.values
            onItemMoved: (from, to) => GlobalConfig.bar.statusIcons.move(from, to)
            onItemRemoved: index => GlobalConfig.bar.statusIcons.remove(index)
            onItemToggled: (index, checked) => GlobalConfig.bar.statusIcons.at(index).enabled = checked
        }

        DialogSelectButton {
            id: addItemContainer

            rootParent: root.flickable
            visible: root.addableIcons.length > 0
            icon: "add"
            label: qsTr("Add entry")
            header: qsTr("Add new entry")
            acceptLabel: qsTr("Add")

            model: root.addableIcons

            onAccepted: {
                if (selectedItem)
                    GlobalConfig.bar.statusIcons.insert({ id: selectedItem, enabled: true });
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Wi-Fi")
            subtext: qsTr("Show the Wi-Fi icon alongside the network icon")
            checked: Config.bar.status.showWifi
            onToggled: GlobalConfig.bar.status.showWifi = checked
        }

        SectionHeader {
            text: qsTr("Behavior")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show a details popout when hovering the status icons")
            checked: Config.bar.popouts.statusIcons
            onToggled: GlobalConfig.bar.popouts.statusIcons = checked
        }
    }
}
