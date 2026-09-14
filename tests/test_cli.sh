#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/src/bin/caelestia"

STUB_DIR=""
CALLS=""
RUN_OUTPUT=""
RUN_STATUS=0

setup_stubs() {
    STUB_DIR="$(new_tmpdir)/bin"
    CALLS="$(dirname "$STUB_DIR")/calls.log"
    mkdir -p "$STUB_DIR"

    local name
    for name in caelestia-shell-ipc caelestia-screenshot caelestia-record caelestia-update caelestia-color; do
        recording_stub "$STUB_DIR" "$name" "$CALLS"
    done

    XDG_CONFIG_HOME="$(dirname "$STUB_DIR")/config"
}

run_cli() {
    [[ -n "$STUB_DIR" ]] || setup_stubs
    : > "$CALLS"
    RUN_OUTPUT="$(CAELESTIA_BIN_DIR="$STUB_DIR" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        bash "$CLI" "$@" 2>&1)"
    RUN_STATUS=$?
}

test_wallpaper_and_scheme_go_to_the_color_command() {
    setup_stubs

    run_cli wallpaper -f /tmp/wall.png
    assert_status 0 "$RUN_STATUS" "wallpaper should succeed"
    assert_eq "wallpaper -f /tmp/wall.png" \
        "$(calls_to "$CALLS" caelestia-color)" \
        "wallpaper reaches the color command with its arguments"

    run_cli scheme set -n dynamic
    assert_eq "scheme set -n dynamic" \
        "$(calls_to "$CALLS" caelestia-color)" \
        "scheme reaches the color command with its arguments"

    run_cli scheme list -n
    assert_eq "scheme list -n" \
        "$(calls_to "$CALLS" caelestia-color)" \
        "every scheme action is handed over, not just set"
}

test_shell_kill_restart_show_and_log() {
    setup_stubs

    run_cli shell -k
    assert_eq "quit" "$(calls_to "$CALLS" caelestia-shell-ipc)" "shell -k stops the shell"

    run_cli shell --restart
    assert_eq "restart" "$(calls_to "$CALLS" caelestia-shell-ipc)" "shell -r restarts the shell"

    run_cli shell -s
    assert_eq "show" "$(calls_to "$CALLS" caelestia-shell-ipc)" "shell -s lists IPC commands"

    run_cli shell --log
    assert_eq "log" "$(calls_to "$CALLS" caelestia-shell-ipc)" "shell -l prints the log"
}

test_shell_message_becomes_an_ipc_call() {
    setup_stubs

    run_cli shell toggleNexus
    assert_eq "call toggleNexus" \
        "$(calls_to "$CALLS" caelestia-shell-ipc)" \
        "a single word is sent as an IPC command"

    run_cli shell nexus openPage 0 8
    assert_eq "call nexus openPage 0 8" \
        "$(calls_to "$CALLS" caelestia-shell-ipc)" \
        "an IPC command keeps all of its arguments"
}

test_shell_with_no_arguments_starts_it() {
    setup_stubs

    run_cli shell
    assert_status 0 "$RUN_STATUS" "starting the shell should succeed"
    assert_eq "start" "$(calls_to "$CALLS" caelestia-shell-ipc)" "the bare command starts the shell"

    run_cli shell -d
    assert_eq "start" "$(calls_to "$CALLS" caelestia-shell-ipc)" "-d is accepted and still starts"
}

test_screenshot_maps_flags_to_the_helper() {
    setup_stubs

    run_cli screenshot
    assert_eq "full" "$(calls_to "$CALLS" caelestia-screenshot)" "the default capture is the full screen"

    run_cli screenshot -r
    assert_eq "region" "$(calls_to "$CALLS" caelestia-screenshot)" "-r captures a region"

    run_cli screenshot --region
    assert_eq "region" "$(calls_to "$CALLS" caelestia-screenshot)" "--region captures a region"
}

test_update_and_record_pass_arguments_through() {
    setup_stubs

    run_cli update
    assert_eq "" "$(calls_to "$CALLS" caelestia-update)" "update runs with no arguments"

    run_cli update dev
    assert_eq "dev" "$(calls_to "$CALLS" caelestia-update)" "update passes its ref through"

    run_cli record --stop
    assert_eq "--stop" "$(calls_to "$CALLS" caelestia-record)" "record passes its options through"
}

test_help_lists_the_commands() {
    setup_stubs

    run_cli help
    assert_status 0 "$RUN_STATUS" "help should succeed"
    assert_contains "$RUN_OUTPUT" "Usage: caelestia" "help shows a usage line"

    local command
    for command in shell install update wallpaper scheme screenshot record version; do
        assert_contains "$RUN_OUTPUT" "$command" "help should mention '$command'"
    done

    run_cli
    assert_status 0 "$RUN_STATUS" "no arguments should print the help and succeed"
    assert_contains "$RUN_OUTPUT" "Usage: caelestia" "no arguments prints the usage"

    run_cli shell -h
    assert_status 0 "$RUN_STATUS" "shell -h should succeed"
    assert_contains "$RUN_OUTPUT" "Usage: caelestia shell" "shell -h shows its own usage"
}

test_unknown_command_and_option_are_rejected() {
    setup_stubs

    run_cli frobnicate
    assert_status 2 "$RUN_STATUS" "an unknown command should exit 2"
    assert_contains "$RUN_OUTPUT" "unknown command: frobnicate" "the unknown command is named"

    run_cli shell --nonsense
    assert_status 2 "$RUN_STATUS" "an unknown shell option should exit 2"
    assert_contains "$RUN_OUTPUT" "unknown option for shell: --nonsense" "the option is named"

    run_cli screenshot --nonsense
    assert_status 2 "$RUN_STATUS" "an unknown screenshot option should exit 2"
}

test_install_with_nothing_to_install_from_explains_itself() {
    setup_stubs

    RUN_OUTPUT="$(CAELESTIA_BIN_DIR="$STUB_DIR" \
        CAELESTIA_DIR="$(dirname "$STUB_DIR")/nowhere" \
        CAELESTIA_LIB_DIR="$(dirname "$STUB_DIR")/nowhere" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        bash "$CLI" install 2>&1)"
    RUN_STATUS=$?

    assert_status 1 "$RUN_STATUS" "install with nothing to install from should fail"
    assert_contains "$RUN_OUTPUT" "no installer scripts found" "what is missing is named"
    assert_contains "$RUN_OUTPUT" "/usr/share/caelestia" "and where a package keeps it"
}

test_version_reports_the_checkout_version() {
    setup_stubs

    local expected
    expected="$(awk -F= '$1 == "VERSION" { print $2; exit }' "$REPO_ROOT/.github/version.env")"
    assert_ne "" "$expected" "version.env should carry a version"

    RUN_OUTPUT="$(XDG_CONFIG_HOME="$XDG_CONFIG_HOME" bash "$CLI" version 2>&1)"
    RUN_STATUS=$?

    assert_status 0 "$RUN_STATUS" "version should succeed"
    assert_eq "caelestia $expected" "$RUN_OUTPUT" "the checkout version is reported"
}

run_tests
