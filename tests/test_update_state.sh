#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/update-state.sh"

require_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    skip_test "git is not installed"
    return 1
}

make_repo() {
    local dir="$1" version="$2"
    mkdir -p "$dir/.github"
    git -C "$dir" init -q
    printf 'VERSION=%s\n' "$version" > "$dir/.github/version.env"
    git -C "$dir" add --all
    git -C "$dir" -c user.email=test@example.com -c user.name=Test commit -qm "init"
}

no_temp_files() {
    local dir="$1"
    find "$dir" -maxdepth 1 -name '.tmp.*' -print 2>/dev/null
}

test_record_installed_revision_writes_commit_branch_and_version() {
    require_git || return 0
    local tmp status expected
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    expected="$(git -C "$tmp/repo" rev-parse HEAD)"

    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "recording the installed revision should succeed"
    assert_eq "$expected" "$(cat "$tmp/config/.current_commit")" ".current_commit should name the checked-out commit"
    assert_contains "$(cat "$tmp/config/.current_version")" "VERSION=v9.9.9" ".current_version should hold the checkout's VERSION"
    assert_eq "$(git -C "$tmp/repo" rev-parse --abbrev-ref HEAD)" "$(cat "$tmp/config/.update_branch")" \
        ".update_branch should name the checked-out branch"
    assert_eq "" "$(no_temp_files "$tmp/config")" "recording should not leave temporary files behind"
}

test_record_installed_revision_does_nothing_when_the_build_was_skipped() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    mkdir -p "$tmp/config"
    printf 'previous-revision\n' > "$tmp/config/.current_commit"

    CAELESTIA_SKIP_BUILD=1 record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 1 "$status" "a skipped build has nothing to record"
    assert_eq "previous-revision" "$(cat "$tmp/config/.current_commit")" \
        "the recorded revision must keep describing the shell that is actually running"
    assert_file_missing "$tmp/config/.current_version"
    assert_file_missing "$tmp/config/.update_source"
}

test_record_installed_revision_reports_failure_outside_a_checkout() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/plain"

    record_installed_revision "$tmp/plain" "$tmp/config"
    status=$?

    assert_status 1 "$status" "a directory that is not a checkout has no revision to record"
    assert_file_missing "$tmp/config/.current_commit"
}

test_record_installed_revision_falls_back_to_the_commit_for_the_version() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    rm "$tmp/repo/.github/version.env"

    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "the version should still be recoverable from the commit"
    assert_contains "$(cat "$tmp/config/.current_version")" "VERSION=v9.9.9" \
        ".current_version should fall back to the committed version.env"
}

test_record_installed_revision_writes_checkout_provenance() {
    require_git || return 0
    local tmp status expected_real
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    expected_real="$(cd "$tmp/repo" && pwd -P)"

    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "recording a checkout should succeed"
    assert_eq "tui" "$(cat "$tmp/config/.update_source")" \
        ".update_source should mark a checkout outside the shadow clone as the tui updater"
    assert_eq "$expected_real" "$(cat "$tmp/config/.update_repo")" \
        ".update_repo should record the absolute path of the deployed checkout"
}

test_record_installed_revision_marks_the_shadow_clone_as_the_cli_updater() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"

    CAELESTIA_UPDATE_REPO_DIR="$tmp/repo" record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "recording from the shadow clone should succeed"
    assert_eq "cli" "$(cat "$tmp/config/.update_source")" \
        ".update_source should mark the CLI updater's shadow clone as cli"
    assert_eq "$(cd "$tmp/repo" && pwd -P)" "$(cat "$tmp/config/.update_repo")" \
        ".update_repo should record the shadow clone it deployed from"
}

test_record_installed_revision_records_the_requested_channel() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    # The CLI updater's shadow clone sits on whatever branch git init picked,
    # so it records the channel it fetched rather than the checked-out branch.
    git -C "$tmp/repo" checkout -q --detach HEAD

    record_installed_revision "$tmp/repo" "$tmp/config" "cli" "dev"
    status=$?

    assert_status 0 "$status" "recording with an explicit channel should succeed"
    assert_eq "dev" "$(cat "$tmp/config/.update_branch")" \
        ".update_branch should name the channel the updater fetched, not the detached HEAD"
    assert_eq "cli" "$(cat "$tmp/config/.update_source")" \
        ".update_source should record the source it was told"
}

test_record_installed_revision_failure_leaves_no_partial_state() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    # A .git directory that is not a repository: the revision cannot be
    # resolved, so nothing at all may be written.
    mkdir -p "$tmp/fake/.git"

    record_installed_revision "$tmp/fake" "$tmp/config"
    status=$?

    assert_status 1 "$status" "a broken checkout has no revision to record"
    assert_file_missing "$tmp/config/.current_commit"
    assert_eq "" "$(no_temp_files "$tmp/config")" "a failed recording must not leave temporary files"
}

test_state_write_atomic_writes_the_content_and_leaves_no_temporary_files() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"

    state_write_atomic "$tmp/config/.current_commit" "abc123"
    status=$?

    assert_status 0 "$status" "an atomic write should succeed"
    assert_eq "abc123" "$(cat "$tmp/config/.current_commit")" "the written file should hold the content"
    assert_eq "" "$(no_temp_files "$tmp/config")" "no temporary file may survive a successful write"
}

test_state_write_atomic_cleans_up_when_the_move_fails() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"

    (
        mv() { return 1; }
        state_write_atomic "$tmp/config/.current_commit" "abc123"
    )
    status=$?

    assert_status 1 "$status" "a failed rename must be reported"
    assert_file_missing "$tmp/config/.current_commit" "a failed write must not touch the destination"
    assert_eq "" "$(no_temp_files "$tmp/config")" "no temporary file may survive a failed write"
}

test_update_state_allow_takeover_refuses_for_a_live_foreign_owner() {
    require_git || return 0
    local tmp status output
    tmp="$(new_tmpdir)"
    make_repo "$tmp/checkout" "v9.9.9"
    record_installed_revision "$tmp/checkout" "$tmp/config" >/dev/null

    output="$(update_state_allow_takeover "$tmp/config" "cli" 0 2>&1)"
    status=$?

    assert_status 1 "$status" "the CLI updater must refuse state owned by a live checkout"
    assert_contains "$output" "--takeover" "the refusal must explain the --takeover escape hatch"
}

test_update_state_allow_takeover_allows_the_takeover_flag() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/checkout" "v9.9.9"
    record_installed_revision "$tmp/checkout" "$tmp/config" >/dev/null

    update_state_allow_takeover "$tmp/config" "cli" 1
    status=$?

    assert_status 0 "$status" "--takeover must let the other updater take ownership"
}

test_update_state_allow_takeover_lets_the_owner_proceed() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/checkout" "v9.9.9"
    record_installed_revision "$tmp/checkout" "$tmp/config" >/dev/null

    update_state_allow_takeover "$tmp/config" "tui" 0
    status=$?

    assert_status 0 "$status" "the owning updater must keep its own state"
}

test_update_state_allow_takeover_ignores_a_dead_owner() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/checkout" "v9.9.9"
    record_installed_revision "$tmp/checkout" "$tmp/config" >/dev/null
    rm -rf "$tmp/checkout"

    update_state_allow_takeover "$tmp/config" "cli" 0
    status=$?

    assert_status 0 "$status" "state whose checkout is gone no longer blocks an update"
}

test_update_state_allow_takeover_allows_stateless_installs() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"

    update_state_allow_takeover "$tmp/config" "cli" 0
    status=$?

    assert_status 0 "$status" "an install with no recorded state is free to claim it"
}

run_tests
