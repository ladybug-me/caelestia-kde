pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var entries: Autostart.entries

    title: qsTr("Startup")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("At log-in")
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.entries.length === 0
            text: qsTr("Nothing is set to start at log-in.")
            color: Colours.palette.m3onSurfaceVariant
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.entries

            delegate: ConnectedRect {
                id: entryRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === root.entries.length - 1
                implicitHeight: entryLayout.implicitHeight + entryLayout.anchors.margins * 2

                RowLayout {
                    id: entryLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    IconImage {
                        asynchronous: true
                        implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                        source: Quickshell.iconPath(entryRow.modelData.icon, "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: entryRow.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: entryRow.modelData.system ? qsTr("%1 - from the system, switched here").arg(entryRow.modelData.command) : entryRow.modelData.command
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                            elide: Text.ElideRight
                        }
                    }

                    StyledSwitch {
                        checked: entryRow.modelData.enabled
                        onToggled: Autostart.setEnabled(entryRow.modelData.id, checked)
                    }

                    // Only the user's own entry can be removed: a system one is switched off
                    // instead, or the next package update would bring it back.
                    IconButton {
                        visible: entryRow.modelData.own
                        icon: "delete"
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        onClicked: Autostart.remove(entryRow.modelData.id)
                    }
                }
            }
        }

        NavRow {
            first: true
            last: true
            icon: "add"
            label: qsTr("Add an application")
            status: qsTr("Pick it from the applications installed here")
            onClicked: root.nState.openSubPage("startupAppPicker")
        }
    }
}
