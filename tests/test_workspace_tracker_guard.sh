#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/shell/scripts/check-workspace-tracker.sh"

# The guard asks KWin and kwinrc through these two tools, so the test supplies
# them and controls both answers.
stub_tools() {
    local dir="$1" enabled="${2:-true}" probe_status="${3:-0}" with_kreadconfig="${4:-1}" with_qdbus="${5:-1}"
    mkdir -p "$dir"
    if [[ "$with_kreadconfig" == 1 ]]; then
        stub_bin "$dir" kreadconfig6 "printf '%s\n' '$enabled'"
    fi
    if [[ "$with_qdbus" == 1 ]]; then
        stub_bin "$dir" qdbus6 "exit $probe_status"
    fi
}

# PATH holds the stubs alone: the script needs nothing but these tools, and a
# developer machine's own copies must not answer for the stubs. Bash is named by
# absolute path so its own lookup does not go through that PATH.
run_guard() {
    local stubs="$1" status
    PATH="$stubs" "$BASH" "$GUARD" >/dev/null 2>&1
    status=$?
    printf '%s' "$status"
}

test_an_enabled_effect_that_loaded_exits_clean() {
    local stubs
    stubs="$(new_tmpdir)/stubs"
    stub_tools "$stubs" true 0

    assert_eq "0" "$(run_guard "$stubs")" "a loaded effect should not be reported"
}

test_an_enabled_effect_that_is_missing_asks_for_a_rebuild() {
    local stubs
    stubs="$(new_tmpdir)/stubs"
    stub_tools "$stubs" true 1

    assert_eq "3" "$(run_guard "$stubs")" "an enabled effect that KWin never registered should be reported"
}

test_an_effect_this_install_does_not_use_is_ignored() {
    local stubs
    stubs="$(new_tmpdir)/stubs"
    stub_tools "$stubs" false 1

    assert_eq "0" "$(run_guard "$stubs")" "an install that never enabled the effect should stay quiet"
}

test_a_missing_kreadconfig_is_not_a_missing_effect() {
    local stubs
    stubs="$(new_tmpdir)/stubs"
    stub_tools "$stubs" true 0 0 1

    assert_eq "0" "$(run_guard "$stubs")" "without kreadconfig6 the guard cannot tell and must stay quiet"
}

test_a_missing_qdbus_is_not_a_missing_effect() {
    local stubs
    stubs="$(new_tmpdir)/stubs"
    stub_tools "$stubs" true 0 1 0

    assert_eq "0" "$(run_guard "$stubs")" "without qdbus6 the guard cannot tell and must stay quiet"
}

run_tests
