#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFS="$REPO_ROOT/shell/services/Notifs.qml"
QUERY_JS="$REPO_ROOT/shell/services/notifquery.js"
SCHEMA="$REPO_ROOT/shell/plugin/src/Caelestia/Config/notifsconfig.hpp"
POPUP="$REPO_ROOT/shell/modules/notifications/Notification.qml"
DOCK="$REPO_ROOT/shell/modules/sidebar/NotifDock.qml"
DOCK_LIST="$REPO_ROOT/shell/modules/sidebar/NotifDockList.qml"
GROUP="$REPO_ROOT/shell/modules/sidebar/NotifGroup.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/audio/NotificationSilencingPage.qml"

# What a search looks at is pure, so it is executed rather than grepped: the script
# below runs against notifquery.js with node's assert.
check_notif_query() { check_js "$1" "$QUERY_JS" Query "$2"; }


test_turning_an_app_off_is_a_setting_not_a_runtime_habit() {
    assert_file_contains "$SCHEMA" "CONFIG_GLOBAL_PROPERTY(QStringList, mutedApps" \
        "the list has to survive a restart, so it is config and not state"
    assert_file_contains "$NOTIFS" 'return GlobalConfig.notifs.mutedApps.includes(appName);' \
        "one place decides what 'muted' means"
}

test_muting_an_app_drops_what_it_already_sent() {
    local mute_block
    mute_block="$(sed -n '/function muteApp(appName: string): void {/,/^    }$/p' "$NOTIFS")"

    assert_file_contains "$NOTIFS" 'function muteApp(appName: string): void' \
        "the popup and the settings page both go through this"
    assert_file_contains "$NOTIFS" 'GlobalConfig.notifs.mutedApps = Array.from(GlobalConfig.notifs.mutedApps).concat([appName]);' \
        "muting records the app"
    assert_file_contains "$NOTIFS" 'root.list = root.list.filter(n => n.appName !== appName);' \
        "and drops what it already sent, or the next banner looks like the mute did not stick"
    assert_file_contains "$NOTIFS" 'for (const notif of dropped)' "closing them is what tells the sender"
    # Closing is what uncounts a notification. Touching the counter here as well counted
    # the same notification twice, and muting one app hid every other app's notifications.
    assert_not_contains "$mute_block" 'openCount' \
        "the unread count is moved by filing and closing, never by a caller patching it"
}

# A muted notification is answered, not filed: the sender gets its close, and the list,
# the unread count and the sound never see it. Building a NotifData to dismiss it counted
# a notification that was never filed, so each muted message ate someone else's unread.
test_a_muted_notification_is_answered_and_never_filed() {
    local block muted_branch order
    block="$(sed -n '/onNotification: notif => {/,/^        }$/p' "$NOTIFS")"
    muted_branch="$(printf '%s\n' "$block" | sed -n '/if (root.isMuted(notif.appName)) {/,/^            }$/p')"

    assert_contains "$block" 'if (root.isMuted(notif.appName)) {' "the notification path checks the mute first"
    assert_contains "$muted_branch" 'notif.dismiss();' "the sender still gets its close"
    assert_not_contains "$muted_branch" 'notifComp.createObject' \
        "and nothing is built that filing would have had to count"

    order="$(printf '%s\n' "$block" | awk '
        /if \(root\.isMuted\(notif\.appName\)\)/ { mute = NR }
        /root\.registerNotification\(comp\)/ { register = NR }
        /Audio\.playNotification\(\)/ { sound = NR }
        END { print (mute && register && sound && mute < register && mute < sound) ? 1 : 0 }
    ')"
    assert_eq "1" "$order" "the mute has to return before anything is registered or played"
}

test_the_popup_offers_the_mute() {
    assert_file_contains "$POPUP" 'icon: "notifications_off"' "the button is on the notification itself"
    assert_file_contains "$POPUP" 'onClicked: Notifs.muteApp(root.modelData.appName)' \
        "and mutes the application that sent it, not the shell"
}

# The filter has to reach every layer that decides what is drawn, or the search box
# narrows nothing: the app list, the notifications inside each app, and the dock that
# owns the query.
test_the_search_reaches_the_list_it_narrows() {
    assert_file_contains "$NOTIFS" 'function matchesQuery(notif: NotifData, query: string): bool' \
        "one definition of what a search matches, over the type it matches"
    assert_file_contains "$NOTIFS" 'NotifQuery.matches(notif.appName, notif.summaryPlain, notif.bodyPlain, query)' \
        "the app, the summary, and the body without its markup"
    assert_file_contains "$DOCK" 'onTextEdited: root.query = searchField.text' "the dock owns the query"
    assert_file_contains "$DOCK" 'filter: root.query' "and passes it to the list"
    assert_file_contains "$DOCK_LIST" 'Notifs.matchesQuery(n, root.filter)' "the app list is filtered"
    assert_file_contains "$GROUP" 'Notifs.matchesQuery(n, root.filter)' "and so are the notifications inside an app"
}

test_a_search_matches_the_app_the_summary_and_the_body() {
    check_notif_query "a search has to look at all three fields" '
assert.strictEqual(Query.matches("firefox", "Invoice 42", "Payment due", "invoice"), true, "the summary matches, case insensitively");
assert.strictEqual(Query.matches("firefox", "hi", "pay the invoice", "INVOICE"), true, "the body matches too");
assert.strictEqual(Query.matches("Firefox", "hi", "there", "fire"), true, "and the app name");
assert.strictEqual(Query.matches("firefox", "hi", "there", "chrome"), false, "something absent matches nothing");
'
}

test_an_empty_search_matches_everything_and_a_missing_field_does_not_throw() {
    check_notif_query "an empty query is not a filter, and a missing field is not a crash" '
assert.strictEqual(Query.matches("firefox", "a", "b", ""), true, "nothing typed shows everything");
assert.strictEqual(Query.matches("firefox", "a", "b", "   "), true, "whitespace is nothing");
assert.strictEqual(Query.matches("firefox", "a", null, null, "a"), true, "a missing body cannot hide a matching app");
assert.strictEqual(Query.matches(null, null, null, "x"), false, "nothing to search matches nothing");
'
}

test_the_search_field_takes_the_keyboard_when_it_appears() {
    assert_file_contains "$DOCK" 'readonly property bool canSearch: root.notifCount > 0 || root.query !== ""' \
        "one answer to whether searching is on offer"
    assert_file_contains "$DOCK" 'enabled: root.canSearch' "and the button is enabled by it, not by its own opacity"
    assert_file_contains "$DOCK" 'searchField.forceActiveFocus();' \
        "a revealed field has to take the keyboard, or typing goes nowhere"
}

test_the_search_and_the_mute_can_be_driven_without_a_pointer() {
    assert_file_contains "$NOTIFS" 'function mute(appName: string): void' "mute is on the IPC"
    assert_file_contains "$NOTIFS" 'function unmute(appName: string): void' "and so is unmute"
    assert_file_contains "$NOTIFS" 'function search(query: string): string' "and the search it would show"
}

test_the_settings_page_shows_both_policies() {
    assert_file_contains "$PAGE" 'GlobalConfig.notifs.mutedApps' "apps that send nothing"
    assert_file_contains "$PAGE" 'GlobalConfig.audio.sounds.disabledNotifApps' "and apps that send quietly"
    assert_file_contains "$PAGE" 'AppPickerRow {' "the applications are picked from what is installed, not typed from memory"
}

run_tests
