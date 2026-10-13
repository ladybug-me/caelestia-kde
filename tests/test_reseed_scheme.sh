#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESEED="$REPO_ROOT/shell/scripts/reseed-scheme.sh"

SANDBOX=""
STUB_DIR=""
CALLS=""

setup_sandbox() {
    SANDBOX="$(new_tmpdir)"
    STUB_DIR="$SANDBOX/bin"
    CALLS="$SANDBOX/calls.log"
    mkdir -p "$STUB_DIR" "$SANDBOX/state/caelestia/wallpaper"

    # The stub writes the scheme back, which is how the script knows it worked and stops there.
    cat > "$STUB_DIR/caelestia" <<STUB
#!/usr/bin/env bash
printf 'caelestia %s\n' "\$*" >> "$CALLS"
printf '%s' '{"name": "dynamic"}' > "$SANDBOX/state/caelestia/scheme.json"
STUB
    chmod +x "$STUB_DIR/caelestia"

    printf '%s' "$SANDBOX/wall.png" > "$SANDBOX/state/caelestia/wallpaper/path.txt"
    printf 'not really a png\n' > "$SANDBOX/wall.png"
    printf '%s' '{"name": "dynamic"}' > "$SANDBOX/state/caelestia/scheme.json"
}

run_reseed() {
    : > "$CALLS"
    XDG_STATE_HOME="$SANDBOX/state" PATH="$STUB_DIR:$PATH" \
        bash "$RESEED" "$@" >/dev/null 2>&1
}

test_the_smart_setting_reaches_the_command_it_calls() {
    setup_sandbox
    run_reseed --no-smart

    assert_contains "$(cat "$CALLS")" "scheme set -n dynamic --no-smart" \
        "the setting the shell stated reaches the command that derives"
}

test_a_caller_that_states_nothing_gets_the_wallpapers_choice() {
    setup_sandbox
    run_reseed

    assert_contains "$(cat "$CALLS")" "scheme set -n dynamic" "the reseed still derives"
    assert_not_contains "$(cat "$CALLS")" "no-smart" \
        "nothing is stated on the reseed's behalf, so nothing is passed on"
}

test_a_scheme_the_user_picked_is_left_alone() {
    setup_sandbox
    printf '%s' '{"name": "catppuccin"}' > "$SANDBOX/state/caelestia/scheme.json"
    run_reseed

    assert_eq "" "$(cat "$CALLS" 2>/dev/null || true)" "nothing is derived for a named scheme"
}

run_tests
