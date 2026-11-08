#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO_ROOT/shell/services/UpdateChecker.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/UpdatesPage.qml"
TIMELINE="$REPO_ROOT/shell/modules/nexus/common/UpdateTimeline.qml"
POPOUT="$REPO_ROOT/shell/modules/bar/popouts/Updates.qml"
BARUPDATES="$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarUpdates.qml"

test_a_failed_check_is_not_reported_as_uptodate() {
    assert_file_contains "$UPDATE" 'FAIL|GitHub is unreachable' \
        "the check has to be able to say it could not reach GitHub"
    assert_file_matches "$UPDATE" '^\s*exit 1$' \
        "and it has to exit non-zero so the failure survives a lost message"
    assert_file_contains "$UPDATE" 'property string checkError: ""' \
        "the page needs a reason to show"
    assert_file_contains "$UPDATE" 'if (root.checkError === "")' \
        "only a check that answered may advance lastCheckSuccessMs"
    assert_file_contains "$UPDATE" 'root.lastCheckSuccessMs = Date.now()' \
        "the last success is what the failure notice reports"
}

test_a_manual_check_ignores_the_periodic_setting() {
    assert_file_contains "$UPDATE" 'if (!manual && !GlobalConfig.general.checkUpdates) return;' \
        "the setting gates automatic checks only, or the page becomes a dead end"
    assert_file_contains "$PAGE" 'UpdateChecker.checkUpdates("", false, true)' \
        "the page has to ask for a manual check"
    assert_file_contains "$UPDATE" 'running: GlobalConfig.general.checkUpdates && root.loaded' \
        "the periodic timer is what the setting still gates"
    assert_file_contains "$UPDATE" 'Component.onCompleted: localCommitProcess.running = true' \
        "the installed version is read whatever the setting says"
}

test_the_page_can_say_it_does_not_know() {
    assert_file_contains "$UPDATE" "Couldn't check for updates" "failed state title"
    assert_file_contains "$UPDATE" 'Update checking is off' "disabled state title"
    assert_file_contains "$PAGE" 'No history yet' "empty history state"
    assert_file_contains "$POPOUT" 'UpdateChecker.statusTitle' \
        "the popout reuses the page's wording instead of its own copy"
    assert_file_contains "$PAGE" 'UpdateChecker.statusDetailFor(root.nowMs)' \
        "and so does the page, with its own clock"
}

test_the_updater_handoff_blocks_a_second_install() {
    assert_file_contains "$UPDATE" 'function markUpdaterLaunched' \
        "a launch has to be recorded, not just performed"
    assert_file_contains "$PAGE" 'UpdateChecker.markUpdaterLaunched(version)' \
        "the page hands off to the service"
    assert_file_contains "$UPDATE" 'updaterPending' \
        "the pending state drives the handoff card"
    assert_file_contains "$PAGE" 'Open terminal again' \
        "and offers a way back to the terminal"
    assert_file_contains "$PAGE" 'copyUpdaterCommand' \
        "with the command to run if no terminal opened"
}

test_the_history_is_grouped_and_reachable_by_keyboard() {
    assert_file_not_contains "$TIMELINE" "What you'll get" \
        "the pending rows need no heading: the card is already 'Commit history'"
    assert_file_contains "$TIMELINE" 'qsTr("Your version")' "current group"
    assert_file_contains "$TIMELINE" 'qsTr("Earlier")' "past group"
    assert_file_contains "$TIMELINE" 'activeFocusOnTab: row.isInteractive' \
        "timeline rows are in the tab order"
    assert_file_contains "$TIMELINE" 'Accessible.role: row.isAction ? Accessible.Button : Accessible.ListItem' \
        "and announce what they are"
    assert_file_contains "$TIMELINE" 'Keys.onPressed' "Enter and Space select a row"
    assert_file_not_contains "$TIMELINE" 'Flickable' \
        "the list scrolls with the page instead of inside it"
    assert_file_not_contains "$TIMELINE" 'timelineSelectionEnabled' \
        "selection is always on, so the flag that said so is gone"
    assert_file_not_contains "$TIMELINE" 'id: stateText' \
        "the per-row state badge repeats the group header and is gone"
    assert_file_contains "$TIMELINE" 'root.stateLabel(row.entry.state)' \
        "the state is still announced to a screen reader"
}

test_a_development_list_opens_on_the_two_ends_of_the_gap() {
    assert_file_contains "$TIMELINE" 'return state === "past" ? 0 : 1;' \
        "a dev list shows the newest commit and the one installed, nothing else"
    assert_file_contains "$TIMELINE" 'qsTr("Show all commits (%1)").arg(hidden)' \
        "the run in between is one disclosure away"
    assert_file_contains "$UPDATE" 'LOCAL_COMMIT%x1f' \
        "the installed commit is read even when it is further back than one page"
    assert_file_contains "$UPDATE" 'if (line.startsWith("COMMIT\u001f"))' \
        "and it must not move the offset the next page is fetched from"
}

test_the_changelog_the_check_fetched_is_shown() {
    assert_file_contains "$PAGE" 'details: bodies[root.normalizeVersion(versions[i])]' \
        "release bodies travel with the entry"
    assert_file_contains "$PAGE" 'text: qsTr("Release notes")' "there is a place to read them"
    assert_file_contains "$PAGE" 'Full release notes' "with a link to GitHub"
}

test_one_owner_per_update_setting() {
    assert_file_contains "$PAGE" 'text: qsTr("Check for updates automatically")' \
        "the page owns whether checking happens"
    assert_file_not_contains "$PAGE" 'Show Update Indicator' \
        "and does not also own the indicator"
    assert_file_not_contains "$BARUPDATES" 'GlobalConfig.general.checkUpdates = checked' \
        "the taskbar page no longer writes the checking setting"
    assert_file_contains "$BARUPDATES" 'Turn on update checking' \
        "it points at the page that does"
}

test_the_abandoned_in_page_runner_stays_deleted() {
    assert_file_not_contains "$UPDATE" 'function startUpdate' \
        "the runner referenced properties that never existed"
    assert_file_not_contains "$UPDATE" 'updateProgress' "and its progress state is gone"
    assert_file_not_contains "$UPDATE" 'processLineBuffer' "along with its output buffer"
}

run_tests
