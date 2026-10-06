#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"

test_every_hotspot_setting_reader_uses_global_config() {
    local readers
    readers="$(grep -rn 'Config\.services\.hotspot' "$SHELL_DIR" --include='*.qml' \
        | grep -v 'GlobalConfig\.services\.hotspot' || true)"

    assert_eq "" "$readers" "every reader of the hotspot settings should use GlobalConfig"
}

test_the_profile_id_has_one_definition() {
    local controller="$REPO_ROOT/shell/plugin/src/Caelestia/Services/HotspotController.cpp"

    assert_file_exists "$controller"
    assert_eq "1" "$(grep -c 'caelestia-hotspot' "$controller")" \
        "the profile id should be written once, in the controller"

    local literals
    literals="$(grep -rn 'caelestia-hotspot' "$SHELL_DIR" --include='*.qml' || true)"
    assert_eq "" "$literals" "no QML file should carry its own copy of the profile id"
}

test_the_hotspot_state_has_one_owner() {
    local adapter
    adapter="$(cat "$SHELL_DIR/services/Nmcli.qml")"

    assert_contains "$adapter" "readonly property HotspotController hotspot: NmQt.hotspot" \
        "Nmcli should expose the hotspot controller itself"
    assert_not_contains "$adapter" "readonly property bool hotspotSupported" \
        "Nmcli should not copy the hotspot state into its own properties"
}

test_every_switch_reads_the_backend() {
    local file
    for file in \
        "$SHELL_DIR/modules/utilities/cards/Toggles.qml" \
        "$SHELL_DIR/modules/nexus/pages/network/HotspotPage.qml"; do
        assert_contains "$(cat "$file")" "Nmcli.hotspot.enabled" \
            "$(basename "$file") should read the hotspot state from the controller"
    done

    local leftover
    leftover="$(grep -rn 'Binding on checked' "$SHELL_DIR/modules" --include='*.qml' || true)"
    assert_eq "" "$leftover" "no switch should need a Binding to survive its own click"
}

test_one_tap_does_not_share_an_open_network() {
    local switch
    switch="$(cat "$SHELL_DIR/services/HotspotSwitch.qml")"

    assert_contains "$switch" 'hotspotSsid.length === 0 && hotspotPassword.length === 0' \
        "an unconfigured hotspot should not start"
    assert_contains "$switch" "Settings > Network > Hotspot" \
        "and the refusal should say where to set it up"

    local adapter
    adapter="$(cat "$SHELL_DIR/services/Nmcli.qml")"
    assert_not_contains "$adapter" "Toaster.toast" \
        "a passthrough adapter should not own a user-facing decision"
}

test_the_profile_id_is_read_not_restated() {
    local page
    page="$(cat "$SHELL_DIR/modules/nexus/pages/network/HotspotPage.qml")"

    assert_contains "$page" "Nmcli.hotspot.profileId" \
        "the page should read the profile id from the controller"
}

test_the_password_rule_has_one_definition() {
    local controller="$REPO_ROOT/shell/plugin/src/Caelestia/Services/HotspotController.cpp"
    local page="$SHELL_DIR/modules/nexus/pages/network/HotspotPage.qml"

    assert_eq "1" "$(grep -c 'return 8;' "$controller")" \
        "the minimum password length should be written once, in the controller"
    assert_contains "$(cat "$controller")" "password.size() < minPasswordLength()" \
        "the controller should refuse a password under its own minimum"
    assert_contains "$(cat "$page")" "text.length >= Nmcli.hotspot.minPasswordLength" \
        "the form should read the minimum from the controller"

    local literals
    literals="$(grep -n 'length >= 8\|length < 8\|at least 8 characters' "$page" || true)"
    assert_eq "" "$literals" "no QML file should carry its own copy of the password rule"
}

run_tests
