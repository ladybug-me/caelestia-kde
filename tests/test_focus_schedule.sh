#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/Focus.qml"
CALENDAR="$REPO_ROOT/shell/services/CalendarEvents.qml"
NOTIFS="$REPO_ROOT/shell/services/Notifs.qml"
CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/notifsconfig.hpp"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/services/FocusPage.qml"
HUB="$REPO_ROOT/shell/modules/nexus/pages/services/NotificationsPage.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"

test_schedules_are_configured_as_windows() {
    local config
    config="$(cat "$CONFIG")"

    assert_contains "$config" 'CONFIG_GLOBAL_PROPERTY(bool, focusEnabled, false)' \
        "focus has to be opt-in"
    assert_contains "$config" 'CONFIG_GLOBAL_LIST(FocusScheduleList, focusSchedules, {})' \
        "schedules are a list of windows"
    assert_contains "$config" 'CONFIG_PROPERTY(QStringList, days, {})' "a window needs its days"
    assert_contains "$config" 'CONFIG_PROPERTY(QString, start' "and a start time"
    assert_contains "$config" 'CONFIG_PROPERTY(QString, end' "and an end time"
    assert_contains "$config" 'CONFIG_GLOBAL_PROPERTY(QStringList, focusAllowlist, QStringList())' \
        "apps allowed through the session have to be configurable"
    assert_contains "$config" 'CONFIG_GLOBAL_PROPERTY(bool, focusCalendar, false)' \
        "following the calendar has to be opt-in as well"
}

test_a_running_meeting_can_start_a_session() {
    local service calendar page
    service="$(cat "$SERVICE")"
    calendar="$(cat "$CALENDAR")"
    page="$(cat "$PAGE")"

    assert_contains "$service" 'readonly property var activeMeeting' \
        "a meeting in progress is the second source of sessions"
    assert_contains "$service" 'CalendarEvents.eventsOn(root.now).find(event => !event.allDay && event.start <= root.now && root.now < event.end)' \
        "an event counts while it runs, and an all-day entry never does"
    assert_contains "$service" 'readonly property bool active: root.enabled && (root.activeSchedule !== null || root.activeMeeting !== null)' \
        "either source opens the session"
    assert_contains "$service" 'root.activeMeeting.summary || qsTr("Meeting")' \
        "the meeting names the session"
    assert_contains "$service" 'return Time.clockTime(root.activeMeeting.end)' \
        "and its end time is formatted the way the bar formats time"
    assert_contains "$service" 'function onEventsChanged(): void' \
        "a calendar that has just been read has to be acted on"
    # The calendar's own cadence belongs to the calendar: focus asks for a refresh instead of
    # reaching into another service's timer.
    assert_contains "$service" 'onTriggered: CalendarEvents.refresh()' \
        "a meeting start is a deadline, so focus asks the calendar to refresh every minute"
    assert_contains "$service" 'running: root.followCalendar && CalendarEvents.configured' \
        "and only while it is following that calendar"
    assert_contains "$page" 'GlobalConfig.notifs.focusCalendar = checked' "and the page can switch it on"
}

test_overnight_windows_belong_to_the_day_they_started() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" 'function scheduleActive(schedule: var, at: date): bool' \
        "the window logic must be one testable function"
    # 22:00-07:00 is a normal focus window; taken literally it would never match.
    assert_contains "$service" 'const yesterday = new Date(at.getFullYear(), at.getMonth(), at.getDate() - 1)' \
        "an overnight window must check the day it started on"
    assert_contains "$service" 'if (start < 0 || end < 0 || start === end)' \
        "a malformed or empty window must not match"
    assert_contains "$service" 'days.length === 0 || days.includes(day)' \
        "a window without days has to mean every day"
}

test_focus_only_undoes_the_dnd_it_turned_on() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" 'Notifs.setDndSilently(true)' \
        "a session must not announce itself with a toast"
    assert_contains "$service" 'if (root._applied)' \
        "DND the user set by hand must survive the session ending"
    assert_contains "$service" 'if (Notifs.dnd)' \
        "clearing DND twice must not fight the user"
    assert_contains "$service" 'interval: 30 * 1000' "the window has to be re-evaluated as time passes"
}

test_allowlisted_apps_pass_through_the_session() {
    local notifs
    notifs="$(cat "$NOTIFS")"

    # The popup and the sound ask the same question, so the DND + focus + fullscreen
    # policy is stated once instead of copied into each decision.
    assert_contains "$notifs" 'function isSilenced(appName: string): bool' \
        "silencing must be one predicate"
    assert_contains "$notifs" 'if (props.dnd && !Focus.allows(appName))' \
        "an allowlisted app must still be heard during a session"
    assert_contains "$notifs" 'return !root.isSilenced(appName);' \
        "the popup decision must go through that predicate"
    assert_contains "$notifs" 'return !root.isSilenced(notif.appName);' \
        "and so must the sound decision"
    local popup_decision sound_decision
    popup_decision="$(sed -n '/function shouldShowPopup/,/^    }/p' <<<"$notifs")"
    sound_decision="$(sed -n '/function shouldPlaySound/,/^    }/p' <<<"$notifs")"
    assert_not_contains "$popup_decision" 'hasFullscreen' \
        "the popup decision must not restate the fullscreen rule"
    assert_not_contains "$sound_decision" 'hasFullscreen' \
        "neither must the sound decision"
    assert_contains "$notifs" 'root.shouldShowPopup(notif.appName)' \
        "the D-Bus path must pass the app name through"
    assert_contains "$notifs" 'root.shouldShowPopup(params.appName ?? "")' \
        "shell-raised notifications must pass theirs too"
    assert_contains "$(cat "$SERVICE")" 'function allows(appName: string): bool' \
        "the allowlist must be the focus service's to answer"
    assert_contains "$(cat "$SERVICE")" 'root.allowlist.some(allowed => allowed.toLowerCase() === name)' \
        "and has to ignore the case the notifier happens to use"
}

test_focus_page_is_reachable_from_notifications() {
    local page hub registry
    page="$(cat "$PAGE")"
    hub="$(cat "$HUB")"
    registry="$(cat "$REGISTRY")"

    assert_contains "$page" 'GlobalConfig.notifs.focusSchedules.insert' "the page must add schedules"
    assert_contains "$page" 'GlobalConfig.notifs.focusSchedules.remove(index)' "and remove them"
    assert_contains "$page" 'start: startField.text.trim()' "the times come straight out of the fields"
    assert_contains "$page" 'startField.text = root.defaultStart' "which reset to the defaults after adding"
    assert_contains "$page" 'GlobalConfig.notifs.focusAllowlist = apps' "and edit the allowlist"
    assert_contains "$page" 'AppPickerRow {' "apps are picked from the installed ones"
    assert_contains "$page" 'onSelected: name => root.addAllowedApp(name)' "not typed in from memory"
    assert_not_contains "$page" 'allowInput' "the free-text allow field is gone"
    assert_contains "$hub" 'root.nState.openSubPage(4)' "the hub must link to it"
    assert_contains "$registry" 'Component { FocusPage {} }' "the page must be registered"
}

run_tests
