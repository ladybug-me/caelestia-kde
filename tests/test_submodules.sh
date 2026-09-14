#!/usr/bin/env bash
# test_submodules.sh - Tests for scripts/lib/submodules.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/submodules.sh"

require_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    skip_test "git is not installed"
    return 1
}

# make_repo <dir>
#
# A throwaway checkout with one commit, so git is willing to operate on it.
make_repo() {
    local repo="$1"
    git init -q "$repo"
    git -C "$repo" -c user.email=test@example.com -c user.name=Test \
        commit -q --allow-empty -m "init"
}

# register_submodule <repo> <name> <path>
#
# Reproduces what `git submodule init` leaves behind for a submodule since deleted
# upstream: the .git/config registration, the module cache and the worktree.
# `git submodule deinit` cannot clean that up - it resolves the path through
# .gitmodules and fails once the entry is gone, which is what prune_removed_submodules
# exists for.
register_submodule() {
    local repo="$1" name="$2" path="$3"
    git -C "$repo" config "submodule.$name.url" "https://example.invalid/$name.git"
    git -C "$repo" config "submodule.$name.path" "$path"
    mkdir -p "$repo/$path" "$repo/.git/modules/$name"
    printf 'stale\n' > "$repo/$path/stale-file"
    printf 'stale\n' > "$repo/.git/modules/$name/stale-file"
}

test_prune_removes_the_worktree_and_registration_of_a_deleted_submodule() {
    require_git || return 0
    local tmp repo status
    tmp="$(new_tmpdir)"
    repo="$tmp/repo"
    make_repo "$repo"
    printf '[submodule "keep"]\n\tpath = keep\n\turl = https://example.invalid/keep.git\n' \
        > "$repo/.gitmodules"
    register_submodule "$repo" keep keep
    register_submodule "$repo" gone gone

    prune_removed_submodules "$repo"
    status=$?

    assert_status 0 "$status" "pruning should succeed"
    assert_file_missing "$repo/gone" "the worktree checkout of the deleted submodule should be removed"
    assert_file_missing "$repo/.git/modules/gone" "the module cache of the deleted submodule should be removed"
    git -C "$repo" config --get submodule.gone.url >/dev/null 2>&1
    assert_status 1 "$?" "the stale .git/config registration should be removed"

    assert_is_dir "$repo/keep" "a submodule still listed in .gitmodules must survive"
    assert_is_dir "$repo/.git/modules/keep" "a live submodule must keep its module cache"
    assert_eq "keep" "$(git -C "$repo" config --get submodule.keep.path)" \
        "a submodule still listed in .gitmodules must keep its registration"
}

test_prune_resolves_the_worktree_path_from_the_local_registration() {
    require_git || return 0
    local tmp repo
    tmp="$(new_tmpdir)"
    repo="$tmp/repo"
    make_repo "$repo"
    : > "$repo/.gitmodules"
    # Name and worktree path differ (a nested submodule), so the path can only
    # come from .git/config.
    register_submodule "$repo" dots src/dots

    prune_removed_submodules "$repo"

    assert_file_missing "$repo/src/dots" "the nested worktree checkout should be removed"
    assert_is_dir "$repo/src" "the parent directory of the checkout must not be removed"
    assert_file_missing "$repo/.git/modules/dots" "the module cache should be removed"
}

test_prune_is_a_no_op_without_local_registrations() {
    require_git || return 0
    local tmp repo status
    tmp="$(new_tmpdir)"
    repo="$tmp/repo"
    make_repo "$repo"
    printf '[submodule "keep"]\n\tpath = keep\n\turl = https://example.invalid/keep.git\n' \
        > "$repo/.gitmodules"
    mkdir -p "$repo/keep"

    prune_removed_submodules "$repo"
    status=$?

    assert_status 0 "$status" "a checkout that was never submodule-initialized should still succeed"
    assert_is_dir "$repo/keep" "a submodule that is not registered locally must not be touched"
}

# isolate_git_config <dir>
#
# Points git at a throwaway global config, so a test can allow file:// submodule URLs
# (refused by default) without touching the developer's ~/.gitconfig.
isolate_git_config() {
    local dir="$1"
    export HOME="$dir/home"
    mkdir -p "$HOME"
    git config --global protocol.file.allow always
    git config --global user.email "test@example.com"
    git config --global user.name "Test"
    git config --global init.defaultBranch main
}

# make_submodule_source <dir>
#
# A repository with content, to be used as a submodule's remote.
make_submodule_source() {
    local source="$1"
    git init -q "$source"
    printf 'deployed\n' > "$source/deployed.conf"
    git -C "$source" add -A
    git -C "$source" commit -q -m "content"
}

# make_checkout_with_submodule <repo> <source> [registered-url]
#
# A checkout with src/dots recorded as a submodule of <source> and an empty working
# tree - an unfetched submodule. With registered-url, .git/config points there
# instead, which is the stale-registration case sync exists for.
make_checkout_with_submodule() {
    local repo="$1" source="$2" registered="${3:-}"
    git init -q "$repo"
    printf '[submodule "caelestia"]\n\tpath = src/dots\n\turl = %s\n' "file://$source" \
        > "$repo/.gitmodules"
    git -C "$repo" add .gitmodules
    git -C "$repo" commit -q -m "add submodule"
    # `submodule init` is what copies the URL into .git/config and leaves the
    # working tree empty, exactly as an install sees it before the fetch.
    git -C "$repo" submodule init src/dots >/dev/null 2>&1 || true
    if [[ -n "$registered" ]]; then
        git -C "$repo" config submodule.caelestia.url "$registered"
    fi
    mkdir -p "$repo/src/dots"
}

test_submodule_has_content_tells_an_empty_checkout_from_a_fetched_one() {
    require_git || return 0
    local tmp repo
    tmp="$(new_tmpdir)"
    repo="$tmp/repo"
    mkdir -p "$repo/empty" "$repo/full"
    printf 'x\n' > "$repo/full/file"

    submodule_has_content "$repo/empty"
    assert_status 1 "$?" "an empty directory has no content"
    submodule_has_content "$repo/full"
    assert_status 0 "$?" "a directory with a file has content"
    submodule_has_content "$repo/missing"
    assert_status 1 "$?" "a directory that is not there has no content"
}

test_ensure_submodule_content_leaves_a_fetched_submodule_alone() {
    require_git || return 0
    local tmp repo
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    mkdir -p "$repo/src/dots"
    printf 'local edit\n' > "$repo/src/dots/deployed.conf"

    ensure_submodule_content "$repo" "src/dots"
    assert_status 0 "$?" "content that is already there counts as fetched"
    assert_eq "local edit" "$(cat "$repo/src/dots/deployed.conf")" \
        "content that is already there must not be replaced"
}

test_ensure_submodule_content_fetches_an_empty_submodule() {
    require_git || return 0
    local tmp repo source
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    source="$tmp/source"
    make_submodule_source "$source"
    repo="$tmp/repo"
    make_checkout_with_submodule "$repo" "$source"

    ensure_submodule_content "$repo" "src/dots"
    assert_status 0 "$?" "the submodule should be fetched"
    assert_eq "deployed" "$(cat "$repo/src/dots/deployed.conf")" \
        "the submodule's own content should be in place"
}

test_ensure_submodule_content_recovers_from_a_stale_registration() {
    require_git || return 0
    local tmp repo source
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    source="$tmp/source"
    make_submodule_source "$source"
    repo="$tmp/repo"
    # .git/config points somewhere useless while .gitmodules is correct, which
    # is what a moved or renamed submodule remote looks like from here.
    make_checkout_with_submodule "$repo" "$source" "file://$tmp/gone"

    ensure_submodule_content "$repo" "src/dots"
    assert_status 0 "$?" "a stale registration should not stop the fetch"
    assert_eq "deployed" "$(cat "$repo/src/dots/deployed.conf")" \
        "the content should come from the URL .gitmodules records"
}

test_fetch_submodule_by_clone_works_without_submodule_machinery() {
    require_git || return 0
    local tmp source repo
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    source="$tmp/source"
    make_submodule_source "$source"
    repo="$tmp/repo"
    # Deliberately not a repository: the fallback exists for checkouts where
    # git-submodule has nothing to work with.
    mkdir -p "$repo"
    printf '[submodule "caelestia"]\n\tpath = src/dots\n\turl = file://%s\n' "$source" \
        > "$repo/.gitmodules"
    mkdir -p "$repo/src/dots"

    fetch_submodule_by_clone "$repo" "src/dots"
    assert_status 0 "$?" "the clone fallback should succeed with a usable URL"
    assert_eq "deployed" "$(cat "$repo/src/dots/deployed.conf")" "the content should be there"
    assert_file_missing "$repo/src/dots/.git" \
        "the clone's own repository must not be left inside the parent's working tree"
}

test_ensure_submodule_content_reports_failure_instead_of_pretending() {
    require_git || return 0
    local tmp repo
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    mkdir -p "$repo"
    printf '[submodule "caelestia"]\n\tpath = src/dots\n\turl = file://%s/gone\n' "$tmp" \
        > "$repo/.gitmodules"
    git init -q "$repo"
    mkdir -p "$repo/src/dots"

    ensure_submodule_content "$repo" "src/dots"
    assert_status 1 "$?" "an unfetchable submodule must be reported as a failure"
    assert_eq "" "$(ls -A "$repo/src/dots")" "nothing should be invented in its place"
}

run_tests
