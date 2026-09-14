#!/usr/bin/env bash
# test_toolchain.sh - Tests for scripts/lib/toolchain.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/toolchain.sh"

# `caelestia_sudo` comes from privileges.sh in real use; these tests do NOT define
# it as a function, which would shadow the stub on PATH and hide whether the code
# went through the privilege helper at all.

# with_path <dir> <lrelease-fallback-path> <command> [args...]
#
# Runs <command> in a subshell whose PATH holds only <dir>, so the code under test
# sees exactly the stubs installed here. CAELESTIA_LRELEASE_FALLBACK is overridden
# too: its default absolute path may exist on a developer machine but not a CI
# runner, which would make the check non-deterministic.
with_path() {
    local dir="$1" fallback="$2"
    shift 2
    (
        PATH="$dir"
        export CAELESTIA_LRELEASE_FALLBACK="$fallback"
        "$@"
    )
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

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools
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
    # Records the call, then forwards the arguments so the test also proves the
    # install command survives the wrapper intact.
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools
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

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools
    status=$?

    assert_status 1 "$status" "a failed install should be reported to the caller"
}

test_install_linguist_tools_fails_when_no_package_manager_is_known() {
    local tmp stub status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    mkdir -p "$stub"

    with_path "$stub" "$tmp/absent-lrelease" install_linguist_tools
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
