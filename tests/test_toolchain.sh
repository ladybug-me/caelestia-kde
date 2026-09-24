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

test_install_cava_sdk_fails_on_unknown_distro() {
    local tmp stub status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    mkdir -p "$stub"

    with_path "$stub" "" install_cava_sdk unknown
    status=$?

    assert_status 1 "$status" "an unknown distro should be reported as a failure"
}

# install_cava_sdk legitimately calls core utilities (mktemp for the archive,
# sha256sum and cut for the checksum); symlink the real ones into the stub
# directory so with_path's package-manager isolation keeps working. tar stays a
# recording stub: these tests assert on what tar is asked to extract, not on
# real extraction. The listing audit itself has its own tests, against real
# archives, in tests/test_download_hardening.sh.
expose_core_tools() {
    local stub="$1" tool
    shift
    mkdir -p "$stub"
    for tool in "$@"; do
        ln -sf "$(command -v "$tool")" "$stub/$tool"
    done
}

# A release server: serves the SDK archive from a fixture and publishes its
# sha256 beside it, the way the publishing workflow does. The published hash
# can be overridden to simulate a mismatch.
release_server_stub() {
    local stub="$1" log="$2" fixture="$3" published_sha="${4:-}"
    if [[ -z "$published_sha" ]]; then
        published_sha="$(sha256sum "$fixture" | cut -d' ' -f1)"
    fi
    mkdir -p "$stub"
    cat > "$stub/curl" <<STUB
#!/bin/bash
printf 'curl %s\n' "\$*" >> '$log'
url=""
dest=""
prev=""
for arg in "\$@"; do
    [[ "\$prev" == "-o" ]] && dest="\$arg"
    case "\$arg" in
        http*) url="\$arg" ;;
    esac
    prev="\$arg"
done
if [[ "\$url" == *.sha256 ]]; then
    printf '%s\n' '$published_sha' > "\$dest"
else
    cp "$fixture" "\$dest"
fi
STUB
    chmod +x "$stub/curl"
}

# An SDK-shaped fixture: the trees the real archive unpacks into /usr.
make_cava_release() {
    local dir="$1"
    mkdir -p "$dir/root/include/cava" "$dir/root/lib" "$dir/root/bin"
    printf 'header\n' > "$dir/root/include/cava/cavacore.h"
    printf 'library\n' > "$dir/root/lib/libcava.a"
    printf 'binary\n' > "$dir/root/bin/cava"
    tar -C "$dir/root" -czf "$dir/cava-sdk.tar.gz" include lib bin
    printf '%s\n' "$dir/cava-sdk.tar.gz"
}

test_install_cava_sdk_fetches_and_extracts_for_arch() {
    local tmp stub log status fixture
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    fixture="$(make_cava_release "$tmp/release")"
    stub_bin "$stub" uname "echo x86_64"
    release_server_stub "$stub" "$log" "$fixture"
    recording_stub "$stub" tar "$log"
    expose_core_tools "$stub" mktemp rm sha256sum cut cp
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 0 "$status" "installing the cava sdk for arch should succeed"
    assert_contains "$(calls_to "$log" curl)" "cava-x86_64-arch.tar.gz" "curl must fetch the arch archive"
    assert_contains "$(calls_to "$log" tar)" "--exclude=bin" "tar must pass --exclude=bin"
    assert_contains "$(calls_to "$log" tar)" "--no-same-owner" "tar must not restore the archive's own owner as root"
}

test_install_cava_sdk_fetches_for_aarch64() {
    local tmp stub log status fixture
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    fixture="$(make_cava_release "$tmp/release")"
    stub_bin "$stub" uname "echo aarch64"
    release_server_stub "$stub" "$log" "$fixture"
    recording_stub "$stub" tar "$log"
    expose_core_tools "$stub" mktemp rm sha256sum cut cp
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 0 "$status" "installing the cava sdk for aarch64 arch should succeed"
    assert_contains "$(calls_to "$log" curl)" "cava-aarch64-arch.tar.gz" "curl must fetch the aarch64 arch archive"
}

test_install_cava_sdk_maps_debian_to_ubuntu() {
    local tmp stub log status fixture
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    fixture="$(make_cava_release "$tmp/release")"
    stub_bin "$stub" uname "echo x86_64"
    release_server_stub "$stub" "$log" "$fixture"
    recording_stub "$stub" tar "$log"
    expose_core_tools "$stub" mktemp rm sha256sum cut cp
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "" install_cava_sdk debian
    status=$?

    assert_status 0 "$status" "installing the cava sdk for debian should succeed"
    assert_contains "$(calls_to "$log" curl)" "cava-x86_64-ubuntu.tar.gz" "curl must fetch the ubuntu archive for debian"
}

test_install_cava_sdk_refuses_an_archive_without_a_published_checksum() {
    local tmp stub log status
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    stub_bin "$stub" uname "echo x86_64"
    # fetches the artifact but never publishes a sidecar: verify_download
    # returns 2, and an archive destined for /usr must not survive that.
    recording_stub "$stub" curl "$log"
    recording_stub "$stub" tar "$log"
    expose_core_tools "$stub" mktemp rm sha256sum cut cp
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 1 "$status" "an unverified archive must not be unpacked into /usr"
    assert_eq "" "$(calls_to "$log" tar)" "tar must never run for an unverified archive"
}

test_install_cava_sdk_refuses_an_archive_with_a_mismatched_checksum() {
    local tmp stub log status fixture
    tmp="$(new_tmpdir)"
    stub="$tmp/bin"
    log="$tmp/calls.log"
    fixture="$(make_cava_release "$tmp/release")"
    stub_bin "$stub" uname "echo x86_64"
    release_server_stub "$stub" "$log" "$fixture" \
        "0000000000000000000000000000000000000000000000000000000000000000"
    recording_stub "$stub" tar "$log"
    expose_core_tools "$stub" mktemp rm sha256sum cut cp
    stub_bin "$stub" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_path "$stub" "" install_cava_sdk arch
    status=$?

    assert_status 1 "$status" "a checksum mismatch must not be unpacked into /usr"
    assert_eq "" "$(calls_to "$log" tar)" "tar must never run for a mismatched archive"
}

run_tests
