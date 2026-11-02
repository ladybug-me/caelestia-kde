#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIFI_JS="$REPO_ROOT/shell/services/wifi.js"
NMCLI="$REPO_ROOT/shell/services/Nmcli.qml"
ICONS="$REPO_ROOT/shell/utils/Icons.qml"
STATUS="$REPO_ROOT/shell/modules/bar/components/StatusIcons.qml"
DETAIL="$REPO_ROOT/shell/modules/nexus/pages/network/NetworkDetailPage.qml"
SAVED="$REPO_ROOT/shell/modules/nexus/pages/network/SavedNetworksPage.qml"
SIGNAL="$REPO_ROOT/shell/services/WifiSignal.qml"
NMQT="$REPO_ROOT/shell/plugin/src/Caelestia/Services/NmQt.cpp"

# Reading the driver is pure, so it is executed rather than grepped: each script below
# runs against wifi.js with node's assert.
check_wifi() { check_js "$1" "$WIFI_JS" Wifi "$2"; }

# NetworkManager publishes the strength of the associated access point from its last
# scan of that BSS. On 6 GHz that read -45 dBm as 73 %, which is a three-bar icon next to
# the router; the driver reports the link as it is.
test_the_link_signal_comes_out_of_the_driver() {
    check_wifi "iw link has to give up its dBm" '
assert.strictEqual(Wifi.signalOf("\tSSID: SUNSET\n\tfreq: 6135.0\n\tsignal: -45 dBm\n"), -45, "a plain link line");
assert.strictEqual(Wifi.signalOf("\tSSID: X\n\tsignal: -67.00 dBm\n"), -67, "the dBm is not always whole");
assert.strictEqual(Wifi.signalOf("MLD a2:91:ca:9e:ce:18 stats:\n\tRX: 1\n\tsignal: -46 dBm\n"), -46, "and MLO prints one aggregate line");
assert.strictEqual(Wifi.signalOf("Not connected.\n"), null, "no link is not a signal");
assert.strictEqual(Wifi.signalOf(""), null, "nor is no output at all");
assert.strictEqual(Wifi.signalOf(null), null, "and a missing field does not throw");
'
}

test_the_reading_is_one_number_with_one_unknown() {
    check_wifi "a caller should not have to turn a null into a zero" '
assert.strictEqual(Wifi.qualityFromLink("\tSSID: SUNSET\n\tsignal: -45 dBm\n"), 100, "a full reading");
assert.strictEqual(Wifi.qualityFromLink("\tSSID: X\n\tsignal: -68 dBm\n"), 64, "and a middling one");
assert.strictEqual(Wifi.qualityFromLink("Not connected.\n"), -1, "no link is unknown, not zero");
assert.strictEqual(Wifi.qualityFromLink(""), -1, "nor is empty output a dead link");
'
}

test_dbm_maps_onto_the_scale_the_icons_use() {
    check_wifi "the icon buckets are percentages, so dBm has to become one" '
assert.strictEqual(Wifi.qualityOf(-45), 100, "next to the router is a full signal");
assert.strictEqual(Wifi.qualityOf(-50), 100, "as is anything better than -50 dBm");
assert.strictEqual(Wifi.qualityOf(-30), 100, "which clamps, rather than overflowing");
assert.strictEqual(Wifi.qualityOf(-60), 80, "ten dB down is four fifths");
assert.strictEqual(Wifi.qualityOf(-70), 60, "and the rest of the scale is linear");
assert.strictEqual(Wifi.qualityOf(-75), 50, "half way");
assert.strictEqual(Wifi.qualityOf(-100), 0, "nothing at all");
assert.strictEqual(Wifi.qualityOf(-120), 0, "and it clamps at the bottom too");
assert.strictEqual(Wifi.qualityOf(null), null, "no reading is not a reading");
'
}

# A full signal has to be able to reach the full icon: the top bucket starts at 80, and
# the scan snapshot never got there on a 6 GHz link.
test_a_full_signal_reaches_the_full_icon() {
    assert_file_contains "$ICONS" 'if (strength >= 80)' "the top bucket is still 80 and up"
    assert_file_contains "$STATUS" 'Icons.getNetworkIcon(WifiSignal.strength)' \
        "and the bar asks for the link's strength, not NetworkManager's snapshot"
}

test_the_link_reading_has_its_own_owner() {
    assert_file_contains "$SIGNAL" 'readonly property int strength: root.reading >= 0 ? root.reading : (Nmcli.active?.strength ?? 0)' \
        "the live link wins, and NetworkManager answers when the driver cannot"
    assert_file_contains "$SIGNAL" 'property int reading: -1' \
        "with no-reading kept apart from no-signal"
    assert_file_contains "$SIGNAL" 'command: ["iw", "dev", root.interfaceName, "link"]' \
        "the reading comes from the driver"
    assert_file_contains "$SIGNAL" 'running: root.watchable' \
        "and is only taken while there is a link to read"
    assert_file_contains "$SIGNAL" 'root.reading = -1;' \
        "a dropped link forgets its last reading"
    assert_file_contains "$NMQT" 'details[QStringLiteral("interface")] = wifiDev->interfaceName();' \
        "the interface to ask about comes from the service that owns the device"
    assert_file_not_contains "$NMCLI" 'iw", "dev"' \
        "and the NetworkManager adapter stays an adapter"
}

test_the_whole_shell_shows_one_signal() {
    assert_file_contains "$STATUS" 'Icons.getNetworkIcon(WifiSignal.strength)' \
        "the bar draws the link's strength"
    assert_file_contains "$DETAIL" 'qsTr("%1%").arg(root.isActive ? WifiSignal.strength : root.ap.strength)' \
        "and the connection page prints the same number, rather than NetworkManager's snapshot"
    assert_file_contains "$SAVED" 'Icons.getNetworkIcon(saved.isActive ? WifiSignal.strength : saved.ap.strength' \
        "as does the saved-network row when it is the live link"
}

run_tests
