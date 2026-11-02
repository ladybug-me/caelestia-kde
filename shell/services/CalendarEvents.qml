pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

/// The events of the calendars configured in Nexus, as the agenda shows them.
///
/// The reading itself belongs to `scripts/calendar_events.py`: iCalendar is a
/// text format with recurrence rules, and parsing it in QML would mean a second
/// implementation of something the standard library already handles. The script
/// hands back one sorted list, and this only decides when to ask for it again.
Singleton {
    id: root

    readonly property var sources: GlobalConfig.services.calendarSources.values ?? []
    readonly property int days: Math.max(1, GlobalConfig.services.calendarDays)

    property var events: []
    property var errors: []
    property bool loading: false
    property double updatedAt: 0

    /// A re-read asked for while one was already running: "" for nothing, otherwise the
    /// kind of request to run once the current read finishes. A forced request wins over
    /// a soft one, since it subsumes it.
    property string _queued: ""

    readonly property bool configured: root.sources.length > 0

    function commandFor(force: bool): var {
        const args = ["python3", Quickshell.shellPath("scripts/calendar_events.py"), "--days", String(root.days)];
        if (force)
            args.push("--refresh");
        for (const source of root.sources) {
            const name = (source.name || "").trim() || "Calendar";
            const url = (source.url || "").trim();
            if (url)
                args.push("--source", `${name}=${url}`);
        }
        return args;
    }

    /// The events of the selected day, and whether a day has any — the grid marks the
    /// ones that do without having to build a list.
    function eventsOn(date: date): var {
        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        const end = start + 86400000;
        // Overlap rather than a day key: an all-day event, and a meeting that runs past
        // midnight, belong to every day they touch.
        return root.events.filter(event => event.start.getTime() < end && event.end.getTime() > start);
    }

    function hasEventsOn(date: date): bool {
        return root.eventsOn(date).length > 0;
    }

    function apply(output: string): void {
        root.loading = false;
        try {
            const parsed = JSON.parse(output);
            root.errors = parsed.errors ?? [];
            root.events = (parsed.events ?? []).map(item => ({
                uid: item.uid,
                summary: item.summary,
                location: item.location,
                source: item.source,
                allDay: item.allDay,
                day: item.day,
                start: new Date(item.startMs),
                end: new Date(item.endMs)
            }));
            root.updatedAt = Date.now();
        } catch (error) {
            root.errors = [{ source: "Calendar", error: String(error) }];
        }
    }

    /// `force` bypasses the on-disk copy and re-asks Google; without it the cached
    /// calendar is reused, so opening the popout is free.
    function refresh(force = false): void {
        if (!root.configured)
            return;

        const kind = force ? "force" : "soft";
        if (calendarProcess.running) {
            // A read is already on its way — queue one instead of dropping it, or a
            // popout opened during the first fetch would keep showing stale events.
            if (kind === "force" || root._queued === "")
                root._queued = kind;
            return;
        }

        root.loading = true;
        calendarProcess.command = root.commandFor(force);
        calendarProcess.running = true;
    }

    onSourcesChanged: root.refresh()
    onDaysChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Process {
        id: calendarProcess

        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }

        onExited: code => {
            root.loading = false;
            if (code !== 0 && root.errors.length === 0)
                root.errors = [{ source: "Calendar", error: `calendar_events.py exited with ${code}` }];

            if (root._queued !== "") {
                const force = root._queued === "force";
                root._queued = "";
                root.refresh(force);
            }
        }
    }

    /// A calendar changes when it changes, so the agenda is re-read on its own while
    /// the shell is open. The fetch is conditional, so most of these cost one 304. A feature
    /// that needs a tighter cadence asks for its own refresh rather than changing this one.
    Timer {
        interval: 5 * 60 * 1000
        running: root.configured
        repeat: true
        onTriggered: root.refresh()
    }
}
