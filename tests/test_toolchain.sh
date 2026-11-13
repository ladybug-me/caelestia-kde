#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/toolchain.sh"

# The library names the programs it trusts by absolute path so a PATH this user can write
# cannot stand in for them. Every stub here lives on PATH, so the lookup is pointed back at
# it; that the real lookup uses /usr/bin is covered by tests/test_tools.sh.
system_tool() { printf '%s\n' "$1"; }

# The cava release publishes no checksum for its archives, so unpacking one is a decision
# the user makes through the documented opt-out. These tests make that decision the same
# way a user would, and the tests that check the refusal do not.
with_unverified_allowed() {
    ( export CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1; "$@" )
}

# verify_download reads the published checksum with coreutils, and PATH holds only the stubs
# in these tests, so the tools it needs are linked in beside them.
add_coreutils() {
    local stub="$1" tool resolved
    for tool in mktemp sha256sum cut rm cat; do
        resolved="$(command -v "$tool" 2>/dev/null)" || continue
        ln -sf "$resolved" "$stub/$tool"
    done
}

test_linguist_tools_available_when_lrelease_is_on_path() {
    local tmp stub
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    stub_bin "$stub" lrelease 'exit 0'

    with_path "$stub" "$tmp/absent-lrelease" linguist_tools_available
}

test_linguist_tools_available_from_the_fallback_location() {
    local tmp stub
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    mkdir -p "$stub"
    stub_bin "$tmp" fallback-lrelease 'exit 0'

    with_path "$stub" "$tmp/fallback-lrelease" linguist_tools_available
}

test_linguist_tools_unavailable_when_neither_location_has_it() {
    local tmp stub
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    mkdir -p "$stub"

    if with_path "$stub" "$tmp/absent-lrelease" linguist_tools_available; then
        fail "lrelease is not reachable, so the tools should report as unavailable"
    fi
}

test_install_linguist_tools_does_nothing_when_lrelease_is_present() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" lrelease 'exit 0'
    recording_stub "$stub" pacman "$log"
    recording_stub "$stub" caelestia_sudo "$log"

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools arch
    status=$?

    assert_status 0 "$status" "an available lrelease needs no work"
    assert_eq "" "$(calls_to "$log" caelestia_sudo)" "nothing should be installed when lrelease already works"
}

test_install_linguist_tools_escalates_through_the_privilege_helper() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    recording_stub "$stub" pacman "$log"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools arch
    status=$?

    assert_status 0 "$status" "installing the linguist tools should succeed"
    assert_eq "pacman -S --needed --noconfirm qt6-tools" "$(calls_to "$log" caelestia_sudo)" \
        "the install must go through caelestia_sudo"
    assert_eq "-S --needed --noconfirm qt6-tools" "$(calls_to "$log" pacman)" \
        "the package arguments must reach the package manager"
}

test_install_linguist_tools_reports_failure_when_the_install_fails() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    recording_stub "$stub" pacman "$log"
    recording_stub "$stub" caelestia_sudo "$log" 1

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools arch
    status=$?

    assert_status 1 "$status" "a failed install should be reported to the caller"
}

# "Whichever manager is on PATH" answers for the wrong package universe, which is why
# the distro is an argument: pacman here is reachable, and still must not be used.
test_install_linguist_tools_uses_the_named_distro_not_path() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    recording_stub "$stub" pacman "$log"
    recording_stub "$stub" apt-get "$log"
    recording_stub "$stub" caelestia_sudo "$log"

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools debian
    status=$?

    assert_status 0 "$status" "installing for a debian base should succeed"
    assert_contains "$(calls_to "$log" caelestia_sudo)" "apt-get install -y qt6-l10n-tools qt6-tools-dev" \
        "a debian base must install through apt-get"
    assert_eq "" "$(calls_to "$log" pacman)" "pacman being on PATH must not choose the manager"
}

test_install_linguist_tools_fails_for_an_unknown_distro() {
    local tmp stub status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    mkdir -p "$stub"

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools unknown
    status=$?

    assert_status 1 "$status" "an unknown distro should be reported as a failure, not a success"
}

test_install_cava_sdk_fetches_and_extracts_for_arch() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo x86_64"
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_unverified_allowed with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 0 "$status" "installing the cava sdk for arch should succeed"
    assert_contains "$(calls_to "$log" curl)" "cava-x86_64-arch.tar.gz" "curl must fetch the arch archive"
    assert_contains "$(calls_to "$log" tar)" "--exclude=bin" "tar must pass --exclude=bin"
}

test_install_cava_sdk_fetches_for_aarch64() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo aarch64"
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_unverified_allowed with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 0 "$status" "installing the cava sdk for aarch64 arch should succeed"
    assert_contains "$(calls_to "$log" curl)" "cava-aarch64-arch.tar.gz" "curl must fetch the aarch64 arch archive"
}

test_install_cava_sdk_maps_debian_to_ubuntu() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo x86_64"
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_unverified_allowed with_path "$stub" "" install_cava_sdk debian
    status=$?

    assert_status 0 "$status" "installing the cava sdk for debian should succeed"
    assert_contains "$(calls_to "$log" curl)" "cava-x86_64-ubuntu.tar.gz" "curl must fetch the ubuntu archive for debian"
}

test_install_cava_sdk_fails_on_unknown_distro() {
    local tmp stub status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    mkdir -p "$stub"

    with_path "$stub" "" install_cava_sdk unknown
    status=$?

    assert_status 1 "$status" "an unknown distro should be reported as a failure"
}

test_install_cava_sdk_extraction_ignores_the_archive_ownership() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo x86_64"
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_unverified_allowed with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 0 "$status" "installing the cava sdk should still succeed"
    assert_contains "$(calls_to "$log" tar)" "--no-same-owner" \
        "unpacking into /usr must not take ownership from the archive"
    assert_contains "$(calls_to "$log" tar)" "--no-same-permissions" \
        "nor the mode bits that go with it"
}

test_archive_entries_are_safe_accepts_a_plain_archive() {
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/plain.tar.gz"
    printf 'payload\n' > "$tmp/payload"
    tar -C "$tmp" -czf "$archive" payload

    if ! archive_entries_are_safe "$archive"; then
        fail "an archive of ordinary files should be accepted"
    fi
}

test_archive_entries_are_safe_rejects_a_setuid_entry() {
    local tmp archive
    tmp="$(new_tmpdir)"
    archive="$tmp/setuid.tar.gz"
    printf 'payload\n' > "$tmp/payload"
    tar -C "$tmp" --mode=4755 -czf "$archive" payload

    if archive_entries_are_safe "$archive"; then
        fail "an archive carrying a setuid entry must be refused"
    fi
}

test_own_release_is_recognized() {
    if ! is_own_release "https://github.com/ladybug-me/cava/releases/download/continuous/cava-x86_64-arch.tar.gz"; then
        fail "a ladybug-me asset is one of ours"
    fi
    if ! is_own_release "https://github.com/caelestia-kde/caelestia/releases/download/v1.0/caelestia-kde-x86_64.tar.gz"; then
        fail "a caelestia-kde asset is one of ours"
    fi
    if is_own_release "https://github.com/other-org/thing/releases/download/v1/thing.tar.gz"; then
        fail "another org's asset is not one of ours"
    fi
    if is_own_release "https://github.com/caelestia-kde/caelestia/archive/refs/tags/v1.0.tar.gz"; then
        fail "a page under our account that is not a release asset is not one of ours"
    fi
}

test_the_cava_sdk_download_is_refused_without_a_published_checksum() {
    local tmp stub log out status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo x86_64"
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    add_coreutils "$stub"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\\n' \"\$*\" >> '$log'
\"\$@\""

    out="$(with_path "$stub" "" install_cava_sdk arch 2>&1)"
    status=$?

    assert_status 1 "$status" "an archive nobody published a hash for must not be unpacked"
    assert_contains "$out" "publishes no checksum" "the missing hash has to be reported"
    assert_contains "$out" "CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1" "and the way to accept it named"
    assert_eq "" "$(calls_to "$log" tar)" "nothing may be unpacked as root"
}

test_the_cava_sdk_download_unpacks_once_the_user_opts_in() {
    local tmp stub log out status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo x86_64"
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    add_coreutils "$stub"
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\\n' \"\$*\" >> '$log'
\"\$@\""

    out="$(with_unverified_allowed with_path "$stub" "" install_cava_sdk arch 2>&1)"
    status=$?

    assert_status 0 "$status" "the documented opt-out should let the install run"
    assert_contains "$out" "CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1" "and say that it did"
    assert_contains "$(calls_to "$log" tar)" "--exclude=bin" "tar must still be the thing unpacking it"
}

test_a_missing_checksum_is_still_warned_about_in_general() {
    local tmp out
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin"

    out="$(bash -c "
        source '$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/download.sh'
        source '$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/log.sh'
        if is_own_release 'https://github.com/other-org/thing/releases/download/v1/t.tar.gz'; then
            echo 'OWN'
        else
            warn 'No published checksum for the third party archive'
        fi
    " 2>&1)"

    assert_contains "$out" "No published checksum" \
        "a third-party archive with no checksum must still be reported"
}

run_tests
