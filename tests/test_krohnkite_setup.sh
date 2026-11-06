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

run_tests
