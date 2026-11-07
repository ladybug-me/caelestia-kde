pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// A month at a glance with, when the card is wide enough, the agenda of the day
// picked in it. The month itself belongs to CalendarMonth, so the grid, the dots on
// days with events and the shape on the selected day are the ones the bar shows.
Item {
    id: root

    property var frame
    property var controller

    readonly property var cfg: frame?.config ?? ({})
    readonly property bool showEvents: cfg.showEvents !== false
    // Wide cards trade half the month's width for the agenda; narrow ones keep the
    // whole width for the month and mark the days that have events instead.
    readonly property bool agenda: root.showEvents && root.width > root.height * 1.25
    readonly property real fontScale: Math.max(0.8, Math.min(1.25, root.height / 260))

    property date viewDate: new Date()
    property date selectedDate: new Date()

    readonly property var selectedEvents: CalendarEvents.eventsOn(root.selectedDate)
    readonly property string agendaHint: {
        if (!CalendarEvents.configured)
            return qsTr("No calendars yet");
        if (CalendarEvents.errors.length > 0)
            return qsTr("Could not read %1").arg(CalendarEvents.errors[0].source);
        return qsTr("No events");
    }

    function shiftMonth(delta: int): void {
        root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() + delta, 1);
    }

    function pick(date: date): void {
        root.selectedDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        // A trailing day belongs to the month it is shown in, so follow it there.
        if (date.getMonth() !== root.viewDate.getMonth() || date.getFullYear() !== root.viewDate.getFullYear())
            root.viewDate = new Date(date.getFullYear(), date.getMonth(), 1);
    }

    function eventTime(event: var): string {
        if (event.allDay)
            return qsTr("All day");
        // The bar clock's 12/24-hour choice, so the two never disagree.
        return Time.clockTime(event.start);
    }

    Component.onCompleted: CalendarEvents.refresh()

    WheelHandler {
        acceptedModifiers: Qt.NoModifier
        onWheel: event => root.shiftMonth(event.angleDelta.y > 0 ? -1 : 1)
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.large

        CalendarMonth {
            Layout.fillWidth: true
            Layout.preferredWidth: root.agenda ? root.width * 0.55 : root.width
            Layout.alignment: Qt.AlignTop

            viewDate: root.viewDate
            highlightedDate: root.selectedDate
            selectable: true
            fontScale: root.fontScale
            scaleOffset: root.fontScale

            onMonthShifted: delta => root.shiftMonth(delta)
            onTodayRequested: root.viewDate = new Date()
            onDayClicked: date => root.pick(date)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.agenda
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root.selectedDate.toLocaleDateString(Qt.locale(), "ddd d MMM")
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            Flickable {
                id: agendaScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: agendaColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: StyledScrollBar {
                    flickable: agendaScroll
                }

                ColumnLayout {
                    id: agendaColumn

                    width: agendaScroll.width
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.selectedEvents.length === 0
                        text: root.agendaHint
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: root.selectedEvents

                        RowLayout {
                            id: eventRow

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledRect {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: Tokens.padding.extraSmall
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: eventRow.modelData.summary
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.eventTime(eventRow.modelData)
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}