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

run_tests
