#!/usr/bin/env bash
# suite: fast
#
# The installer decides what may be installed with `sha256sum`, `cut`, `stat`, `tar`, `curl`
# and `jq`. A source install puts the user's own bin directory first on PATH, so a lookup that
# respects PATH lets a directory this user can write supply the answer: a digest that matches
# whatever was downloaded, a release URL naming different content, or a file called root's
# when it is not. These tests pin the lookup to the system directories.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$REPO_ROOT/scripts/lib/tools.sh"

test_every_decision_program_resolves_to_an_absolute_path() {
    local name resolved
    for name in sha256sum cut stat tar curl jq; do
        resolved="$(system_tool "$name")"
        assert_contains "$resolved" "/" "system_tool $name should name a path, not a word"
        case "$resolved" in
            /usr/bin/* | /bin/* | /usr/sbin/* | /sbin/*) ;;
            *) fail "system_tool $name did not resolve to a system directory: $resolved" ;;
        esac
        [[ -x "$resolved" ]] || fail "system_tool $name is not executable: $resolved"
    done
}

test_a_directory_this_user_can_write_cannot_stand_in_for_a_system_program() {
    local tmp fake resolved
    tmp="$(new_tmpdir)"
    fake="$tmp/bin"
    stub_bin "$fake" sha256sum 'printf "%s  -\n" 0000000000000000000000000000000000000000000000000000000000000000'
    stub_bin "$fake" jq 'printf "%s\n" https://evil.example/payload'

    resolved="$(PATH="$fake" system_tool sha256sum)"
    assert_not_contains "$resolved" "$fake" "a sha256sum this user can write must not be chosen"

    resolved="$(PATH="$fake" system_tool jq)"
    assert_not_contains "$resolved" "$fake" "a jq this user can write must not be chosen"

    rm -rf "$tmp"
}

test_a_system_without_the_program_still_falls_back_to_path() {
    local tmp resolved
    tmp="$(new_tmpdir)"
    stub_bin "$tmp/bin" caelestia-not-a-system-program 'exit 0'

    resolved="$(PATH="$tmp/bin" system_tool caelestia-not-a-system-program)"
    assert_eq "$tmp/bin/caelestia-not-a-system-program" "$resolved" \
        "a program with no system copy is still found, so an unusual system keeps working"

    rm -rf "$tmp"
}

# Each of these turns user-reachable content into a root install decision. A body that reverts
# to calling the bare name drops the protection without any test above noticing.
test_every_decision_site_goes_through_the_lookup() {
    local file function expected
    while IFS='|' read -r file function expected; do
        assert_contains "$(extract_function "$REPO_ROOT/$file" "$function")" "system_tool $expected" \
            "$function in $file must resolve $expected by absolute path"
    done <<'SITES'
scripts/lib/download.sh|file_sha256|sha256sum
scripts/lib/download.sh|verify_download|cut
scripts/lib/download.sh|archive_entries_are_safe|tar
installer/distro/debian/packages.sh|darkly_deb_asset_url|jq
installer/distro/debian/packages.sh|cliphist_asset_url|jq
installer/distro/fedora/packages.sh|darkly_rpm_asset_url|jq
scripts/lib/matugen.sh|matugen_asset_url|jq
SITES
}

run_tests
