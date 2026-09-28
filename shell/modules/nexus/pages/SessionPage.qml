pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    function commandString(list: var): string {
        return (list || []).join(" ");
    }

    function commandList(text: string): var {
        return text.split(" ").filter(s => s.length > 0);
    }

    title: qsTr("Session")

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
            Layout.fillWidth: true
            text: qsTr("Enabled")
            subtext: qsTr("Show the session (power) menu")
            checked: Config.session.enabled
            onToggled: GlobalConfig.session.enabled = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Vim keybinds")
            subtext: qsTr("Navigate the session menu with hjkl")
            checked: Config.session.vimKeybinds
            onToggled: GlobalConfig.session.vimKeybinds = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels to drag before the menu moves")
            value: Config.session.dragThreshold
            from: 10
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.session.dragThreshold = v
        }

        SectionHeader {
            text: qsTr("Icons")
        }

        LabeledField {
            first: true
            label: qsTr("Logout")
            value: Config.session.icons.logout
            onCommitted: v => GlobalConfig.session.icons.logout = v
        }

        LabeledField {
            label: qsTr("Shutdown")
            value: Config.session.icons.shutdown
            onCommitted: v => GlobalConfig.session.icons.shutdown = v
        }

        LabeledField {
            label: qsTr("Hibernate")
            value: Config.session.icons.hibernate
            onCommitted: v => GlobalConfig.session.icons.hibernate = v
        }

        LabeledField {
            last: true
            label: qsTr("Reboot")
            value: Config.session.icons.reboot
            onCommitted: v => GlobalConfig.session.icons.reboot = v
        }

        SectionHeader {
            text: qsTr("Commands")
        }

        LabeledField {
            first: true
            label: qsTr("Logout")
            value: root.commandString(Config.session.commands.logout)
            onCommitted: v => GlobalConfig.session.commands.logout = root.commandList(v)
        }

        LabeledField {
            label: qsTr("Shutdown")
            value: root.commandString(Config.session.commands.shutdown)
            onCommitted: v => GlobalConfig.session.commands.shutdown = root.commandList(v)
        }

        LabeledField {
            label: qsTr("Hibernate")
            value: root.commandString(Config.session.commands.hibernate)
            onCommitted: v => GlobalConfig.session.commands.hibernate = root.commandList(v)
        }

        LabeledField {
            last: true
            label: qsTr("Reboot")
            value: root.commandString(Config.session.commands.reboot)
            onCommitted: v => GlobalConfig.session.commands.reboot = root.commandList(v)
        }
    }

    component LabeledField: ConnectedRect {
        id: field

        property string label
        property string value

        signal committed(string v)

        Layout.fillWidth: true
        implicitHeight: row.implicitHeight + Tokens.padding.medium * 2

        RowLayout {
            id: row

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            StyledText {
                text: field.label
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
                Layout.preferredWidth: 128
            }
            StyledInputField {
                Layout.fillWidth: true
                horizontalAlignment: TextInput.AlignLeft
                text: field.value
                onEditingFinished: field.committed(text)
            }
        }
    }
}
