#!/usr/bin/env bash
# suite: fast
#
# The smaller findings that are about one file each: a link from a feed, a file another
# local user can read, a path a record pointed at, and a debug line.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"

test_a_link_from_a_feed_is_opened_the_way_a_notification_link_is() {
    assert_file_contains "$SHELL_DIR/modules/sidebar/News.qml" 'Launch.openUrl(delegateItem.link)' \
        "the feed chose the address, so only a web or mail link may be opened from it"
    assert_not_contains "$(cat "$SHELL_DIR/modules/sidebar/News.qml")" 'Qt.openUrlExternally' \
        "which is what the unchecked call let through"
}

test_the_saved_notifications_are_the_users_own() {
    assert_file_contains "$SHELL_DIR/services/Notifs.qml" 'install -m 600 /dev/null' \
        "a one-time code in a notification body must not be readable by another local user"
    assert_file_contains "$SHELL_DIR/services/Notifs.qml" 'chmod 600' \
        "and a file that already exists is tightened rather than left as it was"
}

test_the_debug_log_names_the_settings_it_read_and_not_their_values() {
    local settings="$SHELL_DIR/plugin/src/Caelestia/Settings/settingsfile.cpp"
    assert_file_contains "$settings" 'json.toObject().keys()' \
        "the file carries the API keys, so only which keys it holds may be logged"
    assert_not_contains "$(cat "$settings")" 'qCDebug(lcSettingsFile) << " " << json;' \
        "the whole document must not be printed"
}

test_the_icon_cache_is_not_written_through_a_link() {
    local file
    for file in windowicon.cpp plasmawindowicon.cpp; do
        assert_file_contains "$SHELL_DIR/plugin/src/Caelestia/Services/$file" 'QSaveFile file(path)' \
            "$file writes to a name anyone can predict, so it must replace a planted link, not follow it"
    done
}

test_the_runtime_fallback_is_not_a_path_another_user_could_have_made() {
    assert_file_contains "$SHELL_DIR/utils/Paths.qml" 'root.state}/run' \
        "with no XDG_RUNTIME_DIR the shell keeps its sockets under its own state directory"
    assert_not_contains "$(cat "$SHELL_DIR/utils/Paths.qml")" '/tmp/caelestia-' \
        "a fixed name under /tmp is one another local user can create first"
}

test_the_screenshot_temps_come_from_the_shared_helper() {
    local file
    for file in modules/screenshot/TempScreenshotProcess.qml \
        modules/screenshot/regionSelector/RegionSelection.qml; do
        assert_file_contains "$SHELL_DIR/$file" 'Paths.runtimeTemp("screenshot")' \
            "$file should build its capture directory from Paths, not by hand"
        assert_file_not_contains "$SHELL_DIR/$file" '"XDG_RUNTIME_DIR"' \
            "the fallback decision belongs in one place"
    done
    assert_file_contains "$SHELL_DIR/modules/screenshot/TempScreenshotProcess.qml" 'import qs.utils' \
        "so the file needs the module Paths lives in"
}

test_a_plugin_directory_name_cannot_write_the_list() {
    local script="$SHELL_DIR/scripts/list-plugins.sh"
    assert_file_contains "$script" 'json_string "$name"' \
        "the name is the only thing here that is not a literal"
    assert_file_contains "$script" 'json_string "$path"'

    local dir out
    dir="$(new_tmpdir)"
    mkdir -p "$dir/bundled/a\"b" "$dir/bundled/plain"
    printf '{}\n' > "$dir/bundled/a\"b/metadata.json"
    printf '{}\n' > "$dir/bundled/plain/metadata.json"

    out="$(bash "$script" "$dir/bundled" "$dir/absent")"

    if command -v python3 >/dev/null 2>&1; then
        local parsed
        if parsed="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))' 2>&1)"; then
            assert_eq "2" "$parsed" "a quote in a plugin's name must not end the string it is written into"
        else
            fail "the plugin list is not valid JSON: $parsed"
        fi
    fi
    assert_contains "$out" 'a\"b' "the quote is escaped rather than carried through"
}

test_a_checkout_record_is_only_trusted_when_it_is_this_project() {
    local uninstaller="$SHELL_DIR/services/Uninstaller.qml"
    assert_file_contains "$uninstaller" '[ ! -L "$1/uninstall.sh" ]' \
        "a link there would run whatever it points at, as root"
    assert_file_contains "$uninstaller" '[ ! -L "$1/scripts/setup.sh" ]' \
        "and a directory that is not this project is not what the record meant"
    assert_file_contains "$uninstaller" 'remote get-url origin' \
        "nor is a directory the record points at that no clone of this project produced"
}

test_the_update_counter_reads_a_checkout_it_actually_has() {
    assert_file_contains "$REPO_ROOT/src/bin/caelestia-check-updates" 'REPO="$HOME/.cache/caelestia-kde/upstream.git"' \
        "a count taken against an unset path is always zero"
}

test_the_workspace_effect_only_takes_calls_from_the_shell() {
    local tracker="$SHELL_DIR/kwin-effects/workspace-tracker/workspace_tracker.cpp"
    assert_file_contains "$tracker" 'if (!callerIsShell())' \
        "the session bus offers every local process the same way in"
    assert_file_contains "$tracker" '/proc/%1/exe' \
        "so the caller is identified by what it is running"
    assert_file_contains "$SHELL_DIR/kwin-effects/workspace-tracker/workspace_tracker.hpp" 'protected QDBusContext' \
        "which needs the sender's message, so the effect has to be a D-Bus context"
}

test_a_caller_that_only_calls_itself_the_shell_is_not_the_shell() {
    # A process picks the name it runs under, so the name is checked against the file it is
    # really running: only a program root installed cannot be produced by the caller.
    local tracker="$SHELL_DIR/kwin-effects/workspace-tracker/workspace_tracker.cpp"
    assert_file_contains "$tracker" 'link.canonicalFilePath()' \
        "the binary behind the name is what has to be trusted"
    assert_file_contains "$tracker" 'program.ownerId() != 0' \
        "and a program the caller built in their own home is not one root installed"
    assert_file_contains "$tracker" 'QFileDevice::WriteGroup | QFileDevice::WriteOther' \
        "nor is one anybody else can rewrite"
    assert_file_contains "$tracker" '::getuid()' \
        "a helper that became another user is not the shell the user started"
    assert_file_contains "$tracker" 'qWarning() << "WorkspaceTracker: refusing a call from"' \
        "a refusal says which program and which process it refused"
}

run_tests
