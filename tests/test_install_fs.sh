#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/install-fs.sh"

make_fixture() {
    local tmp="$1"
    mkdir -p "$tmp/src/contents" "$tmp/dest"
    printf 'new-greeter\n' > "$tmp/src/metadata.json"
    printf 'body\n' > "$tmp/src/contents/Main.qml"
    printf 'old-greeter\n' > "$tmp/dest/metadata.json"
}

test_atomic_replace_tree_swaps_in_the_new_tree() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    atomic_replace_tree "$tmp/src" "$tmp/dest" metadata.json
    status=$?

    assert_status 0 "$status" "replacing a healthy tree should succeed"
    assert_eq "new-greeter" "$(cat "$tmp/dest/metadata.json")" "destination should hold the new tree"
    assert_file_exists "$tmp/dest/contents/Main.qml"
}

test_atomic_replace_tree_keeps_destination_when_copy_is_incomplete() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    atomic_replace_tree "$tmp/src" "$tmp/dest" does-not-exist.json
    status=$?

    assert_status 1 "$status" "an incomplete source should be rejected"
    assert_eq "old-greeter" "$(cat "$tmp/dest/metadata.json")" "destination should be left untouched"
}

test_atomic_replace_tree_keeps_destination_when_source_is_missing() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    atomic_replace_tree "$tmp/absent" "$tmp/dest"
    status=$?

    assert_status 1 "$status" "a missing source should be rejected"
    assert_eq "old-greeter" "$(cat "$tmp/dest/metadata.json")" "destination should be left untouched"
}

test_atomic_replace_tree_creates_a_missing_destination() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    atomic_replace_tree "$tmp/src" "$tmp/fresh/nested/dest" metadata.json
    status=$?

    assert_status 0 "$status" "a fresh install should succeed"
    assert_eq "new-greeter" "$(cat "$tmp/fresh/nested/dest/metadata.json")" "destination should be created"
}

test_atomic_replace_tree_leaves_no_staging_directories() {
    local tmp status leftovers
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    atomic_replace_tree "$tmp/src" "$tmp/dest" metadata.json
    status=$?
    assert_status 0 "$status" "replacing a healthy tree should succeed"

    atomic_replace_tree "$tmp/src" "$tmp/dest" does-not-exist.json >/dev/null 2>&1

    leftovers="$(compgen -G "$tmp/.dest.*" || true)"
    assert_eq "" "$leftovers" "staging directories should not outlive the call"
}

test_snapshot_dir_copies_the_tree_and_reports_the_path() {
    local tmp status dest
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    dest="$(snapshot_dir "$tmp/src" "$tmp/backups" "quickshell-caelestia" 3)"
    status=$?

    assert_status 0 "$status" "snapshotting an existing directory should succeed"
    assert_eq "new-greeter" "$(cat "$dest/metadata.json")" "snapshot should hold a copy of the source"
    assert_eq "$tmp/backups" "$(dirname "$dest")" "snapshot should live under the requested root"
    assert_contains "$(basename "$dest")" "quickshell-caelestia-" "snapshot name should carry the requested prefix"
}

test_snapshot_dir_reports_nothing_when_there_is_nothing_to_snapshot() {
    local tmp status dest
    tmp="$(new_tmpdir)"

    dest="$(snapshot_dir "$tmp/absent" "$tmp/backups" "quickshell-caelestia" 3)"
    status=$?

    assert_status 1 "$status" "a missing source directory is not an error worth a snapshot"
    assert_eq "" "$dest" "no path should be reported when nothing was copied"
}

test_snapshot_dir_keeps_only_the_requested_number_of_snapshots() {
    local tmp status i remaining
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    for i in 1 2 3 4 5; do
        printf 'revision-%s\n' "$i" > "$tmp/src/metadata.json"
        snapshot_dir "$tmp/src" "$tmp/backups" "quickshell-caelestia" 3 >/dev/null
    done
    status=$?

    assert_status 0 "$status" "repeated snapshots should succeed"
    remaining="$(compgen -G "$tmp/backups/quickshell-caelestia-*" | wc -l | tr -d ' ')"
    assert_eq "3" "$remaining" "pruning should keep exactly three snapshots"
}

test_snapshot_dir_keeps_the_newest_snapshot_when_pruning() {
    local tmp newest
    tmp="$(new_tmpdir)"
    make_fixture "$tmp"

    snapshot_dir "$tmp/src" "$tmp/backups" "quickshell-caelestia" 2 >/dev/null
    printf 'revision-2\n' > "$tmp/src/metadata.json"
    newest="$(snapshot_dir "$tmp/src" "$tmp/backups" "quickshell-caelestia" 2)"

    assert_file_exists "$newest"
    assert_eq "revision-2" "$(cat "$newest/metadata.json")" "pruning should never remove the newest snapshot"
}

test_wait_for_nonempty_file_returns_immediately_when_it_is_there() {
    local tmp status
    tmp="$(new_tmpdir)"
    printf 'scheme\n' > "$tmp/scheme.json"

    wait_for_nonempty_file "$tmp/scheme.json" 0
    status=$?

    assert_status 0 "$status" "an existing file should not be waited on"
}

test_wait_for_nonempty_file_times_out_on_a_missing_file() {
    local tmp status
    tmp="$(new_tmpdir)"

    wait_for_nonempty_file "$tmp/absent.json" 0
    status=$?

    assert_status 1 "$status" "a file that never arrives should report a timeout"
}

test_wait_for_nonempty_file_treats_an_empty_file_as_absent() {
    local tmp status
    tmp="$(new_tmpdir)"
    : > "$tmp/scheme.json"

    wait_for_nonempty_file "$tmp/scheme.json" 0
    status=$?

    assert_status 1 "$status" "a truncated file is not yet usable"
}

test_wait_for_nonempty_file_returns_once_the_file_lands() {
    local tmp status
    tmp="$(new_tmpdir)"

    ( sleep 1; printf 'scheme\n' > "$tmp/scheme.json" ) &
    wait_for_nonempty_file "$tmp/scheme.json" 5
    status=$?
    wait

    assert_status 0 "$status" "the wait should end as soon as the file is written"
}

test_validate_install_manifest_accepts_a_complete_tree() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root/usr/bin"
    : > "$tmp/root/usr/bin/app"
    printf '/usr/bin/app\n' > "$tmp/manifest.txt"

    validate_install_manifest "$tmp/manifest.txt" "$tmp/root"
    status=$?

    assert_status 0 "$status" "a manifest whose paths all exist should pass"
}

test_validate_install_manifest_rejects_a_missing_path() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root/usr/bin"
    : > "$tmp/root/usr/bin/app"
    printf '/usr/bin/app\n/usr/bin/absent\n' > "$tmp/manifest.txt"

    validate_install_manifest "$tmp/manifest.txt" "$tmp/root" 2>/dev/null
    status=$?

    assert_status 1 "$status" "a manifest referencing a missing path should fail"
}

test_validate_install_manifest_rejects_vcs_metadata() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root/usr/share/.git"
    : > "$tmp/root/usr/share/.git/config"
    printf '/usr/share/.git/config' > "$tmp/manifest.txt"

    validate_install_manifest "$tmp/manifest.txt" "$tmp/root" 2>/dev/null
    status=$?

    assert_status 1 "$status" "VCS metadata must not be accepted in the package manifest"
}

test_validate_install_manifest_rejects_a_missing_manifest() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root"

    validate_install_manifest "$tmp/absent.txt" "$tmp/root" 2>/dev/null
    status=$?

    assert_status 1 "$status" "a missing manifest should fail"
}

test_validate_install_manifest_checks_the_unterminated_last_entry() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root/usr/bin"
    : > "$tmp/root/usr/bin/app"
    printf '/usr/bin/app\n/usr/bin/absent' > "$tmp/manifest.txt"

    validate_install_manifest "$tmp/manifest.txt" "$tmp/root" 2>/dev/null
    status=$?

    assert_status 1 "$status" "the final entry must be checked even without a trailing newline"
}

test_validate_install_manifest_accepts_a_cmake_shaped_manifest() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root/usr/share/caelestia/src"
    : > "$tmp/root/usr/share/caelestia/src/hyprland.conf"
    : > "$tmp/root/usr/share/caelestia/src/starship.toml"
    printf '/usr/share/caelestia/src/hyprland.conf\n/usr/share/caelestia/src/starship.toml' \
        > "$tmp/manifest.txt"

    validate_install_manifest "$tmp/manifest.txt" "$tmp/root"
    status=$?

    assert_status 0 "$status" "a CMake-shaped manifest of existing files should pass"
}

make_prune_fixture() {
    local tmp="$1"
    mkdir -p "$tmp/root/services" "$tmp/root/modules/x" \
        "$tmp/root/assets/icons/yet-another-monochrome-icon-set/actions" \
        "$tmp/root/assets/fonts"

    printf 'new\n' > "$tmp/root/services/Audio.qml"
    printf 'stale\n' > "$tmp/root/services/Stale.qml"
    printf 'old\n' > "$tmp/root/modules/x/Old.qml"
    printf 'icon\n' > "$tmp/root/assets/icons/yet-another-monochrome-icon-set/actions/a.svg"
    printf 'mine\n' > "$tmp/root/assets/fonts/MyFont.ttf"
    printf 'state\n' > "$tmp/root/.current_commit"

    printf '%s/services/Audio.qml\n' "$tmp/root" > "$tmp/listing.txt"
}

test_prune_install_root_removes_what_the_artifact_no_longer_ships() {
    local tmp status pruned
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"

    pruned="$(prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root")"
    status=$?

    assert_status 0 "$status" "a prune of a readable tree should succeed"
    assert_contains "$pruned" "services/Stale.qml" "the unshipped file is reported"
    assert_file_missing "$tmp/root/services/Stale.qml"
    assert_file_exists "$tmp/root/services/Audio.qml"
    rm -rf "$tmp"
}

test_prune_install_root_keeps_what_the_artifact_does_not_own() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"

    prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root" \
        assets/fonts assets/icons/yet-another-monochrome-icon-set .current_commit >/dev/null
    status=$?

    assert_status 0 "$status" "the prune should succeed"
    assert_file_exists "$tmp/root/assets/fonts/MyFont.ttf"
    assert_file_exists "$tmp/root/assets/icons/yet-another-monochrome-icon-set/actions/a.svg"
    assert_file_exists "$tmp/root/.current_commit"
    rm -rf "$tmp"
}

test_prune_install_root_drops_a_directory_the_artifact_dropped() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"

    prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root" >/dev/null
    status=$?

    assert_status 0 "$status" "the prune should succeed"
    assert_file_missing "$tmp/root/modules/x/Old.qml"
    assert_file_missing "$tmp/root/modules/x"
    assert_is_dir "$tmp/root/services"
    rm -rf "$tmp"
}

test_prune_install_root_removes_dangling_symlinks() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"
    ln -s /nonexistent/target "$tmp/root/services/Gone.qml"

    prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root" >/dev/null
    status=$?

    assert_status 0 "$status" "the prune should succeed"
    assert_file_missing "$tmp/root/services/Gone.qml"
    rm -rf "$tmp"
}

test_prune_install_root_only_counts_paths_under_the_prefix() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"
    mkdir -p "$tmp/elsewhere/services"
    printf 'other tree\n' > "$tmp/elsewhere/services/Stale.qml"
    printf '%s/services/Audio.qml\n%s/elsewhere/services/Stale.qml\n' \
        "$tmp/root" "$tmp" > "$tmp/listing.txt"

    prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root" >/dev/null
    status=$?

    assert_status 0 "$status" "the prune should succeed"
    assert_file_missing "$tmp/root/services/Stale.qml" \
        "an entry under another prefix must not protect a file in the config tree"
    assert_file_exists "$tmp/elsewhere/services/Stale.qml" \
        "the prune must not reach outside the config tree"
    rm -rf "$tmp"
}

test_prune_install_root_reads_an_unterminated_last_entry() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"
    printf '%s/services/Audio.qml\n%s/services/Last.qml' "$tmp/root" "$tmp/root" > "$tmp/listing.txt"
    printf 'new\n' > "$tmp/root/services/Last.qml"

    prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root" >/dev/null
    status=$?

    assert_status 0 "$status" "the prune should succeed"
    assert_file_exists "$tmp/root/services/Last.qml"
    rm -rf "$tmp"
}

test_prune_install_root_accepts_a_release_archive_listing() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"
    printf 'quickshell/\nquickshell/caelestia/\nquickshell/caelestia/services/\n' > "$tmp/listing.txt"
    printf 'quickshell/caelestia/services/Audio.qml\nquickshell/caelestia/assets/\nbin/caelestia\n' >> "$tmp/listing.txt"

    prune_install_root "$tmp/root" "$tmp/listing.txt" "quickshell/caelestia" >/dev/null
    status=$?

    assert_status 0 "$status" "an archive listing names the root and its directories too"
    assert_file_exists "$tmp/root/services/Audio.qml"
    assert_file_missing "$tmp/root/services/Stale.qml"
    assert_is_dir "$tmp/root/assets" "a directory the archive ships stays even once it is empty"
    rm -rf "$tmp"
}

test_prune_install_root_fails_without_a_listing() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"

    prune_install_root "$tmp/root" "$tmp/absent.txt" "$tmp/root" >/dev/null 2>&1
    status=$?

    assert_status 1 "$status" "an unreadable artifact listing should fail"
    assert_file_exists "$tmp/root/services/Stale.qml"
    rm -rf "$tmp"
}

test_prune_install_root_tolerates_a_missing_root() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_prune_fixture "$tmp"

    prune_install_root "$tmp/absent" "$tmp/listing.txt" "$tmp/root" >/dev/null 2>&1
    status=$?

    assert_status 0 "$status" "a config directory that was never created has nothing to prune"
    rm -rf "$tmp"
}

# The copy helpers escalate through caelestia_sudo. These tests write into a directory the
# running user owns, so the shim only has to run the command it was given.
caelestia_sudo() { "$@"; }

make_stage_fixture() {
    local tmp="$1"
    mkdir -p "$tmp/stage/usr/bin" "$tmp/stage/usr/share/app" "$tmp/dest"
    printf '#!/bin/sh\n' > "$tmp/stage/usr/bin/app"
    chmod 0755 "$tmp/stage/usr/bin/app"
    printf 'data\n' > "$tmp/stage/usr/share/app/data.txt"
}

test_privileged_copy_file_copies_the_source_with_the_requested_mode() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/dest"
    printf 'font\n' > "$tmp/source.ttf"
    chmod 0777 "$tmp/source.ttf"

    privileged_copy_file "$tmp/source.ttf" "$tmp/dest/source.ttf" 0644
    status=$?

    assert_status 0 "$status" "a regular file should be copied"
    assert_eq "font" "$(cat "$tmp/dest/source.ttf")" "with the source's contents"
    assert_eq "644" "$(stat -c %a "$tmp/dest/source.ttf")" "and the mode the caller asked for"
}

test_privileged_copy_file_refuses_a_symlinked_source() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/dest"
    printf 'elsewhere\n' > "$tmp/real.ttf"
    ln -s "$tmp/real.ttf" "$tmp/link.ttf"

    privileged_copy_file "$tmp/link.ttf" "$tmp/dest/link.ttf" 0644 2>/dev/null
    status=$?

    assert_status 1 "$status" "a source that is a link must not be opened"
    assert_file_missing "$tmp/dest/link.ttf" "and so nothing is put in its place"
}

test_privileged_copy_tree_keeps_the_layout_and_the_modes() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_stage_fixture "$tmp"

    privileged_copy_tree "$tmp/stage" "$tmp/dest"
    status=$?

    assert_status 0 "$status" "a tree of plain files should be promoted"
    assert_file_exists "$tmp/dest/usr/share/app/data.txt"
    assert_eq "$(stat -c %a "$tmp/stage/usr/bin/app")" "$(stat -c %a "$tmp/dest/usr/bin/app")" \
        "the executable should keep its mode"
    assert_eq "$(stat -c %a "$tmp/stage/usr/share/app/data.txt")" "$(stat -c %a "$tmp/dest/usr/share/app/data.txt")" \
        "and a data file should keep its own"
}

test_privileged_copy_tree_refuses_a_link_out_of_the_tree() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_stage_fixture "$tmp"
    ln -s /etc/passwd "$tmp/stage/usr/share/app/escape"

    privileged_copy_tree "$tmp/stage" "$tmp/dest" 2>/dev/null
    status=$?

    assert_status 1 "$status" "a link that leaves the tree must be refused"
    assert_file_missing "$tmp/dest/usr/bin/app" "and nothing at all may be copied across"
}

test_privileged_copy_tree_recreates_a_link_inside_its_own_directory() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_stage_fixture "$tmp"
    ln -s app "$tmp/stage/usr/bin/app-alias"

    privileged_copy_tree "$tmp/stage" "$tmp/dest"
    status=$?

    assert_status 0 "$status" "a command alias is part of what the build installed"
    [[ -L "$tmp/dest/usr/bin/app-alias" ]] || fail "the alias should be promoted as a link"
    assert_eq "app" "$(readlink "$tmp/dest/usr/bin/app-alias")" "pointing at the file beside it"
}

test_privileged_copy_tree_refuses_a_stage_that_holds_nothing() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/stage/usr/bin" "$tmp/dest"

    privileged_copy_tree "$tmp/stage" "$tmp/dest"
    status=$?

    assert_status 1 "$status" "an install that staged no file must not report success"
}

test_privileged_copy_tree_refuses_a_setuid_file() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_stage_fixture "$tmp"
    chmod 4755 "$tmp/stage/usr/bin/app"

    privileged_copy_tree "$tmp/stage" "$tmp/dest" 2>/dev/null
    status=$?

    assert_status 1 "$status" "a setuid file a user built must not arrive as root's"
    assert_file_missing "$tmp/dest/usr/bin/app"
}

test_install_staged_tree_installs_what_the_build_wrote_under_destdir() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/dest" "$tmp/src"
    printf 'built\n' > "$tmp/src/payload"

    install_staged_tree "$tmp/dest" sh -c 'mkdir -p "$DESTDIR/usr/bin" && cp "$1" "$DESTDIR/usr/bin/payload"' _ "$tmp/src/payload"
    status=$?

    assert_status 0 "$status" "the staged install should succeed"
    assert_file_exists "$tmp/dest/usr/bin/payload" "and put the build's file under the destination"
}

test_install_staged_tree_reports_a_failed_install() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/dest"

    install_staged_tree "$tmp/dest" sh -c 'exit 3'
    status=$?

    assert_status 1 "$status" "a failed install must be reported to the caller"
}

run_tests
