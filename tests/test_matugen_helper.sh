#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/log.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/privileges.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/packages.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/matugen.sh"

# install_matugen_github downloads the release asset and then asks for its checksum. curl
# writes to the path it is given, and the pinned release publishes no .sha256 at all: the
# stub answers that request the way the release does, by failing.
stub_asset_curl() {
    MATUGEN_TEST_ASSET="$1"
    curl() {
        local arg prev="" url="" dest=""
        for arg in "$@"; do
            [[ "$prev" == "-o" ]] && dest="$arg"
            [[ "$arg" == https://* ]] && url="$arg"
            prev="$arg"
        done
        case "$url" in
            *.sha256) return 22 ;;
            *) cp "$MATUGEN_TEST_ASSET" "$dest" ;;
        esac
    }
}

test_matugen_present_checks_path() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/tools"
    local tool p
    for tool in grep head sort sed cat; do
        p="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -s "$p" "$tmp/tools/$tool"
    done

    if (HOME="$tmp" PATH="$tmp/bin:$tmp/tools" matugen_present); then
        fail "matugen_present should return false when matugen is not on PATH"
    fi

    printf '#!/bin/sh\necho "matugen 4.2.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"

    if ! (HOME="$tmp" PATH="$tmp/bin:$tmp/tools" matugen_present); then
        fail "matugen_present should return true when matugen is on PATH"
    fi
}

test_matugen_present_rejects_outdated_version() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/tools"
    local tool p
    for tool in grep head sort sed cat; do
        p="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -s "$p" "$tmp/tools/$tool"
    done

    printf '#!/bin/sh\necho "matugen 3.1.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"

    if (HOME="$tmp" PATH="$tmp/bin:$tmp/tools" matugen_present); then
        fail "matugen_present should return false when matugen version is < 4.2"
    fi
}

test_cleanup_legacy_cargo_matugen_removes_binaries() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.cargo/bin"

    printf '#!/bin/sh\necho "matugen 3.1.0"\n' > "$tmp/.cargo/bin/matugen"
    chmod +x "$tmp/.cargo/bin/matugen"

    (
        HOME="$tmp"
        PATH="/usr/bin:/bin"
        caelestia_sudo() { "$@"; }
        export -f caelestia_sudo
        cleanup_legacy_cargo_matugen
    )

    assert_file_missing "$tmp/.cargo/bin/matugen" "cargo matugen should be removed"
}

test_ensure_matugen_reports_success_when_present() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin"
    printf '#!/bin/sh\necho "matugen 4.2.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"

    (
        HOME="$tmp"
        BASE_DISTRO=arch
        PATH="$tmp/bin:/usr/bin:/bin"
        if ! ensure_matugen; then
            exit 1
        fi
    ) || fail "ensure_matugen should succeed when matugen is present on PATH"
}

# tar writes member names as the archive states them, so an entry above the extraction
# directory lands in the user's own files. The pinned release is unpacked without a
# privilege prompt, which makes the entries the only thing standing between an archive and
# the tree it is emptied into.
test_install_matugen_github_refuses_an_archive_that_escapes_the_extraction_directory() {
    local tmp out status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/usr/local/bin" "$tmp/assets"

    : > "$tmp/assets/matugen"
    chmod +x "$tmp/assets/matugen"
    tar -czf "$tmp/assets/matugen-4.2.0-x86_64.tar.gz" -C "$tmp/assets" \
        --transform='s,^,../,' matugen 2>/dev/null

    out="$(
        HOME="$tmp"
        caelestia_sudo() {
            if [[ "$1" == "install" ]]; then
                cp "$4" "$tmp/usr/local/bin/matugen"
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        stub_asset_curl "$tmp/assets/matugen-4.2.0-x86_64.tar.gz"
        export -f curl

        install_matugen_github 2>&1
    )"
    status=$?

    assert_status 1 "$status" "an archive with an escaping entry must not be unpacked"
    assert_contains "$out" "Refusing to unpack" "and the refusal has to be said out loud"
    assert_file_missing "$tmp/usr/local/bin/matugen" "nothing from it may be installed"
}

test_install_matugen_github_installs_the_pinned_release() {
    local tmp out status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/usr/local/bin" "$tmp/assets"

    touch "$tmp/assets/matugen"
    chmod +x "$tmp/assets/matugen"
    tar -czf "$tmp/assets/matugen-4.2.0-x86_64.tar.gz" -C "$tmp/assets" matugen

    out="$(
        HOME="$tmp"
        caelestia_sudo() {
            if [[ "$1" == "install" ]]; then
                cp "$4" "$tmp/usr/local/bin/matugen"
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        stub_asset_curl "$tmp/assets/matugen-4.2.0-x86_64.tar.gz"
        export -f curl

        install_matugen_github 2>&1
    )"
    status=$?

    assert_status 0 "$status" "install_matugen_github should succeed when the pinned asset exists"
    assert_contains "$out" "releases/download/v4.2.0/matugen-4.2.0-x86_64.tar.gz" \
        "the download must come from the pinned release rather than from latest"
    assert_contains "$out" "No published checksum" "and the missing checksum must be said out loud"
    assert_file_exists "$tmp/usr/local/bin/matugen" "github release binary should be installed"
}

test_install_matugen_debian_falls_back_to_cargo() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/.cargo/bin"

    (
        HOME="$tmp"
        caelestia_sudo() {
            if [[ "$1" == "cp" || "$1" == "install" ]]; then
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo
        cargo() {
            if [[ "$1" == "install" ]]; then
                touch "$tmp/.cargo/bin/matugen"
                chmod +x "$tmp/.cargo/bin/matugen"
                return 0
            fi
            return 1
        }
        export -f cargo

        curl() { return 1; }
        export -f curl

        if ! install_matugen_debian; then
            exit 1
        fi
    ) || fail "install_matugen_debian should succeed via cargo fallback"

    assert_file_exists "$tmp/.cargo/bin/matugen" "cargo should install matugen when github download fails"
}

test_install_matugen_fedora_uses_github_when_copr_fails() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/usr/local/bin" "$tmp/assets"

    touch "$tmp/assets/matugen"
    chmod +x "$tmp/assets/matugen"
    tar -czf "$tmp/assets/matugen-4.2.0-x86_64.tar.gz" -C "$tmp/assets" matugen

    (
        HOME="$tmp"
        BASE_DISTRO="fedora"
        caelestia_sudo() {
            if [[ "$1" == "dnf" ]]; then
                return 1
            fi
            if [[ "$1" == "install" ]]; then
                cp "$4" "$tmp/usr/local/bin/matugen"
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        stub_asset_curl "$tmp/assets/matugen-4.2.0-x86_64.tar.gz"
        export -f curl

        if ! install_matugen_fedora; then
            exit 1
        fi
    ) || fail "install_matugen_fedora should succeed via github release when COPR fails"

    assert_file_exists "$tmp/usr/local/bin/matugen" "github release binary should be installed on fedora when copr fails"
}

test_install_matugen_fedora_falls_back_to_cargo_when_copr_and_github_fail() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/.cargo/bin"

    (
        HOME="$tmp"
        BASE_DISTRO="fedora"
        caelestia_sudo() {
            if [[ "$1" == "dnf" ]]; then
                return 1
            fi
            if [[ "$1" == "cp" || "$1" == "install" ]]; then
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        curl() { return 1; }
        export -f curl

        cargo() {
            if [[ "$1" == "install" ]]; then
                touch "$tmp/.cargo/bin/matugen"
                chmod +x "$tmp/.cargo/bin/matugen"
                return 0
            fi
            return 1
        }
        export -f cargo

        if ! install_matugen_fedora; then
            exit 1
        fi
    ) || fail "install_matugen_fedora should succeed via cargo fallback when COPR and GitHub fail"

    assert_file_exists "$tmp/.cargo/bin/matugen" "cargo should install matugen when fedora copr and github fail"
}

run_tests
