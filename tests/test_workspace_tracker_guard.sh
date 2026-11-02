#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/shell/scripts/check-workspace-tracker.sh"
BUILD_SHELL="$REPO_ROOT/scripts/08-build-shell.sh"

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

test_an_enabled_effect_that_loads_on_demand_exits_clean() {
    local dir count_file stubs
    dir="$(new_tmpdir)"
    count_file="$dir/count"
    printf '0\n' > "$count_file"

    stubs="$dir/stubs"
    mkdir -p "$stubs"
    stub_bin "$stubs" kreadconfig6 "printf 'true\n'"
    # Call 1 (first introspect): fails
    # Call 2 (loadEffect): succeeds
    # Call 3 (second introspect): succeeds
    stub_bin "$stubs" qdbus6 "read -r count < '$count_file'
echo \"\$((count + 1))\" > '$count_file'
if [[ \"\$count\" -eq 0 ]]; then
    exit 1
fi
exit 0"
    chmod +x "$stubs/qdbus6"

    assert_eq "0" "$(run_guard "$stubs")" "an effect that loads successfully on demand should exit clean"
    assert_eq "3" "$(cat "$count_file")" "the guard should have checked, attempted load, and verified"
}

test_a_failed_effect_install_leaves_kwin_pointing_at_nothing() {
    # KWin keeps the effect enabled across an install that did not produce the plugin,
    # finds nothing to load, and says nothing about it; the shell's guard then warns on
    # every login. The install step has to switch the effect off in that case.
    local dir stubs body
    dir="$(new_tmpdir)"
    stubs="$dir/stubs"
    stub_bin "$stubs" kwriteconfig6 "printf '%s\n' \"\$*\" >> '$dir/writes.log'"
    stub_bin "$stubs" qdbus6 "printf '%s\n' \"\$*\" >> '$dir/writes.log'"
    printf 'stale\n' > "$dir/stamp"

    body="$(extract_function "$BUILD_SHELL" ws_leave_effect_off)"
    PATH="$stubs:$PATH" WS_STAMP="$dir/stamp" bash -c "
set -uo pipefail
info() { :; }
ws_installed_path() { return 1; }
$(printf '%s\n' "$body")
ws_leave_effect_off
" >/dev/null 2>&1

    assert_file_missing "$dir/stamp" "the stamp must go, so the next run rebuilds"
    assert_contains "$(cat "$dir/writes.log" 2>/dev/null)" \
        "--key kwin_workspace_trackerEnabled false" \
        "the effect must be switched off when the plugin is not on disk"
}

test_an_effect_that_is_already_installed_is_left_alone() {
    local dir stubs body
    dir="$(new_tmpdir)"
    stubs="$dir/stubs"
    stub_bin "$stubs" kwriteconfig6 "printf '%s\n' \"\$*\" >> '$dir/writes.log'"
    stub_bin "$stubs" qdbus6 "exit 0"
    printf 'stamp\n' > "$dir/stamp"

    body="$(extract_function "$BUILD_SHELL" ws_leave_effect_off)"
    PATH="$stubs:$PATH" WS_STAMP="$dir/stamp" bash -c "
set -uo pipefail
info() { :; }
ws_installed_path() { return 0; }
$(printf '%s\n' "$body")
ws_leave_effect_off
" >/dev/null 2>&1

    assert_file_exists "$dir/stamp" "a plugin that is installed must not have its stamp dropped"
    assert_file_missing "$dir/writes.log" "and KWin must not be reconfigured while it works"
}

run_tests

