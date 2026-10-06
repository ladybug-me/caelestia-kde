#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOT="$REPO_ROOT/shell/modules/screenshot/ScreenshotAction.qml"
LOADER="$REPO_ROOT/shell/services/PluginLoader.qml"
API="$REPO_ROOT/shell/services/api/ShortcutsApi.qml"
WALL="$REPO_ROOT/shell/services/WallhavenSearcher.qml"
STORE="$REPO_ROOT/shell/services/PluginStore.qml"
VPN="$REPO_ROOT/shell/services/VPN.qml"

test_remote_upload_urls_are_validated_before_they_reach_a_shell() {
    assert_contains "$SHOT" 'URL="$(' "the upload response must land in a variable first"
    assert_contains "$SHOT" 'case "$URL" in https://*|http://*)' "and pass a scheme check"
    assert_not_contains "$SHOT" 'xdg-open "${root.imageSearchEngineBaseUrl}$(' \
        "the unquoted command substitution must be gone"
}

test_generated_qml_never_embeds_raw_plugin_strings() {
    assert_not_contains "$LOADER" 'command: ["cat", "${metaPath}"]' \
        "a plugin path with a quote must not be able to break out of generated QML"
    assert_contains "$LOADER" 'JSON.stringify(metaPath)' "paths travel as string literals"
    assert_contains "$LOADER" 'meta.path = ${JSON.stringify(pluginInfo.path)};'
    assert_not_contains "$LOADER" 'console.log("readMetadata called for"' \
        "per-plugin debug chatter stays out of the log"
}

test_the_public_shortcut_api_quotes_its_inputs() {
    assert_contains "$API" 'name: ${JSON.stringify(name)}' \
        "register() is a documented extension surface; its inputs are strings, not code"
}

test_wallhaven_logs_never_carry_the_apikey() {
    assert_contains "$WALL" 'apikey=<redacted>' "keys are redacted"
    assert_not_contains "$WALL" 'Logger.log("Wallhaven search:", url);' "raw URLs stay out of the log"
}

test_store_ids_cannot_escape_the_plugins_directory() {
    assert_contains "$STORE" 'isValidPluginId' "store ids are validated before use"
    assert_contains "$STORE" '\^\[A-Za-z0-9\]\[A-Za-z0-9._-\]\*\$/' "only plain directory names pass"
    assert_contains "$STORE" 'refusing to remove plugin with unsafe id' "removal is guarded"
}

test_vpn_interface_names_travel_as_arguments() {
    assert_not_contains "$VPN" '/sys/class/net/\${iface}' "config-supplied interfaces must not be interpolated"
    assert_contains "$VPN" '"--", iface' "they are passed as positional arguments instead"
}
