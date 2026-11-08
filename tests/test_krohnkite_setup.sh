#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/shell/scripts/krohnkite_setup.sh"

test_script_exists_and_is_executable() {
    [[ -f "$SETUP_SCRIPT" ]] || fail "setup script should exist at $SETUP_SCRIPT"
    [[ -x "$SETUP_SCRIPT" ]] || fail "setup script should be executable"
}

test_help_flag_displays_usage() {
    local output
    output="$(bash "$SETUP_SCRIPT" --help 2>&1)" || fail "setup script --help should exit with 0"
    assert_contains "$output" "Usage: krohnkite_setup.sh" "help output should include usage information"
}

test_status_outputs_valid_json() {
    local output
    output="$(bash "$SETUP_SCRIPT" --status 2>&1)" || fail "setup script --status should exit with 0"

    python3 -c '
import json, sys
data = json.loads(sys.argv[1])
for key in ["installed", "latest", "update_available", "download_url"]:
    if key not in data:
        sys.exit(1)
' "$output" || fail "setup script --status must emit JSON containing installed, latest, update_available, download_url"
}

test_download_url_is_https_kwinscript() {
    local output dl_url
    output="$(bash "$SETUP_SCRIPT" --status 2>&1)" || fail "setup script --status failed"
    dl_url="$(python3 -c 'import json, sys; print(json.loads(sys.argv[1]).get("download_url") or "")' "$output")"

    if [[ -n "$dl_url" ]]; then
        [[ "$dl_url" =~ ^https://.*\.kwinscript$ ]] || fail "download URL must be HTTPS and end with .kwinscript, got $dl_url"
    fi
}

# The download helpers out of the script under test, so the checksum path is driven rather
# than restated. Sourcing the whole file would run its command dispatcher.
download_helpers() {
    eval "$(extract_function "$SETUP_SCRIPT" verify_kwinscript)"
    eval "$(extract_function "$SETUP_SCRIPT" release_tag_of_url)"
    eval "$(extract_function "$SETUP_SCRIPT" download_kwinscript)"
    eval "$(grep -E '^KROHNKITE_(PINNED_VERSION|SHA256)=' "$SETUP_SCRIPT")"
}

# curl is the only thing that talks to Codeberg, and it writes to the path it is given: the
# stub answers the sidecar request with $KROHN_SUM and every other request with the asset.
stub_release_curl() {
    curl() {
        local arg prev="" url="" dest=""
        for arg in "$@"; do
            [[ "$prev" == "-o" ]] && dest="$arg"
            [[ "$arg" == https://* ]] && url="$arg"
            prev="$arg"
        done
        case "$url" in
            *.sha256)
                [[ -n "${KROHN_SUM:-}" ]] || return 22
                printf '%s  krohnkite.kwinscript\n' "$KROHN_SUM" > "$dest"
                ;;
            *) cp "$KROHN_ASSET" "$dest" ;;
        esac
    }
}

test_download_refuses_an_asset_that_does_not_match_its_checksum() {
    local tmp out status
    tmp="$(new_tmpdir)"
    printf 'asset\n' > "$tmp/asset"

    out="$(
        download_helpers
        KROHN_ASSET="$tmp/asset"
        KROHN_SUM="$(printf 'something else\n' | sha256sum | cut -d' ' -f1)"
        stub_release_curl
        download_kwinscript "https://codeberg.org/a/b/raw/krohnkite.kwinscript" "$tmp/download" 2>&1
    )"
    status=$?

    assert_status 1 "$status" "an asset that does not match its checksum must not be installed"
    assert_contains "$out" "checksum mismatch" "and the reason has to be stated"
}

test_download_accepts_an_asset_that_matches_its_checksum() {
    local tmp out status
    tmp="$(new_tmpdir)"
    printf 'asset\n' > "$tmp/asset"

    out="$(
        download_helpers
        KROHN_ASSET="$tmp/asset"
        KROHN_SUM="$(sha256sum "$tmp/asset" | cut -d' ' -f1)"
        stub_release_curl
        download_kwinscript "https://codeberg.org/a/b/raw/krohnkite.kwinscript" "$tmp/download" 2>&1
    )"
    status=$?

    assert_status 0 "$status" "a published checksum that matches should be accepted"
    assert_not_contains "$out" "checksum mismatch" "without complaining about the asset"
    assert_file_exists "$tmp/download"
}

test_download_says_so_when_the_release_publishes_no_checksum() {
    local tmp out status
    tmp="$(new_tmpdir)"
    printf 'asset\n' > "$tmp/asset"

    out="$(
        download_helpers
        KROHN_ASSET="$tmp/asset"
        stub_release_curl
        download_kwinscript "https://codeberg.org/a/b/raw/krohnkite.kwinscript" "$tmp/download" 2>&1
    )"
    status=$?

    assert_status 0 "$status" "a release with no checksum is still installed"
    assert_contains "$out" "no published checksum" "but only after saying it is unverified"
    assert_contains "$out" "SHA-256" "with the hash of what was installed"
}

# Codeberg publishes no sidecar, so the bytes of the pinned release are tied to it by a hash
# in the script instead. A release asset can be replaced under its tag, which is the thing
# that pin is there to catch.
test_the_pinned_asset_hash_names_a_release() {
    local version
    version="$(sed -n 's/^KROHNKITE_PINNED_VERSION="\([^"]*\)"$/\1/p' "$SETUP_SCRIPT" | head -n1)"

    [[ -n "$version" ]] || fail "the script should name the release its hash was taken from"
    assert_file_matches "$SETUP_SCRIPT" '^KROHNKITE_SHA256="[0-9a-f]{64}"$' \
        "and carry a SHA-256 to check that release's asset against"
}

test_download_refuses_the_pinned_release_when_its_bytes_changed() {
    local tmp out status url
    tmp="$(new_tmpdir)"
    printf 'asset\n' > "$tmp/asset"
    url="https://codeberg.org/anametologin/Krohnkite/releases/download/0.9.11.0/krohnkite.kwinscript"

    out="$(
        download_helpers
        KROHN_ASSET="$tmp/asset"
        stub_release_curl
        download_kwinscript "$url" "$tmp/download" 2>&1
    )"
    status=$?

    assert_status 1 "$status" "an asset whose bytes changed under the pinned tag must not be installed"
    assert_contains "$out" "checksum mismatch" "and the reason has to be stated"
    assert_contains "$out" "got $(sha256sum "$tmp/asset" | cut -d' ' -f1)" "naming what arrived"
    assert_contains "$out" "expected $(sed -n 's/^KROHNKITE_SHA256="\([^"]*\)"$/\1/p' "$SETUP_SCRIPT" | head -n1)" \
        "and what the pinned release holds"
}

test_download_accepts_the_pinned_release_when_the_bytes_match_the_pin() {
    local tmp out status url
    tmp="$(new_tmpdir)"
    printf 'asset\n' > "$tmp/asset"
    url="https://codeberg.org/anametologin/Krohnkite/releases/download/0.9.11.0/krohnkite.kwinscript"

    out="$(
        download_helpers
        KROHN_ASSET="$tmp/asset"
        KROHNKITE_SHA256="$(sha256sum "$tmp/asset" | cut -d' ' -f1)"
        stub_release_curl
        download_kwinscript "$url" "$tmp/download" 2>&1
    )"
    status=$?

    assert_status 0 "$status" "the bytes the pin names are accepted"
    assert_not_contains "$out" "unverified" "without calling them unverified"
    assert_file_exists "$tmp/download"
}

run_tests
