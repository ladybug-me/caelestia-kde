pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

/// Focus sessions: Do Not Disturb that turns itself on for the windows configured in
/// Nexus, while a short list of apps is still allowed through.
///
/// The session holds quiet on Notifs by name rather than flipping the user's switch, so
/// it cannot announce itself with a toast and cannot switch off a do-not-disturb the
/// user set by hand — or one another feature is holding.
Singleton {
    id: root

    readonly property bool enabled: GlobalConfig.notifs.focusEnabled
    readonly property bool followCalendar: GlobalConfig.notifs.focusCalendar
    readonly property var schedules: GlobalConfig.notifs.focusSchedules.values ?? []
    readonly property var allowlist: GlobalConfig.notifs.focusAllowlist ?? []

    /// Recomputed on a timer so a session starts on the minute it is due.
    property date now: new Date()

    readonly property var activeSchedule: {
        for (const schedule of root.schedules)
            if (root.scheduleActive(schedule, root.now))
                return schedule;
        return null;
    }

    /// A meeting that is running right now. All-day entries are not meetings: they would
    /// hold a session open from midnight to midnight.
    readonly property var activeMeeting: {
        if (!root.followCalendar || !CalendarEvents.configured)
            return null;

        return CalendarEvents.eventsOn(root.now).find(event => !event.allDay && event.start <= root.now && root.now < event.end) ?? null;
    }

    readonly property bool active: root.enabled && (root.activeSchedule !== null || root.activeMeeting !== null)
    readonly property string activeName: {
        if (root.activeMeeting)
            return root.activeMeeting.summary || qsTr("Meeting");

        return root.activeSchedule?.name ?? "";
    }

    function parseTime(value: string): int {
        const parts = (value ?? "").split(":");
        if (parts.length < 2)
            return -1;

        const hours = parseInt(parts[0], 10);
        const minutes = parseInt(parts[1], 10);
        if (isNaN(hours) || isNaN(minutes))
            return -1;

        return Math.max(0, Math.min(23, hours)) * 60 + Math.max(0, Math.min(59, minutes));
    }

    function dayToken(date: date): string {
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()];
    }

    function scheduleActive(schedule: var, at: date): bool {
        const start = root.parseTime(schedule.start);
        const end = root.parseTime(schedule.end);
        if (start < 0 || end < 0 || start === end)
            return false;

        const days = schedule.days ?? [];
        const minutes = at.getHours() * 60 + at.getMinutes();
        const allowedOn = day => days.length === 0 || days.includes(day);

        if (end > start)
            return allowedOn(root.dayToken(at)) && minutes >= start && minutes < end;

        // Overnight: the part after midnight still belongs to the day it started on.
        if (minutes >= start)
            return allowedOn(root.dayToken(at));

        const yesterday = new Date(at.getFullYear(), at.getMonth(), at.getDate() - 1);
        return minutes < end && allowedOn(root.dayToken(yesterday));
    }

    /// The time a running session ends, for the "until" line in Nexus. A configured window
    /// only carries "HH:MM", so it is put on today's clock and formatted the same way the
    /// meeting's end is: one time format, whichever source opened the session.
    function activeEnd(): string {
        if (root.activeMeeting)
            return Time.clockTime(root.activeMeeting.end);

        const minutes = root.parseTime(root.activeSchedule?.end ?? "");
        if (minutes < 0)
            return root.activeSchedule?.end ?? "";

        const at = new Date();
        at.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0);
        return Time.clockTime(at);
    }

    function allows(appName: string): bool {
        if (!root.active || appName === "")
            return false;

        const name = appName.toLowerCase();
        return root.allowlist.some(allowed => allowed.toLowerCase() === name);
    }

    function sync(): void {
        root.now = new Date();
        Notifs.setDndHold("focus", root.active);
    }

    onEnabledChanged: root.sync()
    onSchedulesChanged: root.sync()
    onFollowCalendarChanged: root.sync()
    Component.onCompleted: root.sync()

    // A meeting starts and ends at minutes the schedule timer does not know about, so the
    // calendar is watched as well while focus follows it: the events as they arrive, and the
    // calendar itself, which otherwise refreshes on a cadence too slow to catch a start.
    Connections {
        function onEventsChanged(): void {
            root.sync();
        }

        target: CalendarEvents
    }

    Timer {
        interval: 60 * 1000
        running: root.followCalendar && CalendarEvents.configured
        repeat: true
        onTriggered: CalendarEvents.refresh()
    }

    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        onTriggered: root.sync()
    }
}
