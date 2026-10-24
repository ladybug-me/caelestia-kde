pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus

/// The clock's calendar: a month at a glance, and the events of the day picked in it.
///
/// The month itself belongs to `CalendarMonth`, so this only holds the selection and
/// renders that day's agenda.
StyledRect {
    id: root

    required property PopoutState popouts
    property bool _isSidebarOpen: false
    property real scaleOffset: 1.0
    property real fontScale: 1.0

    property date viewDate: new Date()
    /// The day whose events are listed under the grid. Picking a day moves it, which is
    /// what makes the grid and the list one control instead of two.
    property date selectedDate: new Date()
    readonly property var selectedEvents: CalendarEvents.eventsOn(root.selectedDate)
    readonly property string selectedLabel: root.isToday(root.selectedDate) ? qsTr("Today") : Qt.locale().toString(root.selectedDate, "ddd d MMM")

    function isToday(date: date): bool {
        const now = new Date();
        return date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
    }

    function select(date: date): void {
        root.selectedDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        // A trailing day belongs to the month it is shown in, so follow it there.
        if (date.getMonth() !== root.viewDate.getMonth() || date.getFullYear() !== root.viewDate.getFullYear())
            root.viewDate = new Date(date.getFullYear(), date.getMonth(), 1);
    }

    function shiftMonth(delta: int): void {
        root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() + delta, 1);
    }

    function goToToday(): void {
        root.viewDate = new Date();
    }

    function eventTime(event: var): string {
        if (event.allDay)
            return qsTr("All day");
        // Same 12/24-hour choice as the bar clock, so the two never disagree.
        return Time.clockTime(event.start);
    }

    function agendaHint(): string {
        if (!CalendarEvents.configured)
            return qsTr("No calendars yet - click to add one");
        if (CalendarEvents.errors.length > 0)
            return qsTr("Could not read %1 - click to check the address").arg(CalendarEvents.errors[0].source);

        return qsTr("No events");
    }

    /// Cheap when nothing changed: the script reuses its copy of the calendar and only
    /// revalidates it, so this is safe to run every time the popout is opened.
    function refreshOnOpen(): void {
        const popouts = root.popouts;
        if (!popouts)
            return;
        // Name first or flag first depends on how the popout was opened, so either
        // changing is enough for it to count as opened.
        if (popouts.currentName !== "clock")
            return;
        CalendarEvents.refresh();
    }

    /// The empty agenda is the only place a first-time user meets this feature, so it
    /// leads to the page that fills it rather than naming a menu they have to find.
    function openCalendarSettings(): void {
        const pageIdx = PageDictionary.pageIdxFor("services");
        if (pageIdx < 0)
            return;

        if (root.popouts)
            root.popouts.hasCurrent = false;
        WindowFactory.create(null, {
            initialPageIdx: pageIdx,
            initialSubPageIdx: PageDictionary.subPageIdxFor("services/CalendarPage.qml")
        });
    }

    implicitWidth: 497 * root.scaleOffset
    implicitHeight: inner.implicitHeight + Tokens.padding.large * 2 * root.scaleOffset
    radius: Tokens.rounding.extraLarge * root.scaleOffset
    color: Colours.tPalette.m3surfaceContainer

    // Opening the calendar is the moment its contents matter, so that is when a stale
    // copy is re-read rather than only on the background timer.
    Connections {
        function onHasCurrentChanged(): void {
            root.refreshOnOpen();
        }

        function onCurrentNameChanged(): void {
            root.refreshOnOpen();
        }

        target: root.popouts
    }

    CustomMouseArea {
        function onWheel(event: WheelEvent): void {
            if (event.angleDelta.y > 0)
                root.shiftMonth(-1);
            else if (event.angleDelta.y < 0)
                root.shiftMonth(1);
        }

        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.goToToday();
            } else if (mouse.button === Qt.RightButton) {
                root.popouts.currentName = "clockcontext";
            }
        }
    }

    ColumnLayout {
        id: inner

        x: Tokens.padding.large * root.scaleOffset
        y: Tokens.padding.large * root.scaleOffset
        width: root.width - Tokens.padding.large * 2 * root.scaleOffset
        spacing: Tokens.spacing.extraSmall * root.scaleOffset

        CalendarMonth {
            Layout.fillWidth: true

            viewDate: root.viewDate
            highlightedDate: root.selectedDate
            selectable: true
            scaleOffset: root.scaleOffset
            fontScale: root.fontScale

            onMonthShifted: delta => root.shiftMonth(delta)
            onTodayRequested: root.goToToday()
            onDayClicked: date => root.select(date)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium * root.scaleOffset
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
        }

        // The day the indicator sits on, so the list below reads as that cell opened up
        // rather than as a separate feed.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium * root.scaleOffset
            text: root.selectedLabel
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.builders.small.size(Tokens.font.body.builders.small.build().pointSize * root.fontScale).weight(Font.Medium).build()
            elide: Text.ElideRight
        }

        Repeater {
            model: root.selectedEvents.length > 0 ? root.selectedEvents : [null]

            delegate: Item {
                id: eventRow

                required property var modelData

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall * root.scaleOffset
                implicitHeight: eventRow.modelData ? eventText.implicitHeight : hint.implicitHeight

                Column {
                    id: eventText

                    width: parent.width
                    spacing: 0
                    visible: eventRow.modelData !== null

                    Row {
                        width: parent.width
                        spacing: Tokens.spacing.small * root.scaleOffset

                        StyledText {
                            width: 74 * root.scaleOffset
                            text: eventRow.modelData ? root.eventTime(eventRow.modelData) : ""
                            color: Colours.palette.m3primary
                            font: Tokens.font.label.builders.small.size(Tokens.font.label.small.pointSize * root.fontScale).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width - 74 * root.scaleOffset - parent.spacing
                            text: eventRow.modelData?.summary ?? ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.builders.small.size(Tokens.font.body.small.pointSize * root.fontScale).build()
                            elide: Text.ElideRight
                        }
                    }

                    StyledText {
                        width: parent.width - 74 * root.scaleOffset - Tokens.spacing.small * root.scaleOffset
                        x: 74 * root.scaleOffset + Tokens.spacing.small * root.scaleOffset
                        text: eventRow.modelData?.location ?? ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.builders.small.size(Tokens.font.label.small.pointSize * root.fontScale).build()
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }

                StyledText {
                    id: hint

                    width: parent.width
                    visible: eventRow.modelData === null
                    text: root.agendaHint()
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.builders.small.size(Tokens.font.body.small.pointSize * root.fontScale).build()
                    wrapMode: Text.Wrap
                }

                // Last, so it takes the click rather than the text above it, and it has
                // to be given the row's size: it is not positioned by the layout.
                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    disabled: eventRow.modelData !== null || CalendarEvents.configured
                    onClicked: root.openCalendarSettings()
                }
            }
        }
    }
}
