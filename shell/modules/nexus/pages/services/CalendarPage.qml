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

    readonly property var sources: GlobalConfig.services.calendarSources.values ?? []

    readonly property list<MenuItem> lookAheadItems: [
        MenuItem {
            text: qsTr("7 days")
            value: 7
        },
        MenuItem {
            text: qsTr("14 days")
            value: 14
        },
        MenuItem {
            text: qsTr("30 days")
            value: 30
        }
    ]

    function addSource(): void {
        const url = urlField.field.text.trim();
        if (url === "")
            return;

        const name = nameField.field.text.trim();
        GlobalConfig.services.calendarSources.insert({ name: name || qsTr("Calendar"), url: url });
        GlobalConfig.save();

        nameField.clear();
        urlField.clear();
        CalendarEvents.refresh();
    }

    function removeSource(index: int): void {
        GlobalConfig.services.calendarSources.remove(index);
        GlobalConfig.save();
        CalendarEvents.refresh();
    }

    function statusText(): string {
        if (CalendarEvents.loading)
            return qsTr("Reading calendars…");
        if (CalendarEvents.errors.length > 0)
            return qsTr("%1: %2").arg(CalendarEvents.errors[0].source).arg(CalendarEvents.errors[0].error);
        if (!CalendarEvents.configured)
            return qsTr("No calendar added yet");
        if (CalendarEvents.updatedAt === 0)
            return qsTr("Not read yet");

        return qsTr("Updated %1 · %2 events ahead").arg(Qt.formatTime(new Date(CalendarEvents.updatedAt), "hh:mm")).arg(CalendarEvents.events.length);
    }

    title: qsTr("Calendar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Calendars")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: helper.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: helper

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: qsTr("Add the calendar's iCal address. In Google Calendar that is Settings -> your calendar -> \"Secret address in iCal format\"; Nextcloud and Fastmail call it an export or subscription link, and a local .ics file works too. The address is read only and re-read every few minutes, so changes made in Google appear here without doing anything.")
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                wrapMode: Text.Wrap
            }
        }

        TextFieldRow {
            id: nameField

            label: qsTr("Name")
            placeholderText: qsTr("Work")
        }

        TextFieldRow {
            id: urlField

            label: qsTr("iCal address")
            placeholderText: "https://…/basic.ics"
            onEditingFinished: root.addSource()
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: root.sources.length === 0
            implicitHeight: addRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: addRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Paste the address, then add it")
                    color: Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                    elide: Text.ElideRight
                }

                TextButton {
                    text: qsTr("Add")
                    type: urlField.field.text.trim() !== "" ? TextButton.Filled : TextButton.Tonal
                    enabled: urlField.field.text.trim() !== ""
                    onClicked: root.addSource()
                }
            }
        }

        Repeater {
            model: root.sources

            delegate: ConnectedRect {
                id: sourceRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === root.sources.length - 1
                implicitHeight: sourceLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: sourceLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "calendar_month"
                        fontStyle: Tokens.font.icon.small
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: sourceRow.modelData.name || qsTr("Calendar")
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: sourceRow.modelData.url
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                            elide: Text.ElideMiddle
                        }
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        onClicked: root.removeSource(sourceRow.index)
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Agenda")
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Look ahead")
            subtext: qsTr("How far the agenda and the calendar popout look for events")
            fallbackIcon: "event_upcoming"
            fallbackText: qsTr("%1 days").arg(GlobalConfig.services.calendarDays)

            menuItems: root.lookAheadItems
            active: root.lookAheadItems.find(item => item.value === GlobalConfig.services.calendarDays) ?? null

            onSelected: item => {
                GlobalConfig.services.calendarDays = item.value;
                GlobalConfig.save();
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: refreshRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: refreshRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText()
                    color: CalendarEvents.errors.length > 0 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                    elide: Text.ElideRight
                }

                TextButton {
                    text: qsTr("Refresh")
                    enabled: CalendarEvents.configured && !CalendarEvents.loading
                    onClicked: CalendarEvents.refresh(true)
                }
            }
        }
    }
}
