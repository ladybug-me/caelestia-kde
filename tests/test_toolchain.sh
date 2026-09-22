#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/toolchain.sh"

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

    with_path "$stub" "" install_cava_sdk arch
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

    with_path "$stub" "" install_cava_sdk arch
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

    with_path "$stub" "" install_cava_sdk debian
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

run_tests
