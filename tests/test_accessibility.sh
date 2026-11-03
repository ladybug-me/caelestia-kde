#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/Accessibility.qml"
CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/appearanceconfig.hpp"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/services/AccessibilityPage.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
DICTIONARY="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"

test_shell_text_follows_kdes_font_size() {
    local config service
    config="$(cat "$CONFIG")"
    service="$(cat "$SERVICE")"

    assert_contains "$config" 'CONFIG_PROPERTY(bool, followSystemScale, true)' \
        "following KDE's text size has to be a setting"
    # The file is watched, not polled: spawning kreadconfig6 every 30s to learn a value
    # that only changes when the user changes it is work for nothing.
    assert_contains "$service" 'watchChanges: true' "kdeglobals must be watched"
    assert_contains "$service" 'onFileChanged: reload()' "and re-read when KDE writes it"
    assert_not_contains "$service" 'kreadconfig6' "the font size must not be polled through a process"
    # kdeglobals stores "Family,11,-1,5,…": the point size is the second field.
    assert_contains "$service" 'const size = parseInt(line.substring(5).split(",")[1] ?? "", 10)' \
        "the size has to be taken from the font entry"
    assert_contains "$service" 'const scale = points / root.basePointSize' \
        "an 11 pt default has to become 110%, not a delta"
    assert_contains "$service" 'points = isNaN(size) || size <= 0 ? 0 : size' \
        "an absent key means KDE's default, not a zero scale"
    assert_contains "$service" 'if (!root.followSystem)' "the setting has to be honoured"
    assert_contains "$service" 'Math.abs(current - root.systemScale) < 0.005' \
        "the config must not be rewritten on every re-read"
}

test_visual_helpers_drive_kwin_effects() {
    local service page
    service="$(cat "$SERVICE")"
    page="$(cat "$PAGE")"

    # KWin reports the whole list in one call; asking per effect meant matching a
    # positional reply, which is the kind of contract that silently breaks.
    assert_contains "$service" '["qdbus6", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects.loadedEffects"]' \
        "the loaded effects must be read in one query"
    assert_not_contains "$service" 'Effects.isEffectLoaded' "and not one process per effect"
    assert_contains "$service" 'root.loadedEffects.indexOf(name) >= 0' "membership decides the switch"
    assert_contains "$service" 'org.kde.kwin.Effects.${method}' "toggling must go through KWin's interface"
    assert_contains "$service" 'effectsReload.restart()' "and the list is re-read after the call"

    # The page is data: one row per effect, so a fourth effect is a line, not a copy.
    assert_contains "$page" 'readonly property var effectRows' "the effects belong in one list"
    assert_contains "$page" 'checked: Accessibility.isEffectLoaded(modelData.id)' \
        "each row asks whether KWin has it loaded"
    assert_contains "$page" 'onToggled: Accessibility.setEffect(modelData.id, checked)'
    assert_contains "$page" 'qsTr("Reduce motion")' "reduced motion belongs on this page"
    assert_contains "$page" 'GlobalConfig.appearance.anim.enabled = !checked' \
        "reduced motion is the inverse of the animations switch"
}

test_screen_reader_is_offered_when_present() {
    local service page
    service="$(cat "$SERVICE")"
    page="$(cat "$PAGE")"

    assert_contains "$service" 'command -v orca' "availability has to be detected, not assumed"
    assert_contains "$service" 'Quickshell.execDetached(["orca"])' "starting it must not block the shell"
    assert_contains "$page" 'enabled: Accessibility.screenReaderInstalled' \
        "the button must not be offered when it cannot work"
}

test_accessibility_page_is_a_top_level_page() {
    local page registry dictionary
    page="$(cat "$PAGE")"
    registry="$(cat "$REGISTRY")"
    dictionary="$(cat "$DICTIONARY")"

    assert_contains "$page" 'title: qsTr("Accessibility")' "the page needs its own title"
    assert_contains "$registry" 'Component { AccessibilityPage {} }' "the page must be registered"
    assert_contains "$dictionary" '"accessibility":' "and listed in the settings index"
    assert_not_contains "$page" 'isSubPage: true' "it is a top level page, not a sub page"
}

run_tests
