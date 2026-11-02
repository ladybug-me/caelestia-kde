#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/shell/scripts/calendar_events.py"
SERVICE="$REPO_ROOT/shell/services/CalendarEvents.qml"
POPOUT="$REPO_ROOT/shell/modules/bar/popouts/CalendarPopout.qml"
CLOCK="$REPO_ROOT/shell/modules/bar/components/Clock.qml"
MONTH="$REPO_ROOT/shell/components/CalendarMonth.qml"
CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/serviceconfig.hpp"
BAR_CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/barconfig.hpp"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/services/CalendarPage.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
DICTIONARY="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"

PYTHON="$(command -v python3 || command -v python)"

# An ICS fixture covering the cases a hand-written parser gets wrong: a named
# timezone, an all-day date, a weekly rule with BYDAY and an EXDATE, and an
# every-other-day rule that has to stop at COUNT.
write_fixture() {
    cat >"$1" <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:single@test
SUMMARY:Lunch with Sam
LOCATION:Cafe\, Main St
DTSTART;TZID=Europe/London:20991120T123000
DTEND;TZID=Europe/London:20991120T133000
END:VEVENT
BEGIN:VEVENT
UID:allday@test
SUMMARY:Holiday
DTSTART;VALUE=DATE:20991121
DTEND;VALUE=DATE:20991122
END:VEVENT
BEGIN:VEVENT
UID:weekly@test
SUMMARY:Standup
DTSTART:20991102T090000Z
DTEND:20991102T091500Z
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6
EXDATE:20991104T090000Z
END:VEVENT
BEGIN:VEVENT
UID:daily@test
SUMMARY:Stretch
DTSTART:20991001T070000Z
DTEND:20991001T071000Z
RRULE:FREQ=DAILY;INTERVAL=2;COUNT=3
END:VEVENT
END:VCALENDAR
ICS
}

test_parser_expands_recurrence_and_timezones() {
    local dir fixture output
    dir="$(mktemp -d)"
    fixture="$dir/test.ics"
    write_fixture "$fixture"

    output="$("$PYTHON" "$SCRIPT" --days 100000 --source "Test=$fixture" 2>&1)"
    rm -rf "$dir"

    assert_contains "$output" '"summary": "Lunch with Sam"' "a plain event must be read"
    assert_contains "$output" '"summary": "Holiday"' "an all-day event must be read"
    # \, is the iCalendar escape for a comma, which the agenda shows verbatim otherwise.
    assert_contains "$output" '"location": "Cafe, Main St"' "escaped commas must be unescaped"
    assert_contains "$output" '"allDay": true' "an all-day event must say so"

    # 2099-11-02 is a Monday: MO,WE over six weeks is 02, 04, 09, 11, 16, 18 — and the
    # EXDATE removes the 4th, so five Mondays/Wednesdays survive.
    assert_contains "$output" '"day": "2099-11-09"' "recurrence must be expanded"
    assert_contains "$output" '"day": "2099-11-11"' "BYDAY must include the second weekday"
    assert_not_contains "$output" '"day": "2099-11-04"' \
        "EXDATE must remove an occurrence"
    assert_contains "$output" '"day": "2099-10-05"' "INTERVAL=2 must skip every other day"
    assert_not_contains "$output" '"day": "2099-10-06"' "INTERVAL=2 must not emit the days between"
    assert_not_contains "$output" '"day": "2099-10-07"' "COUNT=3 must stop the rule"
}

test_the_window_starts_at_todays_midnight() {
    local script
    script="$(cat "$SCRIPT")"

    # Picking today shows today, including the meeting that already happened; starting
    # the window at "now" would leave the day looking empty by the evening.
    assert_contains "$script" 'window_start = now.replace(hour=0, minute=0, second=0, microsecond=0)' \
        "the agenda window must start at the beginning of today"
}

test_unreadable_source_is_reported_not_fatal() {
    local dir output
    dir="$(mktemp -d)"
    write_fixture "$dir/ok.ics"

    output="$("$PYTHON" "$SCRIPT" --days 100000 --source "Good=$dir/ok.ics" --source "Missing=$dir/nope.ics" 2>&1)"
    rm -rf "$dir"

    assert_contains "$output" '"source": "Missing"' "a broken source must be reported"
    assert_contains "$output" '"summary": "Standup"' \
        "the sources that did load must still be returned"
    assert_contains "$output" '"errors"' "the output must carry an errors list"
}

test_service_reads_the_configured_sources() {
    local service config
    service="$(cat "$SERVICE")"
    config="$(cat "$CONFIG")"

    assert_contains "$config" 'CONFIG_GLOBAL_LIST(CalendarSourceList, calendarSources, {})' \
        "calendars must be configured as a list"
    assert_contains "$config" 'CONFIG_PROPERTY(QString, url, {})' "a source needs its address"
    assert_contains "$service" 'Quickshell.shellPath("scripts/calendar_events.py")' \
        "the reading belongs to the script, not to QML"
    assert_contains "$service" '"--source", `${name}=${url}`' "each source must be passed through"
    assert_contains "$service" 'onSourcesChanged: root.refresh()' "editing the list must refresh"
    assert_contains "$service" 'interval: 5 * 60 * 1000' "a calendar must not go stale"
    assert_contains "$service" 'start: new Date(item.startMs)' \
        "the UI needs dates, not raw milliseconds"
}

test_the_selected_day_drives_the_agenda() {
    local popout month
    popout="$(cat "$POPOUT")"
    month="$(cat "$MONTH")"

    # The list under the grid is the selected day opened up, not a separate feed.
    assert_contains "$popout" 'readonly property var selectedEvents: CalendarEvents.eventsOn(root.selectedDate)' \
        "the agenda must follow the selected day"
    assert_contains "$popout" 'text: root.selectedLabel' "and be headed by which day it is"
    assert_contains "$popout" 'onDayClicked: date => root.select(date)' \
        "picking a day in the grid must move the list"
    assert_contains "$popout" 'if (date.getMonth() !== root.viewDate.getMonth()' \
        "clicking a day of the adjacent month must follow it there"
    assert_contains "$month" 'if (root.isMarked(dayItem.model.date))' \
        "the marked day must be highlighted in the grid"
    assert_contains "$popout" 'root.eventTime(eventRow.modelData)' "a timed event shows its time"
    assert_contains "$month" 'CalendarEvents.hasEventsOn(dayItem.model.date)' \
        "days with events must be marked in the grid"
    assert_contains "$(cat "$SERVICE")" 'return root.events.filter(event => event.start.getTime() < end && event.end.getTime() > start);' \
        "a day's events are the ones that overlap it, so multi-day events show"
}

test_the_month_lives_in_one_place() {
    local grids dashboard
    # The bar popout and the dashboard used to draw the same month twice. One MonthGrid in
    # the tree is what keeps them from drifting apart again.
    grids="$(grep -rl 'MonthGrid {' "$REPO_ROOT/shell" --include='*.qml' | wc -l)"
    assert_eq "1" "$grids" "the month grid must exist once, in the shared view"

    dashboard="$(cat "$REPO_ROOT/shell/modules/dashboard/dash/Calendar.qml")"
    assert_contains "$dashboard" 'CalendarMonth {' "the dashboard must use the shared view"
    assert_contains "$dashboard" 'onMonthShifted: delta => root.shiftMonth(delta)' \
        "and leave its own date where the dashboard already stored it"
    assert_contains "$(cat "$MONTH")" 'disabled: !root.selectable' \
        "the dashboard's month is not clickable, the popout's is"
}

test_the_empty_agenda_offers_the_way_out() {
    local popout
    popout="$(cat "$POPOUT")"

    assert_contains "$popout" 'qsTr("No calendars yet - click to add one")' \
        "an empty agenda must offer the way to configure one"
    assert_contains "$popout" 'onClicked: root.openCalendarSettings()' \
        "and the row has to act on it"
    assert_contains "$popout" 'disabled: eventRow.modelData !== null || CalendarEvents.configured' \
        "only the hint row is clickable, not an event"
    assert_contains "$popout" 'PageDictionary.subPageIdxFor("services/CalendarPage.qml")' \
        "the page is looked up, not hardcoded"
}

test_calendar_settings_page_is_reachable() {
    local page registry dictionary
    page="$(cat "$PAGE")"
    registry="$(cat "$REGISTRY")"
    dictionary="$(cat "$DICTIONARY")"

    assert_contains "$page" 'GlobalConfig.services.calendarSources.insert' "the page must add sources"
    assert_contains "$page" 'GlobalConfig.services.calendarSources.remove(index)' "and remove them"
    assert_contains "$page" 'Secret address in iCal format' \
        "Google Calendar's export has to be named, or nobody finds it"
    assert_contains "$registry" 'Component { CalendarPage {} }' "the page must be registered"
    assert_contains "$dictionary" 'pagePath: "services/CalendarPage.qml"' "and be searchable"
}

test_the_clock_reaches_the_calendar_by_click_and_by_hover() {
    local clock
    clock="$(cat "$CLOCK")"

    # The popout is the only way to reach the agenda, so both have to open it.
    assert_contains "$clock" 'onEntered: root.hoverOpen()' \
        "hovering the clock must open the calendar"
    assert_contains "$clock" 'Config.bar.showOnHover' "hover opening honours the bar's own setting"
    assert_contains "$clock" '!Config.bar.popouts.clock' \
        "and the calendar popout switch"
    # A big popout must not appear because the pointer crossed the clock on its way
    # to the tray, so the open is deferred.
    assert_contains "$clock" 'interval: 150' "hover opening waits before it fires"
    assert_contains "$clock" 'onExited: root.hoverClose()' \
        "leaving before the delay cancels it"
    assert_contains "$clock" 'hoverTimer.stop()' "a click settles a pending hover open"
    assert_contains "$(cat "$BAR_CONFIG")" 'CONFIG_PROPERTY(bool, clock, true)' \
        "the calendar popout is on by default, or the agenda is unreachable"
}

test_the_calendar_updates_itself() {
    local script service popout

    script="$(cat "$SCRIPT")"
    service="$(cat "$SERVICE")"
    popout="$(cat "$POPOUT")"

    # A Google calendar changes when it changes; the shell has to come back for it
    # rather than showing whatever it read at startup.
    assert_contains "$service" 'interval: 5 * 60 * 1000' "the agenda must re-read on a timer"
    assert_contains "$service" 'running: root.configured' "and only when there is something to read"
    assert_contains "$popout" 'root.refreshOnOpen()' "opening the popout must refresh what is shown"
    assert_contains "$popout" 'function onHasCurrentChanged(): void' "the refresh hangs off the popout opening"

    # Revalidation is what makes the frequent poll cheap: an unchanged calendar answers
    # 304 and no body is transferred.
    assert_contains "$script" 'headers["If-None-Match"] = etag' "fetches must revalidate with the ETag"
    assert_contains "$script" 'if error.code == 304 and cached.exists():' "a 304 must reuse the cached copy"
    assert_contains "$script" 'add_argument("--refresh", action="store_true"' "and a forced re-fetch must be possible"
    assert_contains "$service" 'calendar_events.py"), "--days", String(root.days)]' "the days window is still passed"
    assert_contains "$service" 'if (force)' "forcing bypasses the on-disk copy"
    assert_contains "$(cat "$PAGE")" 'CalendarEvents.refresh(true)' "Refresh in Nexus forces a re-fetch"
}

run_tests
