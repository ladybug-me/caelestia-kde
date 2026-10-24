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

    readonly property var schedules: GlobalConfig.notifs.focusSchedules.values ?? []
    readonly property var allowlist: GlobalConfig.notifs.focusAllowlist ?? []
    readonly property var weekDays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    property list<string> draftDays: []

    readonly property string defaultStart: "09:00"
    readonly property string defaultEnd: "17:00"

    readonly property bool canAdd: nameField.field.text.trim() !== "" && Focus.parseTime(startField.text) >= 0 && Focus.parseTime(endField.text) >= 0

    function toggleDraftDay(day: string): void {
        const days = Array.from(root.draftDays);
        const index = days.indexOf(day);
        if (index >= 0)
            days.splice(index, 1);
        else
            days.push(day);
        root.draftDays = days;
    }

    function addSchedule(): void {
        if (!root.canAdd)
            return;

        GlobalConfig.notifs.focusSchedules.insert({
            name: nameField.field.text.trim(),
            days: Array.from(root.draftDays),
            start: startField.text.trim(),
            end: endField.text.trim()
        });
        GlobalConfig.save();

        nameField.clear();
        startField.text = root.defaultStart;
        endField.text = root.defaultEnd;
        root.draftDays = [];
    }

    function removeSchedule(index: int): void {
        GlobalConfig.notifs.focusSchedules.remove(index);
        GlobalConfig.save();
    }

    function daySummary(schedule: var): string {
        const days = schedule.days ?? [];
        if (days.length === 0)
            return qsTr("Every day");
        if (days.length === 7)
            return qsTr("Every day");

        return days.join(", ");
    }

    function statusText(): string {
        if (!GlobalConfig.notifs.focusEnabled)
            return qsTr("Focus sessions are off");
        if (Focus.active)
            return qsTr("%1 until %2").arg(Focus.activeName || qsTr("Focus")).arg(Focus.activeEnd());

        return qsTr("No session running now");
    }

    function addAllowedApp(appName: string): void {
        const name = appName.trim();
        if (name === "" || root.allowlist.includes(name))
            return;

        const apps = Array.from(root.allowlist);
        apps.push(name);
        GlobalConfig.notifs.focusAllowlist = apps;
        GlobalConfig.save();
    }

    function removeAllowedApp(appName: string): void {
        const apps = Array.from(root.allowlist).filter(name => name !== appName);
        GlobalConfig.notifs.focusAllowlist = apps;
        GlobalConfig.save();
    }

    title: qsTr("Focus sessions")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Focus")
        }

        ToggleRow {
            first: true
            text: qsTr("Focus sessions")
            subtext: qsTr("Turn notifications off by themselves on a schedule")
            checked: GlobalConfig.notifs.focusEnabled
            onToggled: {
                GlobalConfig.notifs.focusEnabled = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Follow the calendar")
            subtext: qsTr("Start a session while a calendar event is running")
            checked: GlobalConfig.notifs.focusCalendar
            onToggled: {
                GlobalConfig.notifs.focusCalendar = checked;
                GlobalConfig.save();
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: focusStatus.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: focusStatus

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: Focus.active ? "do_not_disturb_on" : "do_not_disturb"
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText()
                    color: Focus.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                    elide: Text.ElideRight
                }
            }
        }

        SectionHeader {
            text: qsTr("Schedules")
        }

        Repeater {
            model: root.schedules

            delegate: ConnectedRect {
                id: scheduleRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0 && root.schedules.length > 0
                implicitHeight: scheduleLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: scheduleLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: scheduleRow.modelData.name || qsTr("Focus")
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `${root.daySummary(scheduleRow.modelData)} · ${scheduleRow.modelData.start}–${scheduleRow.modelData.end}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        onClicked: root.removeSchedule(scheduleRow.index)
                    }
                }
            }
        }

        TextFieldRow {
            id: nameField

            first: root.schedules.length === 0
            label: qsTr("Name")
            placeholderText: qsTr("Deep work")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: dayPicker.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: dayPicker

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Days")
                    color: Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                }

                Repeater {
                    model: root.weekDays

                    delegate: StyledRect {
                        id: dayChip

                        required property string modelData

                        implicitWidth: dayLabel.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: dayLabel.implicitHeight + Tokens.padding.extraSmall * 2
                        radius: Tokens.rounding.large
                        color: root.draftDays.includes(dayChip.modelData) ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainer, 2)

                        StyledText {
                            id: dayLabel

                            anchors.centerIn: parent
                            text: dayChip.modelData.slice(0, 3)
                            color: root.draftDays.includes(dayChip.modelData) ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            font: NexusStyle.secondaryFont
                        }

                        StateLayer {
                            onClicked: root.toggleDraftDay(dayChip.modelData)
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: addRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: addRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("From")
                    color: Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                }

                StyledInputField {
                    id: startField

                    implicitWidth: 96
                    text: root.defaultStart
                }

                StyledText {
                    text: qsTr("to")
                    color: Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                }

                StyledInputField {
                    id: endField

                    implicitWidth: 96
                    text: root.defaultEnd
                }

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    text: qsTr("Add")
                    type: root.canAdd ? TextButton.Filled : TextButton.Tonal
                    enabled: root.canAdd
                    onClicked: root.addSchedule()
                }
            }
        }

        SectionHeader {
            text: qsTr("Allowed through")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: allowHelper.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: allowHelper

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: qsTr("Notifications from these apps still pop up during a focus session.")
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                wrapMode: Text.Wrap
            }
        }

        AppPickerRow {
            last: true
            icon: "add"
            label: qsTr("Allow an application")
            status: qsTr("Pick it from the applications installed here")
            exclude: root.allowlist
            onSelected: name => root.addAllowedApp(name)
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.allowlist

                delegate: RemovableChip {
                    required property string modelData

                    label: modelData
                    onRemoved: root.removeAllowedApp(modelData)
                }
            }
        }
    }
}
