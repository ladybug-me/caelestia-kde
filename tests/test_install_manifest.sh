#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/install-fs.sh"

test_validate_install_manifest_accepts_a_complete_tree() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/root/usr/bin"
    : > "$tmp/root/usr/bin/app"
    printf '# a comment\n\n/usr/bin/app\n' > "$tmp/manifest.txt"

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

test_validate_install_manifest_rejects_a_missing_manifest() {
    local tmp status
    tmp="$(new_tmpdir)"

    validate_install_manifest "$tmp/absent.txt" "$tmp/root" 2>/dev/null
    status=$?

    assert_status 1 "$status" "a missing manifest should fail"
}

test_validate_install_manifest_checks_absolute_entries_without_a_root() {
    local tmp status
    tmp="$(new_tmpdir)"
    : > "$tmp/app"
    printf '%s\n' "$tmp/app" > "$tmp/manifest.txt"

    validate_install_manifest "$tmp/manifest.txt"
    status=$?

    assert_status 0 "$status" "with no root the absolute entries should be checked as-is"
}

# CMake writes the manifest as a ';'-joined list with every ';' replaced by a
# newline (string(REPLACE ";" "\n" ...) + file(WRITE ...)), so a real manifest
# never ends in a newline. `read` reports failure on that unterminated last line,
# so a validator without the `|| [[ -n "$path" ]]` guard silently skips the final
# installed path. This is the shape every call site actually feeds in.
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

run_tests
