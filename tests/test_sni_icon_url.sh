#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "$0")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tray_icon_function="$(sed -n '/function getTrayIcon/,/function getBatteryIcon/p' "$REPO_ROOT/shell/utils/Icons.qml")"

test_provider_urls_are_preserved_before_legacy_path_rewrite() {
    local expected
    expected=$'if (icon.startsWith("image://icon/"))\n            return icon;\n\n        if (icon.includes("?path="))'
    assert_contains "$tray_icon_function" "$expected" "image-provider URLs must bypass filesystem path normalization"
}

test_custom_icon_override_keeps_precedence() {
    local override_line provider_line
    override_line="$(grep -nF 'for (const sub of GlobalConfig.bar.tray.iconSubs.values' <<<"$tray_icon_function" | cut -d: -f1)"
    provider_line="$(grep -nF 'if (icon.startsWith("image://icon/"))' <<<"$tray_icon_function" | cut -d: -f1)"
    if [[ -z "$override_line" || -z "$provider_line" || "$override_line" -ge "$provider_line" ]]; then
        fail "configured tray icon substitutions must run before provider URL passthrough"
    fi
}

run_tests
