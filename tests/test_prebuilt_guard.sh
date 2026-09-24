#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SHELL="$REPO_ROOT/scripts/08-build-shell.sh"

# The guard decides from the checkout's own git state, so the test drives the
# real functions against throwaway repositories rather than stubbing git.
extract_function() {
    awk -v name="$1" '
        $0 ~ "^" name "\\(\\) \\{" { capture = 1 }
        capture { print }
        capture && $0 == "}" { exit }
    ' "$BUILD_SHELL"
}

GUARD_SOURCE="$(extract_function shell_release_tag; extract_function checkout_may_use_prebuilt)"

if [[ -z "$GUARD_SOURCE" ]]; then
    fail "could not find shell_release_tag/checkout_may_use_prebuilt in scripts/08-build-shell.sh"
    run_tests
    exit 1
fi

# A checkout of main with origin/main pointing at the same commit, which is what
# install.sh leaves behind, plus a version.env naming the released version.
seed_checkout() {
    local dir="$1" revision="${2:-v1.0.0}"
    mkdir -p "$dir/.github"
    printf 'VERSION=%s\n' "$revision" > "$dir/.github/version.env"
    git init -q "$dir"
    git -C "$dir" symbolic-ref HEAD refs/heads/main
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name test
    git -C "$dir" add -A
    git -C "$dir" commit -qm "release $revision"
    git -C "$dir" update-ref refs/remotes/origin/main HEAD
}

allows_prebuilt() {
    local dir="$1" status
    BUNDLE_DIR="$dir" bash -c "$GUARD_SOURCE
checkout_may_use_prebuilt" >/dev/null 2>&1
    status=$?
    [[ $status -eq 0 ]]
}

test_main_sitting_on_its_remote_tip_may_use_the_prebuilt() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"

    allows_prebuilt "$repo" || fail "a clean main checkout should be allowed to use the prebuilt"
}

test_local_commits_on_main_build_locally() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    printf 'local\n' > "$repo/local.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "unreleased local work"

    if allows_prebuilt "$repo"; then
        fail "main with commits of its own must not be overwritten by the prebuilt"
    fi
}

test_main_behind_its_remote_builds_locally() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    # The remote moves on while the checkout stays behind, as a stale local main
    # does until something pulls it.
    git -C "$repo" commit -q --allow-empty -m "released later"
    git -C "$repo" update-ref refs/remotes/origin/main HEAD
    git -C "$repo" reset -q --hard HEAD~1

    if allows_prebuilt "$repo"; then
        fail "a stale main checkout must not be treated as the released revision"
    fi
}

test_another_branch_builds_locally() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    git -C "$repo" checkout -q -b dev

    if allows_prebuilt "$repo"; then
        fail "dev must never install the prebuilt shell"
    fi
}

test_the_released_tag_may_use_the_prebuilt() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    # An update pinned to a version: the checkout is the tag, not main's tip.
    git -C "$repo" commit -q --allow-empty -m "next release"
    git -C "$repo" tag v2.0.0
    printf 'VERSION=v2.0.0\n' > "$repo/.github/version.env"

    allows_prebuilt "$repo" || fail "a checkout sitting on the released tag should be allowed to use the prebuilt"
}

test_a_version_that_is_not_the_tag_builds_locally() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    git -C "$repo" commit -q --allow-empty -m "next release"
    git -C "$repo" tag v2.0.0
    # version.env still names the older release, so the prebuilt would be older
    # than the tree it replaces.
    printf 'VERSION=v1.0.0\n' > "$repo/.github/version.env"

    if allows_prebuilt "$repo"; then
        fail "a version.env that does not match the checked-out revision must build locally"
    fi
}

test_a_checkout_without_a_version_builds_locally() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    rm -f "$repo/.github/version.env"

    if allows_prebuilt "$repo"; then
        fail "without a version there is no release artifact to fetch"
    fi
}

test_a_tree_that_is_not_a_checkout_builds_locally() {
    local dir
    dir="$(new_tmpdir)/tree"
    mkdir -p "$dir/.github"
    printf 'VERSION=v1.0.0\n' > "$dir/.github/version.env"

    if allows_prebuilt "$dir"; then
        fail "a source tree without git history must build locally"
    fi
}

INSTALLER_SOURCE="$(awk '
    $0 ~ "^try_download_prebuilt_installer\\(\\) \\{" { capture = 1 }
    capture { print }
    capture && $0 == "}" { exit }
' "$REPO_ROOT/scripts/setup.sh")"

if [[ -z "$INSTALLER_SOURCE" ]]; then
    fail "could not find try_download_prebuilt_installer in scripts/setup.sh"
fi

installer_stdout_with_status() {
    local status="$1"
    bash -c "
        tui_version() { echo '9.9.9'; }
        release_tag() { echo 'v9.9.9'; }
        fetch_asset() { : > \"\$2\"; return 0; }
        verify_download() { return $status; }
        uname() { echo x86_64; }
        $INSTALLER_SOURCE
        try_download_prebuilt_installer
    " 2>/dev/null
}

installer_stderr_with_status() {
    local status="$1"
    bash -c "
        tui_version() { echo '9.9.9'; }
        release_tag() { echo 'v9.9.9'; }
        fetch_asset() { : > \"\$2\"; return 0; }
        verify_download() { return $status; }
        uname() { echo x86_64; }
        $INSTALLER_SOURCE
        try_download_prebuilt_installer
    " 2>&1 >/dev/null
}

test_no_checksum_prints_nothing_to_stdout() {
    local out
    out="$(installer_stdout_with_status 2)"

    if [[ -n "$out" ]]; then
        fail "a failed download must print nothing to stdout, got: $out"
    fi
}

test_no_checksum_warns_on_stderr() {
    local err
    err="$(installer_stderr_with_status 2)"

    case "$err" in
        *"No published checksum"*) ;;
        *) fail "the reason should still be reported, on stderr; got: $err" ;;
    esac
}

test_checksum_mismatch_prints_nothing_to_stdout() {
    local out
    out="$(installer_stdout_with_status 1)"

    if [[ -n "$out" ]]; then
        fail "a mismatched download must print nothing to stdout, got: $out"
    fi
}

test_a_verified_download_prints_only_the_path() {
    local out
    out="$(installer_stdout_with_status 0)"

    case "$out" in
        /tmp/*|/var/*) ;;
        "") fail "a verified download should print its path, got nothing" ;;
        *) fail "stdout should carry the path and nothing else, got: $out" ;;
    esac
}

run_tests
