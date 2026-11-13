#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$REPO_ROOT/shell/modules/nexus/common"
MODEL="$COMMON/updateModel.js"
CHECKER="$REPO_ROOT/shell/services/UpdateChecker.qml"
STATUS="$REPO_ROOT/shell/services/UpdateStatus.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/UpdatesPage.qml"
TIMELINE="$COMMON/UpdateTimeline.qml"
POPOUT="$REPO_ROOT/shell/modules/bar/popouts/Updates.qml"
INDICATOR="$REPO_ROOT/shell/modules/bar/components/UpdateIndicator.qml"

commit() {
    printf '{hash:"%s",fullHash:"%s",subject:"%s",author:"Solanaceae",date:"today",isMerge:%s}' \
        "$1" "$1" "$2" "${3:-false}"
}

test_a_commit_list_marks_the_installed_commit_and_what_is_new() {
    local commits
    commits="[$(commit aaa 'feat: one'),$(commit bbb 'fix: two'),$(commit ccc 'chore: three')]"

    check_js "states are read off the installed commit" "$MODEL" "Model" "
const out = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: $commits, installedCommitHash: 'bbb'});
assert.deepStrictEqual(out.map(e => e.state), ['available', 'current', 'past']);
assert.deepStrictEqual(out.map(e => e.title), ['one', 'two', 'three'], 'the conventional-commit prefix is stripped');
"

    check_js "an unknown install marks the newest commit as current" "$MODEL" "Model" "
const out = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: $commits, installedCommitHash: ''});
assert.deepStrictEqual(out.map(e => e.state), ['current', 'past', 'past']);
"
}

test_a_release_list_marks_the_installed_version() {
    check_js "releases above the installed one are available" "$MODEL" "Model" "
const out = Model.deriveEntries({versionSummaryMode: true, availableVersions: ['2.9.0', '2.8.0', '2.7.0'], currentVersion: '2.7.0', commits: [], installedCommitHash: ''});
assert.deepStrictEqual(out.map(e => e.state), ['available', 'available', 'current']);
assert.strictEqual(out[0].label, '2.9.0', 'the tag is shown without its v');
assert.ok(out[0].url.endsWith('/releases/tag/2.9.0'), 'each release links to its notes');
"

    check_js "a version the list does not contain leaves the newest as current" "$MODEL" "Model" "
const out = Model.deriveEntries({versionSummaryMode: true, availableVersions: ['2.9.0', '2.8.0'], currentVersion: '9.9.9', commits: [], installedCommitHash: ''});
assert.deepStrictEqual(out.map(e => e.state), ['current', 'past']);
"

    check_js "release notes travel with the release they belong to" "$MODEL" "Model" "
const out = Model.deriveEntries({versionSummaryMode: true, availableVersions: ['2.9.0'], currentVersion: '2.8.0', commits: [{subject: '2.9.0', details: 'what changed'}], installedCommitHash: ''});
assert.strictEqual(out[0].details, 'what changed');
"
}

test_merges_and_housekeeping_are_internal_but_the_installed_commit_is_not() {
    check_js "internal commits are the bookkeeping ones" "$MODEL" "Model" "
assert.strictEqual(Model.isInternal({isRelease: false, isMerge: true, state: 'available', type: ''}), true, 'a merge carries no change of its own');
assert.strictEqual(Model.isInternal({isRelease: false, isMerge: false, state: 'available', type: 'chore'}), true);
assert.strictEqual(Model.isInternal({isRelease: false, isMerge: false, state: 'available', type: 'feat'}), false, 'a feature is what the reader came for');
assert.strictEqual(Model.isInternal({isRelease: false, isMerge: true, state: 'current', type: ''}), false, 'the installed commit is always shown');
assert.strictEqual(Model.isInternal({isRelease: true, isMerge: false, state: 'available', type: ''}), false);
"
}

test_a_collapsed_commit_list_shows_the_two_ends_of_the_gap() {
    local commits
    commits="[$(commit a1 'feat: a'),$(commit a2 'feat: b'),$(commit a3 'feat: c'),$(commit a4 'feat: d'),$(commit cur 'feat: installed'),$(commit p1 'feat: old')]"

    check_js "collapsed keeps one pending commit and the installed one" "$MODEL" "Model" "
const entries = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: $commits, installedCommitHash: 'cur'});
const out = Model.disclosure(entries, false, false, 3);
assert.deepStrictEqual(out.entries.map(e => e.id), ['a1', 'cur'], 'the run in between is one disclosure away');
assert.strictEqual(out.hiddenByCap, 4, 'the hidden run is counted for the button');
assert.strictEqual(out.capped, true);
assert.strictEqual(out.isCommitList, true);
"

    check_js "expanding shows the whole run" "$MODEL" "Model" "
const entries = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: $commits, installedCommitHash: 'cur'});
const out = Model.disclosure(entries, true, false, 3);
assert.strictEqual(out.entries.length, 6);
assert.strictEqual(out.hiddenByCap, 0);
"

    check_js "a release list keeps three per group" "$MODEL" "Model" "
const versions = ['9.0.0','8.0.0','7.0.0','6.0.0','5.0.0','4.0.0','3.0.0'];
const entries = Model.deriveEntries({versionSummaryMode: true, availableVersions: versions, currentVersion: '7.0.0', commits: [], installedCommitHash: ''});
const out = Model.disclosure(entries, false, false, 3);
assert.deepStrictEqual(out.entries.map(e => e.label), ['9.0.0','8.0.0','7.0.0','6.0.0','5.0.0','4.0.0'], 'two pending, the installed one, and three earlier releases');
assert.strictEqual(out.hiddenByCap, 1);
assert.strictEqual(out.capped, true);
"
}

test_internal_commits_are_counted_and_can_be_revealed() {
    local commits
    commits="[$(commit n1 'feat: visible'),$(commit n2 'chore: build noise'),$(commit n3 'refactor: internal'),$(commit n4 'Merge pull request #12 from x/y' true)]"

    check_js "hidden internal commits are counted, not shown" "$MODEL" "Model" "
const entries = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: $commits, installedCommitHash: 'n1'});
const collapsed = Model.disclosure(entries, false, false, 3);
assert.deepStrictEqual(collapsed.entries.map(e => e.id), ['n1'], 'only the installed commit survives the defaults');
assert.strictEqual(collapsed.internalCount, 3);

const shown = Model.disclosure(entries, true, true, 3);
assert.strictEqual(shown.entries.length, 4, 'revealing internal changes shows them');
"
}

test_release_notes_are_readable_text() {
    check_js "markdown is reduced to lines" "$MODEL" "Model" "
const body = ['## What is Changed', '* install the unit by [me](https://example.com)', '- fixed a crash', '', '# Skipped heading'].join('\n');
assert.strictEqual(Model.formatNotes(body), '• install the unit by me\n• fixed a crash');
assert.strictEqual(Model.formatNotes(body, 1), '• install the unit by me', 'the card caps how much it prints');
assert.strictEqual(Model.formatNotes(''), '');
"
}

test_the_page_previews_the_selected_entry_or_the_newest_release() {
    check_js "the selected entry wins, otherwise the newest available release" "$MODEL" "Model" "
const entries = Model.deriveEntries({versionSummaryMode: true, availableVersions: ['3.0.0','2.0.0','1.0.0'], currentVersion: '2.0.0', commits: [], installedCommitHash: ''});
assert.strictEqual(Model.previewEntry(entries, '3.0.0').label, '3.0.0');
assert.strictEqual(Model.previewEntry(entries, '1.0.0').label, '1.0.0', 'an older selection previews its own notes');
assert.strictEqual(Model.previewEntry(entries, 'gone').label, '3.0.0', 'a stale selection falls back to the update');
assert.strictEqual(Model.entryById(entries, 'gone'), null, 'and the page sees no selection at all');
"

    check_js "a development build has no release to preview" "$MODEL" "Model" "
const entries = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: [], installedCommitHash: ''});
assert.strictEqual(Model.previewEntry(entries, ''), null);
"
}

test_every_entry_field_always_exists() {
    check_js "one shape for both modes" "$MODEL" "Model" "
const fields = ['author','date','details','id','isMerge','isRelease','label','state','subject','title','type','url'];
const releases = Model.deriveEntries({versionSummaryMode: true, availableVersions: ['2.0.0'], currentVersion: '1.0.0', commits: [], installedCommitHash: ''});
const commits = Model.deriveEntries({versionSummaryMode: false, availableVersions: [], currentVersion: 'unknown', commits: [$(commit zz 'chore: x')], installedCommitHash: ''});
for (const entry of [releases[0], commits[0]])
    assert.deepStrictEqual(Object.keys(entry).sort(), fields, 'no caller has to guard for a missing field');
"
}

test_a_failed_check_is_not_reported_as_uptodate() {
    assert_file_contains "$CHECKER" 'FAIL|GitHub is unreachable' \
        "the check has to be able to say it could not reach GitHub"
    assert_file_contains "$CHECKER" 'if (root.checkError === "")' \
        "only a check that answered may advance lastCheckSuccessMs"
    assert_file_contains "$CHECKER" 'root.lastCheckSuccessMs = Date.now()' \
        "the last success is what the failure notice reports"
}

test_a_manual_check_ignores_the_periodic_setting() {
    assert_file_contains "$CHECKER" 'if (!manual && !root.checkingEnabled)' \
        "the setting gates automatic checks only, or the page becomes a dead end"
    assert_file_contains "$PAGE" 'UpdateChecker.checkNow()' "the page asks for a manual check"
    assert_file_contains "$CHECKER" 'function checkInBackground' \
        "and automatic checks have their own entry point"
    assert_file_not_contains "$CHECKER" 'checkUpdates(' "the positional-flag API is gone"
}

test_the_handoff_is_a_state_the_service_owns() {
    assert_file_contains "$CHECKER" 'enum Handoff' "the handoff is one state"
    assert_file_contains "$CHECKER" 'root.probeHandoff();' \
        "a shell that starts during an update has to ask the lock, not assume none"
    assert_file_contains "$CHECKER" 'handoffProbeIntervalMs: 2000' "the probe interval is named"
    assert_file_contains "$CHECKER" 'handoffGraceMs: 10000' "the grace is named"
    assert_file_contains "$PAGE" 'UpdateChecker.markHandoff(version)' "the page hands off to the service"
    assert_file_contains "$STATUS" 'UpdateChecker.Handoff.Running' "the card says an update is running"
    assert_file_not_contains "$CHECKER" 'wl-copy' "copying a command is a surface's job"
}

test_one_description_for_every_surface() {
    assert_file_contains "$STATUS" 'function describe(selection, launchFailed)' \
        "one function decides what the card says"
    assert_file_contains "$PAGE" 'UpdateStatus.describe(root.selection, root.launchFailed)' \
        "the page renders it"
    assert_file_contains "$POPOUT" 'UpdateStatus.describe(null, false)' "and so does the popout"
    assert_file_contains "$INDICATOR" 'root.status.icon' "and the indicator"
    assert_file_not_contains "$PAGE" 'readonly property string primaryActionText' \
        "the page keeps no second copy of the wording"
    assert_file_not_contains "$CHECKER" 'statusTitle' "nor does the service"
}

test_the_history_is_grouped_and_reachable_by_keyboard() {
    assert_file_not_contains "$TIMELINE" "What you'll get" \
        "the pending rows need no heading: the card is already 'Commit history'"
    assert_file_contains "$TIMELINE" 'qsTr("Your version")' "current group"
    assert_file_contains "$TIMELINE" 'qsTr("Earlier")' "past group"
    assert_file_contains "$TIMELINE" 'activeFocusOnTab: !row.isHeader' "timeline rows are in the tab order"
    assert_file_contains "$TIMELINE" 'Accessible.role: Accessible.ListItem' "and announce what they are"
    assert_file_contains "$TIMELINE" 'Keys.onPressed' "Enter and Space select a row"
    assert_file_not_contains "$TIMELINE" 'Flickable' "the list scrolls with the page instead of inside it"
}

test_the_rows_do_not_depend_on_the_selection() {
    assert_file_contains "$PAGE" 'entries: root.shown.entries' \
        "the timeline is handed the disclosure result, which the selection does not touch"
    assert_file_contains "$PAGE" 'disclosure(root.entries, root.timelineExpanded, root.showInternal' \
        "and nothing in that chain reads the selection"
    assert_file_contains "$TIMELINE" 'height: row.isHeader ? root.headerHeight' \
        "a selected row grows in place instead"
    assert_file_contains "$TIMELINE" 'Column {' "and the column reflows around it"
}

test_the_update_rows_have_one_owner() {
    assert_file_contains "$PAGE" 'text: qsTr("Check for updates automatically")' \
        "the page owns whether checking happens"
    assert_file_not_contains "$PAGE" 'Show Update Indicator' "and does not also own the indicator"
    assert_file_contains "$PAGE" 'label: qsTr("Open backup folder")' "maintenance has its own section"
    assert_file_contains "$PAGE" 'label: qsTr("Update channel")' "and the channel is a setting"
}

test_the_abandoned_in_page_runner_stays_deleted() {
    assert_file_not_contains "$CHECKER" 'function startUpdate' \
        "the runner referenced properties that never existed"
    assert_file_not_contains "$CHECKER" 'updateProgress' "and its progress state is gone"
    assert_file_not_contains "$CHECKER" 'processLineBuffer' "along with its output buffer"
}

test_the_dialogs_share_one_frame() {
    assert_file_contains "$COMMON/NexusDialog.qml" 'property string confirmText' "the frame owns the buttons"
    assert_file_contains "$COMMON/UninstallDialog.qml" 'NexusDialog {' "the uninstaller renders it"
    assert_file_contains "$COMMON/UpdateConfirmDialog.qml" 'NexusDialog {' "and so does the restore confirmation"
    assert_file_not_contains "$COMMON/UninstallDialog.qml" 'Elevation {' "neither keeps its own copy of the chrome"
    assert_file_not_contains "$COMMON/UpdateConfirmDialog.qml" 'Elevation {' "neither keeps its own copy of the chrome"
}

test_update_links_open_the_updates_subpage() {
    assert_file_contains "$POPOUT" 'initialPageIdx: "updates", initialSubPage: "updates"' "the popout opens the Updates page by key"
    assert_file_contains "$INDICATOR" 'initialPageIdx: "updates", initialSubPage: "updates"' "the indicator opens the same page"
    assert_file_contains "$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarUpdates.qml" \
        'goToSubPage(root.updatesPageIdx, "updates")' \
        "the taskbar settings link opens the Updates subpage"
}

test_the_updates_page_index_has_one_lookup() {
    local copies
    copies="$(grep -rl 'indexForKey("updates")' "$REPO_ROOT/shell" | wc -l | tr -d ' ')"
    assert_eq "0" "$copies" "the three copies of the lookup belong to PageRegistry"
    assert_file_contains "$REPO_ROOT/shell/modules/nexus/PageRegistry.qml" 'updatesPageIdx' \
        "which resolves it once"
}

run_tests
