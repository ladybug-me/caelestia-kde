#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/Displays.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/DisplayPage.qml"
MODES="$REPO_ROOT/shell/modules/nexus/pages/display/DisplayModesPage.qml"
DICTIONARY="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
STATE="$REPO_ROOT/shell/modules/nexus/NexusState.qml"

test_kscreen_is_the_only_owner_of_the_layout() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" 'command: ["kscreen-doctor", "-j"]' \
        "the shell reads the layout from KScreen"
    assert_contains "$service" 'writeProcess.command = ["kscreen-doctor", ...settings]' \
        "and asks KScreen to change it, instead of keeping a second copy"
    assert_contains "$service" 'root.layoutApplied();' \
        "every change has to be read back and announced, so the page and the backlight both catch up"
    assert_contains "$service" 'root.outputs = []' "an unreadable layout must not look like an empty one"
    assert_contains "$service" 'root.available = false' "and has to be reported"
}

test_the_two_reads_do_not_wait_for_each_other() {
    local service
    service="$(cat "$SERVICE")"

    # The layout and the panels behind it are separate questions; asking them in series
    # means the EDID probe is blocked behind kscreen-doctor for no reason.
    assert_not_contains "$service" 'readPanels' "the probe must not be called from the layout read"
    assert_contains "$service" 'panelsProcess.running = true;' "it runs on its own"
    assert_contains "$service" 'command: ["python3", Quickshell.shellPath("scripts/panel_capabilities.py")]' \
        "and finds the outputs itself, so it needs no arguments"
}

test_output_settings_map_onto_the_kscreen_cli() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" '`output.${name}.${on ? "enable" : "disable"}`' "enabling an output"
    assert_contains "$service" '`output.${name}.mode.${modeId}`' "setting a mode"
    assert_contains "$service" '`output.${name}.scale.${scale}`' "setting the scale"
    assert_contains "$service" '`output.${name}.rotation.${root.rotationName(rotation)}`' "setting the rotation"
    assert_contains "$service" '`output.${name}.hdr.${on ? "enable" : "disable"}`' "setting HDR"
    assert_contains "$service" 'readonly property var rotations: ({ 1: "none", 2: "left", 4: "inverted", 8: "right" })' \
        "KScreen reports the rotation as a power of two, and the names live in one place"
    assert_contains "$service" 'function setRotation(name: string, rotation: int): void' \
        "so the page passes the value it read, not a spelling of it"
    assert_contains "$service" 'function modesFor(output: var): var' \
        "modes are offered largest and fastest first"
}

test_the_page_is_driven_by_the_service() {
    local page
    page="$(cat "$PAGE")"

    assert_contains "$page" 'model: Displays.connected' "one section per connected screen"
    assert_contains "$page" 'readonly property var output: outputSection.modelData' \
        "the section names its screen once instead of repeating modelData"
    assert_contains "$page" 'Displays.setEnabled(outputSection.output.name, checked)' "enabled switch"
    assert_contains "$page" 'Displays.setScale(outputSection.output.name, Number(item.value))' "scale menu"
    assert_contains "$page" 'Displays.setRotation(outputSection.output.name, item.value)' "rotation menu"
    assert_contains "$page" 'Displays.setHdr(outputSection.output.name, checked)' "HDR switch"
    assert_contains "$page" 'enabled: Displays.enabled.length > 1 || !outputSection.output.enabled' \
        "the last enabled screen cannot be switched off"
    assert_contains "$page" 'fallbackText:' "a scale or rotation outside the menu still shows the truth"
    assert_contains "$page" 'Launch.kcm("kcm_touchpad")' \
        "input settings stay with the KCM that owns them"
    assert_contains "$page" 'Launch.kcm("kcm_keyboard")' "and so does the keyboard"
}

test_the_mode_list_marks_and_applies() {
    local modes
    modes="$(cat "$MODES")"

    assert_contains "$modes" 'model: root.modes' "every mode of the selected output"
    assert_contains "$modes" 'function isCurrent(mode: var): bool' "the current one has to be recognisable"
    assert_contains "$modes" 'delegate: RowButton {' "the rows are the row the rest of Nexus already uses"
    assert_contains "$modes" 'Displays.setMode(root.output.name, String(modeRow.modelData.id))' "applying a mode"
    assert_contains "$modes" 'root.nState.closeSubPage()' "and returning to the screen it came from"
}

test_the_page_is_registered_next_to_its_neighbours() {
    local dictionary registry state
    dictionary="$(cat "$DICTIONARY")"
    registry="$(cat "$REGISTRY")"
    state="$(cat "$STATE")"

    assert_contains "$dictionary" 'key: "displays"' "the page has to exist in the dictionary"
    assert_contains "$dictionary" 'category: "connectivity"' "and sit with the hardware pages"
    assert_contains "$dictionary" 'function pageIdxFor(key: string): int' \
        "page positions are looked up, never remembered"
    assert_contains "$registry" 'Component { DisplayPage {} }' "the page has to be registered"
    assert_contains "$registry" 'Component { DisplayModesPage {} }' "with its mode list"
    assert_contains "$state" 'property string selectedOutput' "the mode list needs to know which screen it edits"

    local dictionary_bluetooth dictionary_displays dictionary_audio
    dictionary_bluetooth="$(grep -n '"bluetooth":' "$DICTIONARY" | head -n1 | cut -d: -f1)"
    dictionary_displays="$(grep -n '"displays":' "$DICTIONARY" | head -n1 | cut -d: -f1)"
    dictionary_audio="$(grep -n '"audio":' "$DICTIONARY" | head -n1 | cut -d: -f1)"
    assert_eq "yes" "$([ "$dictionary_bluetooth" -lt "$dictionary_displays" ] && [ "$dictionary_displays" -lt "$dictionary_audio" ] && echo yes)" \
        "displays belong between the connected devices and audio"

    # The registry is positional: its Nth stack is the Nth page of the dictionary.
    local registry_bluetooth registry_displays registry_audio
    registry_bluetooth="$(grep -n 'key: "bluetoothPairing"' "$REGISTRY" | cut -d: -f1)"
    registry_displays="$(grep -n 'key: "displays"' "$REGISTRY" | cut -d: -f1)"
    registry_audio="$(grep -n 'key: "audio"' "$REGISTRY" | cut -d: -f1)"
    assert_eq "yes" "$([ "$registry_bluetooth" -lt "$registry_displays" ] && [ "$registry_displays" -lt "$registry_audio" ] && echo yes)" \
        "and the registry has to keep that order"
}

SCRIPT="$REPO_ROOT/shell/scripts/panel_capabilities.py"
BRIGHTNESS="$REPO_ROOT/shell/services/Brightness.qml"
PYTHON="$(command -v python3 || command -v python)"

test_hdr_is_only_offered_for_a_panel_that_claims_it() {
    local service page
    service="$(cat "$SERVICE")"
    page="$(cat "$PAGE")"

    assert_contains "$service" 'function supportsHdr(output: var): bool' \
        "HDR must not be offered on a screen that cannot show it"
    assert_contains "$service" 'root.panels[output?.name]?.hdr === true' \
        "and only a panel that says so counts"
    assert_contains "$service" 'Quickshell.shellPath("scripts/panel_capabilities.py")' \
        "the claim comes from the panel's own EDID, not from KScreen"
    assert_contains "$page" 'visible: Displays.supportsHdr(outputSection.output)' \
        "so the switch is absent when the panel is silent"
    assert_contains "$page" 'last: !Displays.supportsHdr(outputSection.output)' \
        "and the row above it keeps the rounded corner"
}

test_hdr_takes_the_wide_gamut_with_it() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" 'output.${name}.hdr.${on ? "enable" : "disable"}' "HDR is set"
    assert_contains "$service" 'output.${name}.wcg.${on ? "enable" : "disable"}' \
        "together with the wide colour gamut, the way KDE's own switch does it"
}

test_brightness_survives_a_layout_change() {
    local brightness
    brightness="$(cat "$BRIGHTNESS")"

    assert_contains "$brightness" 'function reassertBrightness(): void' \
        "a layout change must not throw away the brightness the user chose"
    assert_contains "$brightness" 'target: Displays' "the trigger is the display service"
    assert_contains "$brightness" 'function onLayoutApplied(): void' "announcing an applied layout"
    assert_contains "$brightness" 'if (monitor && !monitor.reasserting && monitor.brightness !== value)' \
        "KWin resetting the panel must not be mistaken for the user dimming it"
    assert_contains "$brightness" 'readonly property real reassertNudge: 0.01' \
        "the nudge is a named step, not a number buried in the timer"
    assert_contains "$brightness" 'const value = settling ? target : (target >= 1 ? target - monitor.reassertNudge : target + monitor.reassertNudge)' \
        "KWin ignores a write it already holds, so the panel is nudged off the value first"
    assert_contains "$brightness" 'monitor.writeBrightness(value)' \
        "and the brightness written back to the panel"
}

test_the_edid_decides_what_the_panel_can_show() {
    if [ -z "$PYTHON" ]; then
        skip_test "python3 not installed"
        return
    fi

    local dir hdr sdr
    dir="$("$PYTHON" - <<'PY'
import tempfile

print(tempfile.mkdtemp())
PY
)"
    "$PYTHON" - "$dir" <<'PY'
import sys
from pathlib import Path

out = Path(sys.argv[1])


def edid(eotf):
    base = bytearray(128)
    base[0:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
    base[126] = 1  # one CTA extension
    # An extended-tag block carrying the HDR Static Metadata payload and its EOTF byte.
    blocks = bytes([0xE6, 0x06, eotf, 0x01, 0x7A, 0x7A, 0x52])
    cta = bytearray(128)
    cta[0] = 0x02
    cta[1] = 0x03
    cta[2] = 4 + len(blocks)
    cta[4:4 + len(blocks)] = blocks
    return bytes(base) + bytes(cta)


(out / "hdr.edid").write_bytes(edid(0x05))  # SDR and PQ
(out / "sdr.edid").write_bytes(edid(0x01))  # SDR only
PY

    hdr="$("$PYTHON" "$SCRIPT" --file "$dir/hdr.edid")"
    sdr="$("$PYTHON" "$SCRIPT" --file "$dir/sdr.edid")"

    assert_contains "$hdr" '"hdr": true' "a panel offering the PQ transfer function can do HDR"
    assert_contains "$sdr" '"hdr": false' "a panel describing only the SDR range cannot"

    rm -rf "$dir"
}
run_tests
