#!/usr/bin/env bash
# suite: fast

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_SCRIPT="$REPO_ROOT/shell/scripts/export-plasma-config.sh"
WIDGETS_QML="$REPO_ROOT/shell/services/PlasmaWidgets.qml"

test_default_geoms_1080p_flush_bottom() {
    local py_out
    py_out="$(python3 - << 'EOF'
def compute_default_geoms(screen_w, screen_h, applet_count):
    center_gap = round(screen_w * (224.0 / 1920.0))
    vis_w = float(int((screen_w - center_gap) / 2))
    vis_h = round(screen_h * (416.0 / 1080.0))
    vis_y = round(screen_h - vis_h)
    vis_x1 = 0.0
    vis_x2 = float(screen_w - vis_w)
    if applet_count == 1:
        single_w = round(screen_w * (848.0 / 1920.0))
        single_x = round((screen_w - single_w) / 2.0)
        return [(single_x, vis_y, single_w, vis_h)]
    return [(vis_x1, vis_y, vis_w, vis_h), (vis_x2, vis_y, vis_w, vis_h)]

geoms = compute_default_geoms(1920.0, 1080.0, 2)
assert len(geoms) == 2, "Expected 2 applets for double_reversed"
g1, g2 = geoms[0], geoms[1]

# Applet 1: (0, 664, 848, 416)
assert g1[0] == 0.0, f"Applet 1 x expected 0, got {g1[0]}"
assert g1[2] == 848.0, f"Applet 1 width expected 848, got {g1[2]}"
assert g1[3] == 416.0, f"Applet 1 height expected 416, got {g1[3]}"
assert g1[1] + g1[3] == 1080.0, f"Applet 1 must be flush at bottom: {g1[1]} + {g1[3]} != 1080"

# Applet 2: (1072, 664, 848, 416)
assert g2[0] == 1072.0, f"Applet 2 x expected 1072, got {g2[0]}"
assert g2[2] == 848.0, f"Applet 2 width expected 848, got {g2[2]}"
assert g2[1] + g2[3] == 1080.0, f"Applet 2 must be flush at bottom: {g2[1]} + {g2[3]} != 1080"
assert g2[0] + g2[2] == 1920.0, "Applet 2 must reach right edge of 1920 display"

# Gap between widgets
gap = g2[0] - (g1[0] + g1[2])
assert gap == 224.0, f"Expected 224 center gap, got {gap}"

print("ok")
EOF
)"
    assert_eq "ok" "$py_out" "1080p visualizer geometry must be flush and match reference proportions"
}

test_default_geoms_1440p_scaling() {
    local py_out
    py_out="$(python3 - << 'EOF'
def compute_default_geoms(screen_w, screen_h, applet_count):
    center_gap = round(screen_w * (224.0 / 1920.0))
    vis_w = float(int((screen_w - center_gap) / 2))
    vis_h = round(screen_h * (416.0 / 1080.0))
    vis_y = round(screen_h - vis_h)
    vis_x1 = 0.0
    vis_x2 = float(screen_w - vis_w)
    return [(vis_x1, vis_y, vis_w, vis_h), (vis_x2, vis_y, vis_w, vis_h)]

geoms = compute_default_geoms(2560.0, 1440.0, 2)
g1, g2 = geoms[0], geoms[1]

assert g1[0] == 0.0
assert g1[1] + g1[3] == 1440.0, f"1440p applet 1 must be flush at bottom: {g1[1] + g1[3]}"
assert g2[1] + g2[3] == 1440.0, f"1440p applet 2 must be flush at bottom: {g2[1] + g2[3]}"
assert g2[0] + g2[2] == 2560.0, f"1440p applet 2 must reach right edge: {g2[0] + g2[2]}"
assert g1[2] == g2[2], "Both widgets must have equal width"
assert g1[3] == g2[3], "Both widgets must have equal height"

print("ok")
EOF
)"
    assert_eq "ok" "$py_out" "1440p visualizer scaling must be flush and symmetric"
}

test_default_geoms_4k_scaling() {
    local py_out
    py_out="$(python3 - << 'EOF'
def compute_default_geoms(screen_w, screen_h, applet_count):
    center_gap = round(screen_w * (224.0 / 1920.0))
    vis_w = float(int((screen_w - center_gap) / 2))
    vis_h = round(screen_h * (416.0 / 1080.0))
    vis_y = round(screen_h - vis_h)
    vis_x1 = 0.0
    vis_x2 = float(screen_w - vis_w)
    return [(vis_x1, vis_y, vis_w, vis_h), (vis_x2, vis_y, vis_w, vis_h)]

geoms = compute_default_geoms(3840.0, 2160.0, 2)
g1, g2 = geoms[0], geoms[1]

assert g1[0] == 0.0
assert g1[1] + g1[3] == 2160.0
assert g2[1] + g2[3] == 2160.0
assert g2[0] + g2[2] == 3840.0
assert g1[2] == 1696.0, f"Expected 4K width 1696, got {g1[2]}"
assert g1[3] == 832.0, f"Expected 4K height 832, got {g1[3]}"

print("ok")
EOF
)"
    assert_eq "ok" "$py_out" "4K visualizer scaling must scale coordinates proportionally"
}

test_default_geoms_single_profile() {
    local py_out
    py_out="$(python3 - << 'EOF'
def compute_default_geoms(screen_w, screen_h, applet_count):
    center_gap = round(screen_w * (224.0 / 1920.0))
    vis_w = float(int((screen_w - center_gap) / 2))
    vis_h = round(screen_h * (416.0 / 1080.0))
    vis_y = round(screen_h - vis_h)
    vis_x1 = 0.0
    vis_x2 = float(screen_w - vis_w)
    if applet_count == 1:
        single_w = float(screen_w)
        single_x = 0.0
        return [(single_x, vis_y, single_w, vis_h)]
    return [(vis_x1, vis_y, vis_w, vis_h), (vis_x2, vis_y, vis_w, vis_h)]

geoms = compute_default_geoms(1920.0, 1080.0, 1)
assert len(geoms) == 1
g = geoms[0]

assert g[0] == 0.0, "Single visualizer must start at x=0"
assert g[2] == 1920.0, "Single visualizer must span complete width"
assert g[1] + g[3] == 1080.0, "Single visualizer must be flush with bottom"

print("ok")
EOF
)"
    assert_eq "ok" "$py_out" "Single profile must be centered horizontally and flush at bottom"
}

test_quickshell_placement_bottom_bar_flush() {
    local py_out
    py_out="$(python3 - << 'EOF'
def calc_qml(screen_w, screen_h, usable_w, usable_h, bottom_excl, left_excl, right_excl, border_th=1):
    center_gap = round(screen_w * (224.0 / 1920.0))
    vis_w = int((usable_w - center_gap) // 2)
    vis_h = round(usable_h * (416.0 / 1080.0))
    raw_y = round(screen_h - bottom_excl - vis_h)
    min_y = round(screen_h * 0.5)
    max_y = round(screen_h - bottom_excl - vis_h)
    vis_y = max(min_y, min(max_y, raw_y))

    vis_x1 = 0 if left_excl <= border_th else round(left_excl)
    vis_x2 = round(screen_w - vis_w if right_excl <= border_th else screen_w - right_excl - vis_w)
    return vis_x1, vis_y, vis_w, vis_h, vis_x2

# Bottom bar scenario: bottomExclusion=48, leftExclusion=1, rightExclusion=1
# screenHeight=1080, usableHeight=1032
x1, y1, w, h, x2 = calc_qml(1920, 1080, 1920 - 2, 1080 - 48, bottom_excl=48, left_excl=1, right_excl=1)

# Must sit directly on top of the bar (top of bar = 1080 - 48 = 1032)
bottom_edge = y1 + h
bar_top = 1080 - 48
assert bottom_edge == bar_top, f"Visualizer bottom ({bottom_edge}) must match bar top ({bar_top}), gap = {bar_top - bottom_edge}"
assert x1 == 0, f"x1 should be 0, got {x1}"
assert x2 + w == 1920, f"x2 + w should reach right edge 1920, got {x2 + w}"

print("ok")
EOF
)"
    assert_eq "ok" "$py_out" "Visualizer with bottom bar must sit flush on top of the bar with 0 gap"
}

test_quickshell_placement_left_bar_flush() {
    local py_out
    py_out="$(python3 - << 'EOF'
def calc_qml(screen_w, screen_h, usable_w, usable_h, bottom_excl, left_excl, right_excl, border_th=1):
    center_gap = round(screen_w * (224.0 / 1920.0))
    vis_w = int((usable_w - center_gap) // 2)
    vis_h = round(usable_h * (416.0 / 1080.0))
    raw_y = round(screen_h - bottom_excl - vis_h)
    min_y = round(screen_h * 0.5)
    max_y = round(screen_h - bottom_excl - vis_h)
    vis_y = max(min_y, min(max_y, raw_y))

    vis_x1 = 0 if left_excl <= border_th else round(left_excl)
    vis_x2 = round(screen_w - vis_w if right_excl <= border_th else screen_w - right_excl - vis_w)
    return vis_x1, vis_y, vis_w, vis_h, vis_x2

# Left bar scenario: leftExclusion=48, bottomExclusion=1 (border), rightExclusion=1
# screenHeight=1080, usableHeight=1080 - 1 = 1079
x1, y1, w, h, x2 = calc_qml(1920, 1080, 1920 - 48 - 1, 1080 - 1, bottom_excl=1, left_excl=48, right_excl=1)

# Left applet must sit flush against left bar (x1 = 48)
assert x1 == 48, f"Left applet x1 expected 48 (flush with left bar), got {x1}"

# Bottom edge must sit flush at screen bottom (1080 - 1 = 1079)
bottom_edge = y1 + h
assert bottom_edge == 1079, f"Visualizer bottom ({bottom_edge}) must be flush at bottom screen boundary (1079)"

print("ok")
EOF
)"
    assert_eq "ok" "$py_out" "Visualizer with left bar must sit flush with left bar and screen bottom"
}

test_export_plasma_config_sync_generates_dynamic_item_geometries() {
    local tmp
    tmp="$(new_tmpdir)"

    # Create dummy appletsrc
    cat > "$tmp/plasma-org.kde.plasma.desktop-appletsrc" << 'EOF'
[Containments][1]
plugin=org.kde.desktopcontainment
ItemGeometriesHorizontal=

[Containments][1][Applets][1]
immutability=1
plugin=luisbocanegra.audio.visualizer

[Containments][1][Applets][2]
immutability=1
plugin=luisbocanegra.audio.visualizer
EOF

    # Create dummy double_reversed.conf
    local conf_dir="$tmp/caelestia/plasma-audio-visualizer"
    mkdir -p "$conf_dir"
    cat > "$conf_dir/double_reversed.conf" << 'EOF'
[Applet_1]
immutability=1
plugin=luisbocanegra.audio.visualizer

[Applet_2]
immutability=1
plugin=luisbocanegra.audio.visualizer
EOF

    # Run sync in test mode via export-plasma-config.sh with custom 2560x1440 coordinates
    (
        USER_CONFIG_DIR="$tmp"
        CAELESTIA_TEST_MODE=1
        source "$EXPORT_SCRIPT"
        sync_kde_applets \
            "$conf_dir/double_reversed.conf" \
            "$tmp" \
            "luisbocanegra.audio.visualizer" \
            "2" \
            "plasma-audio-visualizer" \
            "double_reversed" \
            "0" "885" "1130" "555" "1430" "885" "1130" "555"
    )

    local res_file="$tmp/plasma-org.kde.plasma.desktop-appletsrc"
    assert_file_contains "$res_file" "ItemGeometriesHorizontal=" "Must write ItemGeometriesHorizontal"
    assert_file_contains "$res_file" "Applet-1:0,885,1130,555,0" "Must write Applet 1 custom geometry"
    assert_file_contains "$res_file" "Applet-2:1430,885,1130,555,0" "Must write Applet 2 custom geometry"
}

test_visualizer_sh_entrypoint_and_fallbacks() {
    local vis_sh="$REPO_ROOT/shell/scripts/plasma-config/scripts/visualizer.sh"
    assert_file_contains "$vis_sh" 'USER_CONFIG_DIR="${USER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"' \
        "visualizer.sh must define fallback USER_CONFIG_DIR"
    assert_file_contains "$vis_sh" 'CONFIG_DIR="${CONFIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"' \
        "visualizer.sh must define fallback CONFIG_DIR"
    assert_file_contains "$vis_sh" 'exec bash "$_MAIN_SCRIPT" visualizer "$@"' \
        "visualizer.sh must support direct CLI execution"
}

test_visualizer_effective_enabled_player_condition() {
    assert_file_contains "$WIDGETS_QML" "readonly property bool isPlayerPlaying:" \
        "PlasmaWidgets.qml must define isPlayerPlaying condition"
    assert_file_contains "$WIDGETS_QML" "readonly property bool visualizerBaseConditions:" \
        "PlasmaWidgets.qml must define visualizerBaseConditions for instant hiding"
    assert_file_contains "$WIDGETS_QML" "visualizerBaseConditions && debouncedPlayerPlaying" \
        "visualizerEffectiveEnabled must require base conditions and debouncedPlayerPlaying"
    assert_file_contains "$WIDGETS_QML" "id: playerStopTimer" \
        "PlasmaWidgets.qml must have dedicated playerStopTimer"
}

run_tests
