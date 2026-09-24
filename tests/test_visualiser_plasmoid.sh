#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$REPO_ROOT/src/kde/plasmoids/org.caelestia.visualiser"
METADATA="$PKG_DIR/metadata.json"
MAIN_QML="$PKG_DIR/contents/ui/main.qml"
CONTENT_QML="$PKG_DIR/contents/ui/VisualiserContent.qml"
MAIN_XML="$PKG_DIR/contents/config/main.xml"
CONFIG_QML="$PKG_DIR/contents/config/config.qml"
BUILD_SCRIPT="$REPO_ROOT/scripts/08-build-shell.sh"
MAKEFILE="$REPO_ROOT/Makefile"
RUN_TESTS="$REPO_ROOT/tests/run-tests.sh"

have_python() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    skip_test "python3 not installed"
    return 1
}

test_package_files_exist() {
    assert_is_dir "$PKG_DIR"
    assert_file_exists "$METADATA"
    assert_file_exists "$MAIN_QML"
    assert_file_exists "$CONTENT_QML"
    assert_file_exists "$MAIN_XML"
    assert_file_exists "$CONFIG_QML"
}

test_metadata_declares_a_plasma_applet() {
    have_python || return 0

    python3 - "$METADATA" <<'PYEOF' || fail "metadata.json is not valid Plasma applet metadata"
import json
import sys


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


meta = json.load(open(sys.argv[1]))
if meta.get("KPackageStructure") != "Plasma/Applet":
    die(f"KPackageStructure is {meta.get('KPackageStructure')!r}, expected 'Plasma/Applet'")

plugin = meta.get("KPlugin", {})
expected = {
    "Id": "org.caelestia.visualiser",
    "Category": "Multimedia",
    "License": "GPL-3.0-or-later",
}
for key, value in expected.items():
    if plugin.get(key) != value:
        die(f"KPlugin.{key} is {plugin.get(key)!r}, expected {value!r}")

for key in ("Name", "Description", "Version"):
    if not plugin.get(key):
        die(f"KPlugin.{key} is missing or empty")

if not plugin.get("Authors"):
    die("KPlugin.Authors is missing or empty")
if "Plasma/Applet" not in plugin.get("ServiceTypes", []):
    die(f"KPlugin.ServiceTypes is {plugin.get('ServiceTypes')!r}, expected to contain 'Plasma/Applet'")
for key in ("Website", "BugReportUrl"):
    if not str(plugin.get(key, "")).startswith("https://github.com/"):
        die(f"KPlugin.{key} is {plugin.get(key)!r}, expected the fork's repository URL")
PYEOF
}

test_config_keys_agree_across_schema_dialog_and_applet() {
    have_python || return 0

    python3 - "$MAIN_XML" "$CONFIG_QML" "$MAIN_QML" <<'PYEOF' || fail "applet configuration keys disagree between main.xml, config.qml and main.qml"
import re
import sys
import xml.etree.ElementTree as ET


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


xml_entries = {}


def child_text(entry, name):
    for child in entry:
        if child.tag == name or child.tag.endswith("}" + name):
            return child.text
    return None


for entry in ET.parse(sys.argv[1]).getroot().iter():
    if entry.tag.endswith("}entry") or entry.tag == "entry":
        xml_entries[entry.get("name")] = child_text(entry, "default")

config_qml = open(sys.argv[2]).read()
cfg_keys = set(re.findall(r"cfg_(\w+)", config_qml))

main_qml = open(sys.argv[3]).read()
read_keys = set(re.findall(r"Plasmoid\.configuration\.(\w+)", main_qml))

if cfg_keys != set(xml_entries):
    die(f"config.qml cfg_ keys {sorted(cfg_keys)} != main.xml entries {sorted(xml_entries)}")
if read_keys != set(xml_entries):
    die(f"main.qml reads {sorted(read_keys)} but main.xml declares {sorted(xml_entries)}")

defaults = {
    "barCount": "60",
    "animationDuration": "200",
    "rounding": "1.0",
    "spacing": "1.0",
    "pauseWhenHidden": "true",
    "showUnavailableMessage": "true",
}
for name, default in defaults.items():
    if xml_entries.get(name) != default:
        die(f"{name} default is {xml_entries.get(name)!r}, expected {default!r} (mirrors the quickshell visualiser)")
PYEOF
}

test_the_visualiser_reuses_the_caelestia_plugin() {
    local content
    content="$(cat "$CONTENT_QML")"

    assert_contains "$content" "import Caelestia.Services" "the plasmoid must drive the audio through the plugin services"
    assert_contains "$content" "import Caelestia.Components" "and render with the plugin's VisualiserBars"
    assert_contains "$content" "CavaProvider {" "CavaProvider must be instantiated"
    assert_contains "$content" "ServiceRef {" "a ServiceRef must own the provider lifetime"
    assert_contains "$content" "VisualiserBars {" "the bars must come from the plugin renderer"
    assert_not_contains "$content" "Quickshell" "the plasmoid must not depend on the quickshell host"
}

test_pausing_tears_down_the_audio_pipeline() {
    local main content
    main="$(cat "$MAIN_QML")"
    content="$(cat "$CONTENT_QML")"

    assert_contains "$main" "Plasmoid.configuration.pauseWhenHidden" "pause-when-hidden must be user-configurable"
    assert_contains "$main" "!pauseWhenHidden || (root.visible && !Plasmoid.userConfiguring)" \
        "the applet must stop while it is not visible or the config dialog is open"
    assert_contains "$content" "service: root.running ? cavaProvider : null" \
        "pausing must drop the CavaProvider reference, stopping the analysis timer and the PipeWire stream"
    assert_contains "$content" "values: root.running ? cavaProvider.values : []" \
        "the bars must settle to nothing while paused"
    assert_contains "$content" "running: root.running && !bars.settled" \
        "the frame loop must stop while paused or settled"
}

test_the_applet_degrades_without_the_plugin() {
    local main content
    main="$(cat "$MAIN_QML")"
    content="$(cat "$CONTENT_QML")"

    assert_not_contains "$main" "import Caelestia" "the applet root must load without the Caelestia plugin"
    assert_contains "$main" 'source: "VisualiserContent.qml"' "the plugin-dependent UI must live behind a Loader"
    assert_contains "$main" "status === Loader.Error" "a missing plugin must surface as a load error"
    assert_contains "$main" "Plasmoid.configuration.showUnavailableMessage" "the fallback message must be configurable"
    assert_contains "$content" "PlasmaCore.Theme" "the fallback colours must come from the Plasma theme"
}

test_colours_come_from_the_theme_and_the_caelestia_scheme() {
    local main content
    main="$(cat "$MAIN_QML")"
    content="$(cat "$CONTENT_QML")"

    assert_contains "$content" "PlasmaCore.Theme.highlightColor" "the bars must fall back to the Plasma theme accent"
    assert_contains "$content" "cat ~/.local/state/caelestia/scheme.json" "and follow the Caelestia scheme state like the lock screen does"
    assert_contains "$content" "colours.primary" "the primary bar colour must be the Caelestia M3 primary"
    assert_contains "$content" "colours.inversePrimary" "the secondary bar colour must be the Caelestia M3 inverse primary"
    if printf '%s' "$main$content" | grep -qE '#[0-9a-fA-F]{6}'; then
        fail "plasmoid QML must not hardcode colours"
    fi
}

test_the_installer_deploys_the_plasmoid_like_the_lockscreen() {
    local script
    script="$(cat "$BUILD_SCRIPT")"

    assert_eq "1" "$(printf '%s\n' "$script" | grep -c '^install_visualiser_plasmoid() {')" \
        "the installer should define the plasmoid deploy once"
    assert_contains "$script" 'src/kde/plasmoids/org.caelestia.visualiser' "the source package must be named"
    assert_contains "$script" '.local/share/plasma/plasmoids/org.caelestia.visualiser' "the destination must be the user plasmoid directory"
    assert_contains "$script" 'atomic_replace_tree "$src" "$dest" metadata.json' \
        "the deploy must be atomic and refuse a package without metadata"
    assert_contains "$script" 'install_visualiser_plasmoid || true' \
        "and it must run in the deploy step, non-fatally like the lock screen"
    assert_contains "$script" 'APPLY_VISUALISER_PLASMOID' "the deploy must be switchable like APPLY_LOCKSCREEN"
}

test_the_qml_syntax_gate_covers_the_plasmoid() {
    local makefile
    makefile="$(cat "$MAKEFILE")"

    assert_contains "$makefile" 'PLASMOIDS_DIR := src/kde/plasmoids' "the plasmoid sources should have a Makefile variable"
    assert_contains "$makefile" '--source-root $(PLASMOIDS_DIR)' "make check-qml must sweep the plasmoid sources"

    if ! command -v python3 >/dev/null 2>&1; then
        skip_test "python3 not installed"
        return 0
    fi
    python3 "$REPO_ROOT/.github/scripts/check_qml_syntax.py" --source-root "$PKG_DIR" \
        || fail "the plasmoid QML must pass the repo's structural syntax check"
}

test_the_suite_auto_discovers_the_plasmoid_test() {
    assert_contains "$(cat "$RUN_TESTS")" 'test_*.sh' \
        "run-tests.sh discovers every test_*.sh file by glob, so this file runs with the suite"
}

run_tests
