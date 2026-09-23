#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NMQT_HPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/NmQt.hpp"
NMQT_CPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/NmQt.cpp"
NMCLI_QML="$REPO_ROOT/shell/services/Nmcli.qml"
SERVICES_HPP="$REPO_ROOT/shell/plugin/src/Caelestia/Config/serviceconfig.hpp"
TOGGLES_QML="$REPO_ROOT/shell/modules/utilities/cards/Toggles.qml"
QUICK_TOGGLES_PAGE="$REPO_ROOT/shell/modules/nexus/pages/utilities/QuickTogglesPage.qml"
NETWORK_PAGE="$REPO_ROOT/shell/modules/nexus/pages/NetworkPage.qml"
HOTSPOT_PAGE="$REPO_ROOT/shell/modules/nexus/pages/network/HotspotPage.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
POPOUT="$REPO_ROOT/shell/modules/bar/popouts/Network.qml"

# The state a hotspot toggle reads. Written out here so a rename on one side of
# the backend/adapter pair cannot pass unnoticed.
HOTSPOT_PROPERTIES=(
    "Q_PROPERTY(bool hotspotSupported READ hotspotSupported NOTIFY hotspotSupportedChanged)"
    "Q_PROPERTY(bool hotspotEnabled READ hotspotEnabled NOTIFY hotspotEnabledChanged)"
    "Q_PROPERTY(QString hotspotSsid READ hotspotSsid NOTIFY hotspotSsidChanged)"
)

test_the_backend_exposes_the_hotspot_state_and_actions() {
    local header
    header="$(cat "$NMQT_HPP")"

    local declaration
    for declaration in "${HOTSPOT_PROPERTIES[@]}"; do
        assert_contains "$header" "$declaration" "the header should declare the hotspot state"
    done

    local name
    for name in hotspotSupported hotspotEnabled hotspotSsid; do
        assert_contains "$header" "void ${name}Changed();" "the header should declare the ${name} signal"
    done

    assert_contains "$header" "Q_INVOKABLE void enableHotspot(const QString& ssid, const QString& password, QJSValue callback = {});" \
        "enableHotspot should take the name and the password"
    assert_contains "$header" "void disableHotspot(QJSValue callback = {});" \
        "disableHotspot should take only a callback"

    local impl
    impl="$(cat "$NMQT_CPP")"
    assert_contains "$impl" "void NmQt::enableHotspot(" "enableHotspot should be implemented"
    assert_contains "$impl" "void NmQt::disableHotspot(" "disableHotspot should be implemented"
}

test_the_hotspot_state_is_refreshed_with_the_devices() {
    # refreshDevices is the one place the device, active-connection and
    # NetworkManager-ready paths all go through, so a hotspot started elsewhere
    # (Plasma's applet, nmcli) still reaches the toggle.
    local body
    body="$(awk '/^void NmQt::refreshDevices\(\)/{flag=1} flag{print} flag && /^}$/{exit}' "$NMQT_CPP")"

    assert_contains "$body" "refreshHotspot();" "refreshDevices should re-read the hotspot state"
    assert_contains "$(cat "$NMQT_CPP")" "void NmQt::refreshHotspot()" "refreshHotspot should be implemented"
}

test_the_access_point_profile_has_one_id() {
    # Enabling twice has to update the profile it made the first time. A second
    # copy of the id would drift from the constant and leave a duplicate profile
    # beside it. The id is written once: as the constant.
    local count
    count="$(grep -c 'caelestia-hotspot' "$NMQT_CPP")"

    assert_eq "1" "$count" "the profile id should be written once, as the constant"
    assert_contains "$(cat "$NMQT_CPP")" 'constexpr QLatin1String hotspotConnectionId("caelestia-hotspot");' \
        "the profile id should be a named constant"
}

test_the_password_rule_agrees_across_the_layers() {
    # WPA cannot carry a shorter passphrase, so the backend refuses one and the
    # form refuses to save one. Two copies of the rule can drift apart silently,
    # which is why both sides are pinned here.
    assert_contains "$(cat "$NMQT_CPP")" "if (!password.isEmpty() && password.size() < 8)" \
        "the backend should refuse a password under eight characters"
    assert_contains "$(cat "$HOTSPOT_PAGE")" "validate: text => text.length === 0 || text.length >= 8" \
        "the form should refuse the same password"
}

test_the_adapter_delegates_every_hotspot_property() {
    local adapter
    adapter="$(cat "$NMCLI_QML")"

    assert_contains "$adapter" "readonly property bool hotspotSupported: NmQt.hotspotSupported" \
        "Nmcli should delegate hotspotSupported to the NmQt backend"
    assert_contains "$adapter" "readonly property bool hotspotEnabled: NmQt.hotspotEnabled" \
        "Nmcli should delegate hotspotEnabled to the NmQt backend"
    assert_contains "$adapter" "readonly property string hotspotSsid: NmQt.hotspotSsid" \
        "Nmcli should delegate hotspotSsid to the NmQt backend"

    assert_contains "$adapter" "NmQt.enableHotspot(ssid, password, callback);" "Nmcli should wrap enableHotspot"
    assert_contains "$adapter" "NmQt.disableHotspot(callback);" "Nmcli should wrap disableHotspot"
}

test_the_settings_are_global_keys() {
    local config
    config="$(cat "$SERVICES_HPP")"

    assert_contains "$config" "CONFIG_GLOBAL_PROPERTY(QString, hotspotSsid, QString())" \
        "the hotspot name should be a global setting"
    assert_contains "$config" "CONFIG_GLOBAL_PROPERTY(QString, hotspotPassword, QString())" \
        "the hotspot password should be a global setting"

    # A global property is only reachable through GlobalConfig. Reading it off
    # Config resolves to nothing, so the field would stay empty and the toggle
    # would start an access point with the wrong name.
    local readers
    readers="$(grep -rn 'Config\.services\.hotspot' "$REPO_ROOT/shell" --include='*.qml' \
        | grep -v 'GlobalConfig\.services\.hotspot' || true)"
    assert_eq "" "$readers" "every reader of the hotspot settings should use GlobalConfig"
}

test_the_quick_toggle_is_fully_wired() {
    local toggles
    toggles="$(cat "$TOGGLES_QML")"

    assert_contains "$toggles" 'roleValue: "hotspot"' "the quick toggles should have a hotspot delegate"
    assert_contains "$toggles" "checked: Nmcli.hotspotEnabled" "the delegate should follow the backend state"
    assert_contains "$toggles" "onClicked: {" "the delegate should act on the tap"
    assert_contains "$toggles" "Nmcli.toggleHotspot();" \
        "the delegate should go through the one path both quick surfaces share"
    assert_contains "$toggles" "internalChecked = Nmcli.hotspotEnabled;" \
        "and hand the light back to the backend, so a refused start does not leave it on"

    # An id that reaches the model with no delegate renders nothing, so the id
    # and the delegate are two halves of one contract.
    local id_entry
    id_entry="$(printf '%s\n' "$toggles" | grep -c 'id: "hotspot"')"
    assert_eq "1" "$id_entry" "the hotspot should be offered once, in the built-in list"

    assert_contains "$toggles" 'if (item.id === "hotspot") {' "the hotspot button should be gated on the hardware"
    assert_contains "$toggles" "return Nmcli.hotspotSupported;" "and gated on what the hardware reports"

    assert_contains "$(cat "$QUICK_TOGGLES_PAGE")" '{ id: "hotspot", label: qsTr("Hotspot") }' \
        "the hotspot should be switchable on the quick toggles page"
}

test_the_hotspot_page_is_the_eighth_network_page() {
    # Sub-pages are addressed by index, so a page inserted above the hotspot
    # would leave the row opening whatever page moved down instead.
    local pages
    pages="$(awk '/\/\/ Network$/{flag=1} flag{print} flag && /^            }$/{exit}' "$REGISTRY" \
        | grep -o '[A-Za-z]*Page {}' | awk '{ print $1 }')"

    assert_eq "8" "$(printf '%s\n' "$pages" | wc -l | tr -d ' ')" "the network stack should hold eight pages"
    assert_eq "HotspotPage" "$(printf '%s\n' "$pages" | sed -n '8p')" "the hotspot page should be the eighth"

    assert_contains "$(cat "$NETWORK_PAGE")" 'root.nState.openSubPage(7) // Hotspot sub-page' \
        "the Hotspot row should open the eighth page"
    assert_contains "$(cat "$REGISTRY")" "import qs.modules.nexus.pages.network" \
        "the registry should import the network pages"
}

test_the_bar_popout_shares_the_same_switch() {
    local popout
    popout="$(cat "$POPOUT")"

    assert_contains "$popout" 'label: qsTr("Hotspot")' "the network popout should offer the hotspot"
    assert_contains "$popout" "Binding on checked {" "the switch should read the backend, not the tap"
    assert_contains "$popout" "value: Nmcli.hotspotEnabled" "because the tap writes checked itself"
    assert_contains "$popout" "Nmcli.toggleHotspot();" \
        "the popout should use the same path as the utilities tile"
    assert_contains "$popout" "if (checked === Nmcli.hotspotEnabled)" \
        "and putting the backend state back should not start another attempt"
    assert_contains "$popout" 'visible: root.view === "wireless" && Nmcli.hotspotSupported' \
        "the popout row should stay off a device that cannot run one"
}

test_a_failed_start_is_reported() {
    # NM refuses an access point while the radio is busy, which is a normal thing
    # to run into, so the page has to show what NM said instead of going quiet.
    local page
    page="$(cat "$HOTSPOT_PAGE")"

    assert_contains "$page" "result?.error" "the page should surface the backend's error"

    # The switch reads the backend, not the tap, so a start that fails puts it
    # back. A plain binding would be destroyed by the switch's own click.
    assert_contains "$page" "Binding on checked {" "the switch should be driven by the backend"
    assert_contains "$page" "when: !root.busy" "and left alone while a change is in flight"
    assert_contains "$page" "if (root.busy || checked === Nmcli.hotspotEnabled)" \
        "applying the backend state should not start another attempt"
}

test_one_tap_does_not_share_an_open_network() {
    # With nothing configured, starting the hotspot would share an open network
    # with the machine's name on it: not what one tap on a bar toggle asked for.
    # The refusal points at the page, which is where an open network is a choice.
    local adapter
    adapter="$(cat "$NMCLI_QML")"

    assert_contains "$adapter" "function toggleHotspot(): void {" "the one-tap path should live in the adapter"
    assert_contains "$adapter" 'GlobalConfig.services.hotspotSsid.length === 0 && GlobalConfig.services.hotspotPassword.length === 0' \
        "an unconfigured hotspot should not start"
    assert_contains "$adapter" "Toaster.toast(qsTr(\"Hotspot\"), qsTr(\"Give it a name and a password in Settings > Network > Hotspot\")" \
        "and the refusal should say where to set it up"
    assert_contains "$adapter" "NmQt.enableHotspot(GlobalConfig.services.hotspotSsid, GlobalConfig.services.hotspotPassword, reportHotspotFailure)" \
        "the one-tap path should start it with the settings the page edits"
    assert_contains "$adapter" "Toaster.toast(qsTr(\"Hotspot\"), result.error ||" \
        "a failed start should be toasted, not silent"
}

run_tests
