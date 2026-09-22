#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLOR="$REPO_ROOT/src/bin/caelestia-color"

SANDBOX=""
STUB_DIR=""
CALLS=""
KDE_CALLS=""
OUTPUT=""
STATUS=0

write_stub_matugen() {
    cat > "$STUB_DIR/matugen" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MATUGEN_CALLS"

config=""
mode="dark"
meta="{}"
kind=""
source=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
        --config) config="${args[i + 1]}" ;;
        --mode) mode="${args[i + 1]}" ;;
        --import-json-string) meta="${args[i + 1]}" ;;
        image|json) kind="${args[i]}"; source="${args[i + 1]}" ;;
    esac
done

# The primary a template is rendered with. An image render derives it, and this stub derives
# the same fixed palette its scheme template writes; a json render is handed a palette, which
# is how one the command has scaled reaches the fan out.
render_primary() {
    if [[ "$kind" == "json" ]]; then
        python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["colors"]["primary"]["dark"]["color"].lstrip("#"))' "$source"
    else
        printf '92cef5'
    fi
}

# matugen resolves "smart" itself; this stub always ands up dark.
[[ "$mode" == "smart" ]] && mode="dark"

json_field() {
    printf '%s' "$meta" | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"
}

awk '
    /^\[templates\./ { id = substr($0, 12, length($0) - 12); next }
    /^input_path/ { input = $0; sub(/^input_path = "/, "", input); sub(/"$/, "", input); next }
    /^output_path/ { output = $0; sub(/^output_path = "/, "", output); sub(/"$/, "", output); print id "|" input "|" output; next }
' "$config" | while IFS='|' read -r id input output; do
    mkdir -p "$(dirname "$output")"
    if [[ "$id" == "scheme" ]]; then
        cat > "$output" <<EOF
{
    "name": "$(json_field name)",
    "flavour": "$(json_field flavour)",
    "variant": "$(json_field variant)",
    "mode": "$mode",
    "colours": {
        "background": "101417",
        "onSurface": "dfe6ed",
        "surface": "0a0f12",
        "primary": "92cef5",
        "term0": "333a40"
    }
}
EOF
    else
        case "${input##*/}" in
            palettes.json.tmpl)
                # What the real template renders: every palette, every shade.
                printf '%s' '{"primary": {"50": "227cbb"}, "secondary": {"50": "677987"}, "tertiary": {"50": "6e759f"}, "neutral": {"50": "74777a"}, "neutral_variant": {"50": "71787e"}}' > "$output"
                ;;
            *)
                printf 'primary %s\n' "$(render_primary)" > "$output"
                ;;
        esac
    fi
done
STUB
    chmod +x "$STUB_DIR/matugen"
}

write_stub_ffmpeg() {
    cat > "$STUB_DIR/ffmpeg" <<'STUB'
#!/usr/bin/env bash
case "${FFMPEG_PATTERN:-gray}" in
    gray) printf '\x80\x80\x80\x80\x80\x80' ;;
    redblue) printf '\xff\x00\x00\x00\x00\xff' ;;
    *) exit 1 ;;
    esac
STUB
    chmod +x "$STUB_DIR/ffmpeg"
}

write_stub_kde() {
    cat > "$STUB_DIR/plasma-apply-colorscheme" <<'STUB'
#!/usr/bin/env bash
printf 'apply %s\n' "$*" >> "$KDE_CALLS"
STUB
    cat > "$STUB_DIR/kwriteconfig6" <<'STUB'
#!/usr/bin/env bash
printf 'write %s\n' "$*" >> "$KDE_CALLS"
STUB
    cat > "$STUB_DIR/kreadconfig6" <<'STUB'
#!/usr/bin/env bash
[[ -n "${KREAD_SCHEME:-}" ]] || exit 1
printf '%s\n' "$KREAD_SCHEME"
STUB
    chmod +x "$STUB_DIR/plasma-apply-colorscheme" "$STUB_DIR/kwriteconfig6" "$STUB_DIR/kreadconfig6"
}

setup_sandbox() {
    SANDBOX="$(new_tmpdir)"
    STUB_DIR="$SANDBOX/bin"
    CALLS="$SANDBOX/matugen-calls.log"
    KDE_CALLS="$SANDBOX/kde-calls.log"
    mkdir -p "$STUB_DIR" "$SANDBOX/config" "$SANDBOX/state" "$SANDBOX/cache" "$SANDBOX/data" "$SANDBOX/pictures"
    write_stub_matugen
    write_stub_ffmpeg
    write_stub_kde

    export CAELESTIA_DATA_DIR="$REPO_ROOT/src"
    export XDG_CONFIG_HOME="$SANDBOX/config"
    export XDG_STATE_HOME="$SANDBOX/state"
    export XDG_CACHE_HOME="$SANDBOX/cache"
    export XDG_DATA_HOME="$SANDBOX/data"
    export XDG_PICTURES_DIR="$SANDBOX/pictures"
    export MATUGEN_CALLS="$CALLS"
    export KDE_CALLS="$KDE_CALLS"
    export PATH="$STUB_DIR:$PATH"
}

run_color() {
    : > "$CALLS"
    : > "$KDE_CALLS"
    OUTPUT="$(
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_PICTURES_DIR="$XDG_PICTURES_DIR" \
        CAELESTIA_DATA_DIR="$CAELESTIA_DATA_DIR" \
        MATUGEN_CALLS="$CALLS" \
        KDE_CALLS="$KDE_CALLS" \
        FFMPEG_PATTERN="${FFMPEG_PATTERN:-gray}" \
        PATH="$PATH" \
        bash "$COLOR" "$@" 2>&1
    )"
    STATUS=$?
}

wallpaper_image() {
    local path="$XDG_PICTURES_DIR/$1"
    printf 'not really a png\n' > "$path"
    printf '%s' "$(realpath -- "$path")"
}

set_cli_config() {
    mkdir -p "$XDG_CONFIG_HOME/caelestia"
    printf '%s' "$1" > "$XDG_CONFIG_HOME/caelestia/cli.json"
}

test_list_names_are_the_shipped_ones() {
    setup_sandbox
    run_color scheme list -n
    assert_status 0 "$STATUS" "scheme list -n should succeed"
    assert_contains "$OUTPUT" "catppuccin" "the shipped names are listed"
    assert_contains "$OUTPUT" "gruvbox" "more than one name is listed"
    assert_ne "" "$OUTPUT" "the list is not empty"
}

test_list_flat_is_the_shape_the_colors_page_reads() {
    setup_sandbox
    run_color scheme list --flat
    assert_status 0 "$STATUS" "scheme list --flat should succeed"

    local described
    described="$(printf '%s' "$OUTPUT" | python3 -c '
import json, sys
entries = json.load(sys.stdin)
assert entries, "no entries"
keys = {"name", "flavour", "mode", "colours"}
for entry in entries:
    assert keys <= set(entry), f"missing keys in {entry.keys()}"
    for role, value in entry["colours"].items():
        assert "#" not in value, f"{role} carries a hash: {value}"
print(f"{len(entries)} entries")
' 2>&1)"
    assert_contains "$described" "entries" "the flat list parses and carries the expected keys: $described"
}

test_set_a_named_scheme_writes_its_own_file() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark
    assert_status 0 "$STATUS" "setting a named scheme should succeed"

    local scheme="$XDG_STATE_HOME/caelestia/scheme.json"
    assert_file_exists "$scheme"

    local described
    described="$(python3 - "$scheme" "$REPO_ROOT/src/schemes/catppuccin/mocha/dark.txt" <<'PY' 2>&1
import json, pathlib, sys
scheme = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = {}
for line in pathlib.Path(sys.argv[2]).read_text().splitlines():
    parts = line.split()
    if len(parts) == 2:
        source[parts[0]] = parts[1].lstrip("#")
assert scheme["name"] == "catppuccin", scheme["name"]
assert scheme["flavour"] == "mocha", scheme["flavour"]
assert scheme["mode"] == "dark", scheme["mode"]
assert scheme["colours"] == source, "the colors differ from the shipped file"
print(f'{len(scheme["colours"])} roles, all from the file')
PY
)"
    assert_contains "$described" "roles, all from the file" "$described"
}

test_a_named_scheme_without_the_mode_asked_for_says_so() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m light
    assert_status 0 "$STATUS" "the switch should still happen"
    assert_contains "$OUTPUT" "has no light colors" "the substitution is reported"
    assert_contains "$(cat "$XDG_STATE_HOME/caelestia/scheme.json")" '"mode": "dark"' \
        "the mode that exists is the one written"
}

test_unknown_schemes_are_refused() {
    setup_sandbox
    run_color scheme set -n nosuchscheme -f medium -m dark
    assert_status 1 "$STATUS" "an unknown scheme should fail"
    assert_contains "$OUTPUT" "no such scheme" "the reason is named"
    assert_file_missing "$XDG_STATE_HOME/caelestia/scheme.json"
}

test_dynamic_without_a_wallpaper_explains_itself() {
    setup_sandbox
    run_color scheme set -n dynamic
    assert_status 1 "$STATUS" "a dynamic scheme without a wallpaper should fail"
    assert_contains "$OUTPUT" "no wallpaper has been set yet" "the reason is named"
}

test_get_prints_the_fields_that_were_asked_for() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark
    run_color scheme get -n -m -v
    assert_status 0 "$STATUS" "scheme get should succeed"
    assert_eq "catppuccin
dark
tonalspot" "$OUTPUT" "name, mode and variant come back in order"
}

test_wallpaper_writes_the_state_the_shell_watches() {
    setup_sandbox
    local image
    image="$(wallpaper_image wall.png)"
    run_color wallpaper -f "$image"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    assert_eq "$image" "$(cat "$XDG_STATE_HOME/caelestia/wallpaper/path.txt")" \
        "path.txt carries the wallpaper"
    assert_eq "$image" "$(readlink "$XDG_STATE_HOME/caelestia/wallpaper/current")" \
        "the symlink points at it"
    local scheme="$XDG_STATE_HOME/caelestia/scheme.json"
    assert_file_exists "$scheme"
    assert_contains "$(cat "$scheme")" '"name": "dynamic"' "the scheme follows the wallpaper"
    assert_contains "$(cat "$CALLS")" "image" "matugen is asked for an image"
    assert_contains "$(cat "$CALLS")" "--source-color-index 0" \
        "the source color is picked, not prompted for"
}

test_the_roles_the_shell_reads_come_with_a_generated_scheme() {
    setup_sandbox
    local image
    image="$(wallpaper_image wall.png)"
    run_color wallpaper -f "$image"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    local described
    described="$(python3 - "$XDG_STATE_HOME/caelestia/scheme.json" <<'PY' 2>&1
import json, pathlib, sys
colours = json.loads(pathlib.Path(sys.argv[1]).read_text())["colours"]
expected = {
    "primary_paletteKeyColor": "227cbb",
    "secondary_paletteKeyColor": "677987",
    "tertiary_paletteKeyColor": "6e759f",
    "neutral_paletteKeyColor": "74777a",
    "neutral_variant_paletteKeyColor": "71787e",
    "success": "B5CCBA",
    "onSuccess": "213528",
    "successContainer": "374B3E",
    "onSuccessContainer": "D1E9D6",
    "text": "dfe6ed",
}
for role, value in expected.items():
    actual = colours.get(role)
    assert actual == value, f"{role}: expected {value}, got {actual}"
print(f"{len(expected)} roles folded in")
PY
)"
    assert_contains "$described" "roles folded in" "$described"
}

test_the_wallpaper_picks_the_variant_unless_asked_not_to() {
    setup_sandbox
    local image
    image="$(wallpaper_image wall.png)"

    FFMPEG_PATTERN=gray run_color wallpaper -f "$image"
    assert_contains "$(cat "$CALLS")" "--type scheme-neutral" \
        "a flat wallpaper picks the neutral variant"
    assert_contains "$(cat "$CALLS")" "--mode smart" "the wallpaper picks the mode"
    assert_contains "$(cat "$XDG_STATE_HOME/caelestia/scheme.json")" '"variant": "neutral"' \
        "the scheme is filed under the variant it really is"

    FFMPEG_PATTERN=redblue run_color wallpaper -f "$image"
    assert_contains "$(cat "$CALLS")" "--type scheme-tonal-spot" \
        "a colourful wallpaper picks the tonal spot variant"

    FFMPEG_PATTERN=unreadable run_color wallpaper -f "$image"
    assert_status 0 "$STATUS" "an unreadable image should still produce a scheme"
    assert_contains "$(cat "$CALLS")" "--type scheme-smart" "matugen picks the variant as a fallback"
}

test_no_smart_keeps_the_mode_and_variant() {
    setup_sandbox
    local image
    image="$(wallpaper_image wall.png)"

    run_color wallpaper -f "$image" --no-smart
    run_color scheme set -n dynamic -v rainbow -m light
    run_color wallpaper -f "$image" --no-smart

    local calls
    calls="$(cat "$CALLS")"
    assert_contains "$calls" "--type scheme-rainbow" "--no-smart keeps the variant"
    assert_contains "$calls" "--mode light" "--no-smart keeps the mode"
    assert_eq "0" "$(printf '%s' "$calls" | grep -c 'scheme-smart' || true)" \
        "no smart type is passed with --no-smart (calls: $calls)"
    assert_eq "0" "$(printf '%s' "$calls" | grep -c -- '--mode smart' || true)" \
        "no smart mode is passed with --no-smart (calls: $calls)"
}

test_a_named_scheme_does_not_follow_the_wallpaper() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark
    local before
    before="$(cat "$XDG_STATE_HOME/caelestia/scheme.json")"

    local image
    image="$(wallpaper_image other.png)"
    run_color wallpaper -f "$image"
    assert_status 0 "$STATUS" "the wallpaper should still be set"
    assert_eq "$before" "$(cat "$XDG_STATE_HOME/caelestia/scheme.json")" \
        "a scheme the user picked is left alone"
    assert_eq "$image" "$(cat "$XDG_STATE_HOME/caelestia/wallpaper/path.txt")" \
        "the wallpaper state is still updated"
}

test_the_generated_config_follows_the_user_config() {
    setup_sandbox
    set_cli_config '{"theme": {"enableGtk": false}}'
    run_color scheme set -n catppuccin -f mocha -m dark
    assert_status 0 "$STATUS" "the switch should succeed with a config file"

    # A named scheme is rendered from its own palette rather than derived from the wallpaper, so
    # the config it is rendered through is the fan out one; the targets it lists are the point.
    local config="$XDG_STATE_HOME/caelestia/matugen/fanout.toml"
    assert_file_exists "$config"
    assert_contains "$(cat "$config")" "btop.theme" "an enabled target is in the config"
    assert_not_contains "$(cat "$config")" "gtk-colors.css" "a disabled target is not"
    assert_file_missing "$XDG_CONFIG_HOME/gtk-3.0/colors.css"
    assert_file_missing "$XDG_CONFIG_HOME/gtk-4.0/colors.css"
    assert_file_exists "$XDG_CONFIG_HOME/btop/themes/matugen.theme"
    assert_file_exists "$XDG_CACHE_HOME/caelestia/terminal-sequences"
    assert_file_exists "$XDG_DATA_HOME/color-schemes/Matugen.colors"

    set_cli_config '{"theme": {"enableBtop": false, "enableQt": false}}'
    rm -rf "$XDG_CONFIG_HOME/btop" "$XDG_CONFIG_HOME/qt5ct"
    run_color scheme set -n catppuccin -f mocha -m dark
    assert_file_missing "$XDG_CONFIG_HOME/btop/themes/matugen.theme"
    assert_file_missing "$XDG_CONFIG_HOME/qt5ct/colors/matugen.conf"
    assert_file_exists "$XDG_CONFIG_HOME/rofi/colors.rasi"
}

test_starship_is_not_written_unless_asked_for() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark
    assert_file_missing "$XDG_CONFIG_HOME/starship.toml"

    set_cli_config '{"theme": {"enableStarship": true}}'
    run_color scheme set -n catppuccin -f mocha -m dark
    assert_file_exists "$XDG_CONFIG_HOME/starship.toml"
}

test_a_preview_changes_nothing() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark
    local before
    before="$(cat "$XDG_STATE_HOME/caelestia/scheme.json")"

    run_color scheme set --preview -n gruvbox -f medium -m dark
    assert_status 0 "$STATUS" "a preview should succeed"
    assert_contains "$OUTPUT" '"name": "gruvbox"' "the preview prints the scheme that would be set"
    assert_eq "$before" "$(cat "$XDG_STATE_HOME/caelestia/scheme.json")" \
        "the scheme in effect is untouched"
    assert_ne "$before" "$OUTPUT" "the preview is not the current scheme"
}

test_the_user_templates_are_rendered() {
    setup_sandbox
    mkdir -p "$XDG_CONFIG_HOME/caelestia/templates"
    cat > "$XDG_CONFIG_HOME/caelestia/templates/thing.conf" <<'EOF'
background={{ background.hex }}
upper={{ background.hex | upper }}
mode={{ mode }}
unknown={{ background.nosuchfield }}
EOF

    run_color scheme set -n catppuccin -f mocha -m dark
    assert_status 0 "$STATUS" "the switch should succeed"

    local rendered="$XDG_STATE_HOME/caelestia/theme/thing.conf"
    assert_file_exists "$rendered"

    local expected
    expected="$(python3 - "$REPO_ROOT/src/schemes/catppuccin/mocha/dark.txt" <<'PY'
import pathlib, sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    parts = line.split()
    if len(parts) == 2 and parts[0] == "background":
        print(parts[1])
        break
PY
)"
    assert_contains "$(cat "$rendered")" "background=$expected" "the role was rendered"
    assert_contains "$(cat "$rendered")" "mode=dark" "the mode was rendered"
    assert_contains "$(cat "$rendered")" "unknown={{ background.nosuchfield }}" \
        "a field that does not exist is left as it was"
}

test_the_hooks_run_with_the_scheme_in_their_environment() {
    setup_sandbox
    local log="$SANDBOX/hook.log"
    set_cli_config "{\"theme\": {\"postHook\": \"echo theme \$SCHEME_NAME \$SCHEME_MODE >> $log\"}, \"wallpaper\": {\"postHook\": \"echo wallpaper \$WALLPAPER_PATH >> $log\"}}"

    local image
    image="$(wallpaper_image wall.png)"
    run_color wallpaper -f "$image"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    local logged
    logged="$(cat "$log" 2>/dev/null || true)"
    assert_contains "$logged" "theme dynamic dark" "the theme hook saw the scheme"
    assert_contains "$logged" "wallpaper $image" "the wallpaper hook saw the wallpaper"
}

test_the_wallpaper_preview_changes_nothing() {
    setup_sandbox
    local first
    first="$(wallpaper_image first.png)"
    run_color wallpaper -f "$first"
    local before
    before="$(cat "$XDG_STATE_HOME/caelestia/scheme.json")"

    local second
    second="$(wallpaper_image second.png)"

    run_color wallpaper -p "$second"
    assert_status 0 "$STATUS" "the preview should succeed"
    assert_contains "$OUTPUT" '"name": "dynamic"' "the preview prints a scheme"
    assert_eq "$before" "$(cat "$XDG_STATE_HOME/caelestia/scheme.json")" \
        "the scheme in effect is untouched"
    assert_eq "$first" "$(cat "$XDG_STATE_HOME/caelestia/wallpaper/path.txt")" \
        "the wallpaper is untouched too"

    run_color wallpaper -p
    assert_status 0 "$STATUS" "a preview without a path falls back to the wallpaper set"
    assert_contains "$OUTPUT" '"name": "dynamic"' "and prints its scheme"

    assert_contains "$OUTPUT" '"colours"' "the preview carries colours"
}

test_a_random_scheme_is_one_of_the_shipped_ones() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark
    run_color scheme set -r
    assert_status 0 "$STATUS" "a random switch should succeed"

    local chosen
    chosen="$(python3 -c "import json; print(json.load(open('$XDG_STATE_HOME/caelestia/scheme.json'))['name'])")"
    assert_contains "$(run_color scheme list -n; printf '%s' "$OUTPUT")" "$chosen" \
        "the random scheme is one of the shipped names: $chosen"
    assert_ne "catppuccin" "$chosen" "it is not the scheme that was already in effect"
}

test_the_palette_reaches_the_desktop() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image one.png)"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    assert_file_exists "$XDG_DATA_HOME/color-schemes/Matugen.colors"
    assert_contains "$(cat "$KDE_CALLS")" "apply Matugen" "the palette is applied to Plasma"

    assert_contains "$(cat "$KDE_CALLS")" "--key AccentColor --delete" \
        "a leftover accent color is dropped"
    assert_contains "$(cat "$KDE_CALLS")" "--key AccentColorFromWallpaper --delete" \
        "and so is Plasma deriving one from the wallpaper"
}

test_the_applied_name_rotates_so_a_change_is_an_apply() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image one.png)"
    assert_status 0 "$STATUS" "the first change should succeed"

    export KREAD_SCHEME="Matugen"
    run_color wallpaper -f "$(wallpaper_image two.png)"
    assert_status 0 "$STATUS" "the second change should succeed"
    assert_contains "$(cat "$KDE_CALLS")" "apply Matugen Alt" \
        "the name it is applied under differs from the one in effect"
    assert_eq "$(cat "$XDG_DATA_HOME/color-schemes/Matugen.colors")" \
        "$(cat "$XDG_DATA_HOME/color-schemes/Matugen Alt.colors")" \
        "both names carry the palette that was just generated"
}

test_konsole_gets_a_scheme_in_its_own_format() {
    setup_sandbox
    mkdir -p "$XDG_DATA_HOME/konsole"
    printf '[General]\nName=Profile 1\n[Appearance]\nColorScheme=Breeze\n' \
        > "$XDG_DATA_HOME/konsole/Profile 1.profile"

    run_color wallpaper -f "$(wallpaper_image one.png)"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    local colours="$XDG_DATA_HOME/konsole/Matugen.colorscheme"
    assert_file_exists "$colours"
    assert_contains "$(cat "$colours")" "Color=10,15,18" "the surface is the background"
    assert_contains "$(cat "$colours")" "Color=223,230,237" "onSurface is the text"
    assert_contains "$(cat "$colours")" "[Color15Intense]" \
        "every colour has the groups Konsole looks for"

    local described
    described="$(python3 - "$colours" <<'PY' 2>&1
import pathlib, re, sys
entries = [
    line for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
    if line.startswith("Color=")
]
bad = [line for line in entries if not re.fullmatch(r"Color=\d{1,3},\d{1,3},\d{1,3}", line)]
assert not bad, bad
assert len(entries) == 54, len(entries)
print(f"{len(entries)} entries, all R,G,B")
PY
)"
    assert_contains "$described" "all R,G,B" "$described"
    assert_contains "$(cat "$KDE_CALLS")" \
        "--file $XDG_DATA_HOME/konsole/Profile 1.profile --group Appearance --key ColorScheme Matugen" \
        "the profile is pointed at the scheme"
}

test_the_kvantum_theme_that_was_written_is_the_one_in_use() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image one.png)"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    assert_file_exists "$XDG_CONFIG_HOME/Kvantum/matugen/matugen.kvconfig"
    assert_contains "$(cat "$KDE_CALLS")" \
        "--file $XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig --group General --key theme matugen" \
        "the theme the fan out wrote is the one selected"
}

test_turning_the_desktop_apply_off_leaves_it_alone() {
    setup_sandbox
    set_cli_config '{"theme": {"enableKde": false, "enableKonsole": false, "enableKvantum": false}}'
    run_color scheme set -n catppuccin -f mocha -m dark
    assert_status 0 "$STATUS" "the scheme is still written for the shell to read"
    assert_file_exists "$XDG_STATE_HOME/caelestia/scheme.json"
    assert_eq "" "$(cat "$KDE_CALLS")" "nothing was applied to the desktop"
}

# The intensity is a property of the scheme, like the variant: it is written beside
# the name, read back when the palette is derived again, and read by the shell out of
# the same file. It lives here rather than in the CLI config because every re-derive -
# a wallpaper change, the login reseed - goes through these functions and none of them
# pass a flag.
intensity_of() {
    python3 -c 'import json, pathlib, sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["intensity"])' "$1"
}

# A role's colour in the scheme the command wrote, as the shell reads it.
colour_of() {
    python3 -c 'import json, pathlib, sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["colours"][sys.argv[2]])' "$1" "$2"
}

test_the_intensity_defaults_to_what_the_engine_produced() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    local scheme="$XDG_STATE_HOME/caelestia/scheme.json"
    assert_eq "1" "$(intensity_of "$scheme")" "a palette nobody has tuned is at 1"

    local described
    described="$(python3 - "$scheme" <<'PY' 2>&1
import json, pathlib, sys
colours = json.loads(pathlib.Path(sys.argv[1]).read_text())["colours"]
assert colours["primary"] == "92cef5", colours["primary"]
assert colours["background"] == "101417", colours["background"]
print("the render is left alone")
PY
)"
    assert_contains "$described" "the render is left alone" "$described"
}

test_the_intensity_scales_the_chroma_of_a_generated_palette() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"

    run_color scheme set -i 1.5
    assert_status 0 "$STATUS" "setting the intensity should succeed"

    local scheme="$XDG_STATE_HOME/caelestia/scheme.json"
    assert_eq "1.5" "$(intensity_of "$scheme")" "the factor is recorded in the scheme"

    # The render's own colors with their saturation scaled by 1.5 and their hue and tone held,
    # worked out from the definitions rather than by running this command, so this checks it
    # rather than echoing it. 92cef5 reaches full saturation on the way, which is the clamp.
    local described
    described="$(python3 - "$scheme" <<'PY' 2>&1
import json, pathlib, sys

colours = json.loads(pathlib.Path(sys.argv[1]).read_text())["colours"]
expected = {
    "background": "0e1419",
    "onSurface": "dce6f0",
    "surface": "080f14",
    "primary": "88d0ff",
    "term0": "303a43",
}
wrong = {role: (colours.get(role), code) for role, code in expected.items() if colours.get(role) != code}
assert not wrong, f"scaled colors differ (rendered, expected): {wrong}"
print(f"{len(expected)} roles at saturation x1.5")
PY
)"
    assert_contains "$described" "roles at saturation x1.5" "$described"
}

test_the_intensity_survives_a_wallpaper_change() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image one.png)"
    run_color scheme set -i 1.5
    assert_status 0 "$STATUS" "setting the intensity should succeed"

    run_color wallpaper -f "$(wallpaper_image two.png)"
    assert_status 0 "$STATUS" "the wallpaper should still be set"

    local scheme="$XDG_STATE_HOME/caelestia/scheme.json"
    assert_eq "1.5" "$(intensity_of "$scheme")" \
        "the palette derived from the new wallpaper is at the intensity that was set"

    local described
    described="$(python3 - "$scheme" <<'PY' 2>&1
import colorsys, json, pathlib, sys
colours = json.loads(pathlib.Path(sys.argv[1]).read_text())["colours"]
r, g, b = (int(colours["onSurface"][i:i + 2], 16) / 255 for i in (0, 2, 4))
saturation = colorsys.rgb_to_hls(r, g, b)[2] * 100
assert saturation > 9, f"onSurface is at {saturation}%, which is the unscaled palette"
print(f"onSurface is at {saturation:.1f}%")
PY
)"
    assert_contains "$described" "onSurface is at" "$described"
}

test_the_intensity_at_zero_is_a_grey_palette() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"
    run_color scheme set -i 0
    assert_status 0 "$STATUS" "a grey palette should be allowed"

    local described
    described="$(python3 - "$XDG_STATE_HOME/caelestia/scheme.json" <<'PY' 2>&1
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["intensity"] == 0, data["intensity"]
tinted = [
    role for role, code in data["colours"].items()
    if len({code[i:i + 2] for i in (0, 2, 4)}) != 1
]
assert not tinted, f"still tinted: {tinted}"
print(f'{len(data["colours"])} roles, all grey')
PY
)"
    assert_contains "$described" "roles, all grey" "$described"
}

test_an_intensity_outside_the_range_is_refused() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"

    local bad
    for bad in 3 -1 banana ""; do
        run_color scheme set -i "$bad"
        assert_status 1 "$STATUS" "-i '$bad' should be refused"
        assert_ne "" "$OUTPUT" "'$bad' is refused with a reason"
    done

    run_color scheme set -i 3
    assert_contains "$OUTPUT" "between 0 and 2" "the range is named"
    assert_eq "1" "$(intensity_of "$XDG_STATE_HOME/caelestia/scheme.json")" \
        "the palette keeps the intensity it had"
}

test_scheme_get_prints_the_intensity() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"
    run_color scheme set -i 1.25
    run_color scheme get -i
    assert_status 0 "$STATUS" "scheme get -i should succeed"
    assert_eq "1.25" "$OUTPUT" "the intensity comes back"
}

test_a_preview_shows_the_intensity_it_was_asked_for() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"

    run_color scheme set --preview -i 1.5
    assert_status 0 "$STATUS" "the preview should succeed"
    assert_contains "$OUTPUT" '"intensity": 1.5' "the preview is rendered at the intensity asked for"
    assert_eq "1" "$(intensity_of "$XDG_STATE_HOME/caelestia/scheme.json")" \
        "the palette in effect keeps its own intensity"
}

test_the_whole_desktop_follows_the_intensity_not_just_the_shell() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"
    assert_status 0 "$STATUS" "setting a wallpaper should succeed"

    local gtk="$XDG_CONFIG_HOME/gtk-3.0/colors.css"
    local plasma="$XDG_DATA_HOME/color-schemes/Matugen.colors"
    assert_eq "primary 92cef5" "$(cat "$gtk")" \
        "at the default intensity the fan out carries what matugen produced"

    run_color scheme set -i 1.5
    assert_status 0 "$STATUS" "setting the intensity should succeed"

    local scaled
    scaled="$(colour_of "$XDG_STATE_HOME/caelestia/scheme.json" primary)"
    assert_ne "92cef5" "$scaled" "the palette the shell reads was scaled"
    assert_eq "primary $scaled" "$(cat "$gtk")" \
        "the fan out was rendered from the scaled palette, not from matugen's own"
    assert_eq "primary $scaled" "$(cat "$plasma")" \
        "and so was the scheme the desktop is applied"
}

test_a_default_intensity_still_renders_in_one_pass() {
    setup_sandbox
    run_color wallpaper -f "$(wallpaper_image wall.png)"
    assert_eq "1" "$(grep -c . "$CALLS")" \
        "the default intensity renders the palette and the fan out in one pass"

    run_color scheme set -i 1.5
    assert_eq "2" "$(grep -c . "$CALLS")" \
        "an intensity renders the palette once, then the fan out from what it scaled"
}

test_a_named_scheme_keeps_the_colors_in_its_file() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -m dark -i 1.5
    assert_status 0 "$STATUS" "the switch should succeed"
    assert_contains "$OUTPUT" "wallpaper-derived" "the scope of the slider is named"

    local described
    described="$(python3 - "$XDG_STATE_HOME/caelestia/scheme.json" \
        "$REPO_ROOT/src/schemes/catppuccin/mocha/dark.txt" <<'PY' 2>&1
import json, pathlib, sys
scheme = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = {}
for line in pathlib.Path(sys.argv[2]).read_text().splitlines():
    parts = line.split()
    if len(parts) == 2:
        source[parts[0]] = parts[1].lstrip("#")
assert scheme["colours"] == source, "a named scheme is its file, scaled or not"
assert scheme["intensity"] == 1.5, "the setting travels with the scheme"
print("the file is the palette")
PY
)"
    assert_contains "$described" "the file is the palette" "$described"
}

run_tests
