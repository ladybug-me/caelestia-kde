#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# What checkout_may_use_prebuilt decides is the crate's own behaviour now, and the crate
# tests it (installer/src/steps/build_shell.rs): a released tag, main on its remote tip, a
# stale main, another branch, and a version.env that disagrees with the checkout. What is
# left here is the launcher, which is what fetches the installer before any Rust exists.
fetch_function() {
    local name="$1" source
    source="$(awk -v fn="$name" '
        $0 ~ "^" fn "\\(\\) \\{" { capture = 1 }
        capture { print }
        capture && $0 == "}" { exit }
    ' "$REPO_ROOT/scripts/setup.sh")"
    if [[ -z "$source" ]]; then
        fail "could not find $name in scripts/setup.sh"
    fi
    printf '%s\n' "$source"
}

FETCH_SOURCE="$(fetch_function fetch_installer)"
MATCH_SOURCE="$(fetch_function installer_matches_checkout)"

fetch_with_status() {
    local status="$1" arch="${2:-x86_64}"
    BIN="$(mktemp -d)/caelestia-install"
    bash -c "
        BIN='$BIN'
        tui_version() { echo '9.9.9'; }
        release_tag() { echo 'v9.9.9'; }
        fetch_asset() { : > \"\$2\"; return 0; }
        verify_download() { return $status; }
        uname() { echo '$arch'; }
        $FETCH_SOURCE
        fetch_installer
    "
}

test_a_verified_download_succeeds_quietly() {
    local out err status

    fetch_with_status 0 >/dev/null 2>&1
    status=$?
    if [[ $status -ne 0 ]]; then
        fail "a verified download should succeed, got status $status"
    fi

    out="$(fetch_with_status 0 2>/dev/null)"
    if [[ -n "$out" ]]; then
        fail "a verified download must print nothing to stdout, got: $out"
    fi

    err="$(fetch_with_status 0 2>&1 >/dev/null)"
    if [[ -n "$err" ]]; then
        fail "a verified download must print nothing to stderr, got: $err"
    fi
}

test_a_checksum_mismatch_is_fatal() {
    local err status

    fetch_with_status 1 >/dev/null 2>&1
    status=$?
    if [[ $status -eq 0 ]]; then
        fail "a mismatched download must fail the install"
    fi

    err="$(fetch_with_status 1 2>&1 >/dev/null)"
    case "$err" in
        *"checksum"*) ;;
        *) fail "a mismatched download should say so on stderr; got: $err" ;;
    esac
}

test_a_release_without_a_checksum_is_fatal() {
    local err status

    fetch_with_status 2 >/dev/null 2>&1
    status=$?
    if [[ $status -eq 0 ]]; then
        fail "a release with no published checksum must not be trusted"
    fi

    err="$(fetch_with_status 2 2>&1 >/dev/null)"
    case "$err" in
        *"no checksum"*) ;;
        *) fail "the reason should name the missing checksum; got: $err" ;;
    esac
}

test_an_architecture_with_no_release_is_reported() {
    local err status

    fetch_with_status 0 riscv64 >/dev/null 2>&1
    status=$?
    if [[ $status -eq 0 ]]; then
        fail "an architecture with no published binary must not be attempted"
    fi

    err="$(fetch_with_status 0 riscv64 2>&1 >/dev/null)"
    case "$err" in
        *"no prebuilt installer"*) ;;
        *) fail "the unsupported architecture should be named; got: $err" ;;
    esac
}

test_a_binary_from_another_version_is_refused() {
    local dir binary

    dir="$(mktemp -d)"
    binary="$dir/caelestia-install"
    printf '#!/bin/sh\necho 1.2.3\n' > "$binary"
    chmod +x "$binary"

    if bash -c "
        BIN='$binary'
        tui_version() { echo '9.9.9'; }
        $MATCH_SOURCE
        installer_matches_checkout
    " >/dev/null 2>&1; then
        fail "a binary that disagrees with the checkout must be refused"
    fi

    printf '#!/bin/sh\necho 9.9.9\n' > "$binary"
    chmod +x "$binary"

    if ! bash -c "
        BIN='$binary'
        tui_version() { echo '9.9.9'; }
        $MATCH_SOURCE
        installer_matches_checkout
    " >/dev/null 2>&1; then
        fail "a binary that matches the checkout must be accepted"
    fi
}
run_tests