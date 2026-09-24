#!/usr/bin/env bash

set -uo pipefail

# Tests for the hardened download path: the archive safety audit that runs
# before anything downloaded is unpacked (scripts/lib/download.sh), and the
# submodule clone fallback honoring the recorded gitlink instead of drifting
# to the default branch tip (scripts/lib/submodules.sh). Everything here works
# on real archives and real throwaway repositories; no network is touched.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/download.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/submodules.sh"

require_tar() {
    if command -v tar >/dev/null 2>&1; then
        return 0
    fi
    skip_test "tar is not installed"
    return 1
}

require_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    skip_test "git is not installed"
    return 1
}

# build_archive <archive> <root>
#
# Packs the tree under <root> the way the release tooling packs trees: member
# names relative to the root.
build_archive() {
    local archive="$1" root="$2"
    tar -C "$root" -czf "$archive" .
}

# crafted_archive <archive> <root> <prefix>
#
# Packs <root>/file.txt with <prefix> written into its member name. tar
# sanitizes absolute and ".." prefixes when files are added by path, so the
# prefix has to go in through --transform to produce the archive an attacker
# would hand-craft.
crafted_archive() {
    local archive="$1" root="$2" prefix="$3"
    tar -C "$root" --transform "s,^,${prefix}," -czf "$archive" file.txt 2>/dev/null
}

make_sdk_tree() {
    # The shape of the prebuilt CAVA SDK: include/, lib/ and the excluded bin/,
    # with the link types a real SDK can legitimately carry.
    local root="$1"
    mkdir -p "$root/include/cava" "$root/lib" "$root/bin"
    printf 'header\n' > "$root/include/cava/cavacore.h"
    printf 'library\n' > "$root/lib/libcava.a"
    printf 'binary\n' > "$root/bin/cava"
    ln -s libcava.so.1 "$root/lib/libcava.so"
    ln "$root/lib/libcava.a" "$root/lib/libcava-hardlink.a"
}

test_a_safe_sdk_archive_passes_the_audit() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/sdk.tar.gz"
    make_sdk_tree "$tmp/root"
    build_archive "$archive" "$tmp/root"

    archive_is_safe "$archive"
    assert_status 0 "$?" "an SDK-shaped archive with in-tree links should pass"
    archive_is_safe "$archive" include lib bin
    assert_status 0 "$?" "the same archive should pass with its expected trees given"
}

test_an_archive_with_dotdot_members_is_refused() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/evil.tar.gz"
    mkdir -p "$tmp/root"
    printf 'payload\n' > "$tmp/root/file.txt"
    crafted_archive "$archive" "$tmp/root" "../"

    archive_is_safe "$archive"
    assert_status 1 "$?" "a member with a .. component must refuse the whole archive"
}

test_an_archive_with_absolute_members_is_refused() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/evil.tar.gz"
    mkdir -p "$tmp/root"
    printf 'payload\n' > "$tmp/root/file.txt"
    crafted_archive "$archive" "$tmp/root" "/"

    archive_is_safe "$archive"
    assert_status 1 "$?" "a member with an absolute path must refuse the whole archive"
}

test_an_archive_with_escaping_symlinks_is_refused() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/evil.tar.gz"
    mkdir -p "$tmp/root/include"
    printf 'header\n' > "$tmp/root/include/cavacore.h"
    ln -s ../../../etc/passwd "$tmp/root/include/relative-evil"
    ln -s /etc/passwd "$tmp/root/include/absolute-evil"
    build_archive "$archive" "$tmp/root"

    archive_is_safe "$archive"
    assert_status 1 "$?" "a symlink climbing out of the archive must refuse it"
}

test_a_symlink_staying_inside_the_archive_is_allowed() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/ok.tar.gz"
    mkdir -p "$tmp/root/lib"
    printf 'library\n' > "$tmp/root/lib/libcava.so.1"
    ln -s libcava.so.1 "$tmp/root/lib/libcava.so"
    # From bin/, "../lib/x" resolves inside the archive: one ".." pops to the
    # archive root, it does not climb out of it.
    mkdir -p "$tmp/root/bin"
    ln -s ../lib/libcava.so.1 "$tmp/root/bin/link"
    build_archive "$archive" "$tmp/root"

    archive_is_safe "$archive"
    assert_status 0 "$?" "a symlink that resolves inside the archive is not an escape"
}

test_members_outside_the_expected_trees_are_refused() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/sdk.tar.gz"
    make_sdk_tree "$tmp/root"
    printf 'readme\n' > "$tmp/root/README"
    build_archive "$archive" "$tmp/root"

    archive_is_safe "$archive" include lib bin
    assert_status 1 "$?" "a top-level README is not a tree an SDK unpacks into /usr"
    archive_is_safe "$archive"
    assert_status 0 "$?" "without expected trees given, the same archive is only audited for escapes"
}

test_a_file_that_is_not_an_archive_is_refused() {
    require_tar || return 0
    local tmp
    tmp="$(new_tmpdir)"
    printf 'this is not a tarball\n' > "$tmp/garbage.bin"

    archive_is_safe "$tmp/garbage.bin"
    assert_status 1 "$?" "a file whose members cannot be listed must not be unpacked"
}

test_an_archive_with_no_members_is_safe() {
    require_tar || return 0
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/empty.tar.gz"
    mkdir -p "$tmp/root"
    build_archive "$archive" "$tmp/root"

    archive_is_safe "$archive"
    assert_status 0 "$?" "an archive with nothing in it has nothing to refuse"
}

isolate_git_config() {
    local dir="$1"
    export HOME="$dir/home"
    mkdir -p "$HOME"
    git config --global protocol.file.allow always
    git config --global user.email "test@example.com"
    git config --global user.name "Test"
    git config --global init.defaultBranch main
}

# make_pinned_source <repo> <first-content> <second-content>
#
# A submodule source repository with two commits, so the tip and the pinned
# revision are genuinely different trees.
make_pinned_source() {
    local repo="$1" first="$2" second="$3"
    git init -q "$repo"
    printf '%s\n' "$first" > "$repo/deployed.conf"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "pinned revision"
    printf '%s\n' "$second" > "$repo/deployed.conf"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "later tip"
}

# make_superproject <repo> <source-url> <gitlink-sha>
make_superproject() {
    local repo="$1" url="$2" gitlink="$3"
    git init -q "$repo"
    printf '[submodule "caelestia"]\n\tpath = src/dots\n\turl = %s\n' "$url" \
        > "$repo/.gitmodules"
    git -C "$repo" update-index --add --cacheinfo 160000,"$gitlink",src/dots
    git -C "$repo" add .gitmodules
    git -C "$repo" commit -q -m "record the submodule pin"
}

test_recorded_gitlink_reads_the_pin_from_head() {
    require_git || return 0
    local tmp repo
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    make_pinned_source "$tmp/source" "deployed" "deployed-v2"
    make_superproject "$repo" "file://$tmp/source" "$(git -C "$tmp/source" rev-parse HEAD~1)"

    assert_eq "$(git -C "$tmp/source" rev-parse HEAD~1)" "$(recorded_gitlink "$repo" src/dots)" \
        "the gitlink HEAD records should be the pin handed to the clone fallback"
}

test_recorded_gitlink_reports_a_path_without_a_pin() {
    require_git || return 0
    local tmp repo
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    make_pinned_source "$tmp/source" "deployed" "deployed-v2"
    make_superproject "$repo" "file://$tmp/source" "$(git -C "$tmp/source" rev-parse HEAD~1)"

    recorded_gitlink "$repo" src/never-registered
    assert_status 1 "$?" "a path with no gitlink has no pin to report"
}

test_the_clone_fallback_checks_out_the_recorded_gitlink() {
    require_git || return 0
    local tmp repo pinned status
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    make_pinned_source "$tmp/source" "deployed" "deployed-v2"
    pinned="$(git -C "$tmp/source" rev-parse HEAD~1)"
    make_superproject "$repo" "file://$tmp/source" "$pinned"

    fetch_submodule_by_clone "$repo" src/dots "$pinned"
    status=$?

    assert_status 0 "$status" "the clone fallback should succeed with a reachable pin"
    assert_eq "deployed" "$(cat "$repo/src/dots/deployed.conf")" \
        "the pinned revision must land, not the default branch tip"
}

test_the_clone_fallback_fails_when_the_pin_is_unreachable() {
    require_git || return 0
    local tmp repo source other status
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    source="$tmp/source"
    make_pinned_source "$source" "deployed" "deployed-v2"
    # A sha that exists in a completely different repository: present nowhere
    # the submodule URL can serve.
    make_pinned_source "$tmp/other" "unrelated" "unrelated-v2"
    local bogus
    bogus="$(git -C "$tmp/other" rev-parse HEAD)"

    make_superproject "$repo" "file://$source" "$(git -C "$source" rev-parse HEAD~1)"
    mkdir -p "$repo/src/dots"
    printf 'do not clobber me\n' > "$repo/src/dots/marker"

    fetch_submodule_by_clone "$repo" src/dots "$bogus"
    status=$?

    assert_status 1 "$status" "an unreachable pin must fail loudly instead of drifting"
    assert_eq "do not clobber me" "$(cat "$repo/src/dots/marker")" \
        "a refused clone must not delete the recorded directory either"
}

test_ensure_submodule_content_lands_on_the_pinned_revision() {
    require_git || return 0
    local tmp repo pinned
    tmp="$(new_tmpdir)"
    isolate_git_config "$tmp"
    repo="$tmp/repo"
    make_pinned_source "$tmp/source" "deployed" "deployed-v2"
    pinned="$(git -C "$tmp/source" rev-parse HEAD~1)"
    make_superproject "$repo" "file://$tmp/source" "$pinned"

    ensure_submodule_content "$repo" src/dots
    assert_status 0 "$?" "fetching a pinned submodule should succeed"
    assert_eq "deployed" "$(cat "$repo/src/dots/deployed.conf")" \
        "whichever fetch path wins, the pinned revision is the one that must land"
}

run_tests
