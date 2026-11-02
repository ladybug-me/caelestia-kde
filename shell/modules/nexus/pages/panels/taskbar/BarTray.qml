pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Tray")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            reset: ({ node: GlobalConfig.bar.tray, setting: "background" })
            checked: Config.bar.tray.background
            onToggled: GlobalConfig.bar.tray.background = checked
        }

        ToggleRow {
            text: qsTr("Recolor icons")
            reset: ({ node: GlobalConfig.bar.tray, setting: "recolour" })
            checked: Config.bar.tray.recolour
            onToggled: GlobalConfig.bar.tray.recolour = checked
        }

        ToggleRow {
            text: qsTr("Compact")
            reset: ({ node: GlobalConfig.bar.tray, setting: "compact" })
            checked: Config.bar.tray.compact
            onToggled: GlobalConfig.bar.tray.compact = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show the tray menu popout when hovering")
            reset: ({ node: GlobalConfig.bar.popouts, setting: "tray" })
            checked: Config.bar.popouts.tray
            onToggled: GlobalConfig.bar.popouts.tray = checked
        }

        SectionHeader {
            text: qsTr("Icons")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: !Config.bar.tray.compact
            text: qsTr("Every icon stays on the bar while Compact is off, so Collapse applies once it is on.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        ListEditor {
            id: icons

            function labelFor(item: var): string {
                return item.title;
            }

            function subtextFor(item: var): string {
                return item.running ? item.id : qsTr("Not running");
            }

            function iconFor(item: var): string {
                return Icons.getTrayIcon(item.key, item.icon);
            }

            z: 1
            first: true
            values: TrayRegistry.entries
            allowRemove: false
            allowToggle: false
            trailingComponent: stateButton

            onItemMoved: (from, to) => TrayRegistry.move(from, to)

            Component {
                id: stateButton

                SplitButton {
                    property var modelData: ({})
                    property bool isLast: false

                    readonly property string trayState: TrayRegistry.stateOf(modelData.key)

                    type: SplitButton.Tonal
                    menuOnTop: isLast
                    active: menuItems.find(entry => entry.value === trayState) ?? null
                    fallbackText: TrayRegistry.stateLabel(trayState)
                    fallbackIcon: TrayRegistry.stateIcon(trayState)

                    menuItems: [
                        MenuItem {
                            text: TrayRegistry.stateLabel("visible")
                            icon: TrayRegistry.stateIcon("visible")
                            value: "visible"
                        },
                        MenuItem {
                            text: TrayRegistry.stateLabel("collapsed")
                            icon: TrayRegistry.stateIcon("collapsed")
                            value: "collapsed"
                        },
                        MenuItem {
                            text: TrayRegistry.stateLabel("hidden")
                            icon: TrayRegistry.stateIcon("hidden")
                            value: "hidden"
                        },
                        MenuItem {
                            visible: !modelData.running
                            text: qsTr("Forget")
                            icon: "delete"
                            value: "forget"
                        }
                    ]

                    menu.onItemSelected: item => {
                        if (item.value === "forget")
                            TrayRegistry.forget(modelData.key);
                        else
                            TrayRegistry.setState(modelData.key, item.value);
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: icons.count === 0
            text: qsTr("No tray icons have been seen yet.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: icons.count > 1
            text: qsTr("Drag a row to change the order")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
