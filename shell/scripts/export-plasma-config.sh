#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/plasma-config"
USER_CONFIG_DIR="${USER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"

show_help() {
    cat << EOF
Usage: $(basename "$0") [TARGET [ACTION]]

Exports, configures, or removes Plasma configurations and widgets.
If no target is specified, all configurations are exported.

Targets:
  skwd, skwd-wall, wall       Export skwd-wall-v2 config
  visualizer [enable|disable|configure]
                              Manage plasma-audio-visualizer widgets
  all                         Export all configs (default)
  -h, --help                  Show this help message
EOF
}

apply_skwd_wallpaper() {
    if [[ -z "${CAELESTIA_TEST_MODE:-}" && "$USER_CONFIG_DIR" != "/tmp/"* ]] && command -v skwd-helm >/dev/null 2>&1; then
        local curr_wall
        curr_wall="$(skwd-helm current 2>/dev/null | cut -f2- || true)"
        if [[ -z "$curr_wall" ]]; then
            local cache_json="${XDG_CACHE_HOME:-$HOME/.cache}/skwd-wall-v2/last-applied.json"
            if [[ -f "$cache_json" ]]; then
                curr_wall="$(python3 -c "import json; print(json.load(open('$cache_json')).get('any', {}).get('path', ''))" 2>/dev/null || true)"
            fi
        fi
        if [[ -n "$curr_wall" && -f "$curr_wall" ]]; then
            skwd-helm apply "$curr_wall" >/dev/null 2>&1 || true
        fi
    fi
}

export_skwd() {
    echo "Exporting skwd-wall-v2 configuration..."
    mkdir -p "$USER_CONFIG_DIR/skwd-wall-v2"
    cp "$CONFIG_DIR/skwd-wall-v2/config.json" "$USER_CONFIG_DIR/skwd-wall-v2/config.json"
    echo "✓ skwd-wall-v2 config exported to $USER_CONFIG_DIR/skwd-wall-v2/config.json"
}

# Syncs N applet instances from template into appletsrc files.
# Emits NEEDS_SECOND_RECONFIGURE if newly allocated IDs need another cycle for geometry.
sync_kde_applets() {
    python3 - "$@" << 'PYEOF'
import glob, os, re, subprocess, sys

conf_path, config_dir, plugin_id, count_str, label = \
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
count = int(count_str)

custom_geoms = {}
if len(sys.argv) >= 14 and sys.argv[6]:
    try:
        custom_geoms[1] = f"{sys.argv[6]},{sys.argv[7]},{sys.argv[8]},{sys.argv[9]},0"
        custom_geoms[2] = f"{sys.argv[10]},{sys.argv[11]},{sys.argv[12]},{sys.argv[13]},0"
    except Exception:
        pass

with open(conf_path) as f:
    conf = f.read()

templates = {}
for block in re.split(r"(?m)(?=^\[Applet_\d+\]$)", conf):
    m = re.match(r"^\[Applet_(\d+)\]$", block.strip().splitlines()[0]) if block.strip() else None
    if not m:
        continue
    idx = int(m.group(1))
    geom_m = re.search(r"^geometry=(.*)$", block, re.M)
    geom = geom_m.group(1).strip() if geom_m else custom_geoms.get(idx, "")
    cleaned = re.sub(r"^geometry=.*\n?", "", block, flags=re.M).strip()
    templates[idx] = {"geom": geom, "block": cleaned}

candidate_files = []
shell_pkg = ""
try:
    shell_pkg = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.shell"],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
except Exception:
    pass

if shell_pkg:
    pkg_file = os.path.join(config_dir, f"plasma-{shell_pkg}-appletsrc")
    if os.path.exists(pkg_file):
        candidate_files.append(pkg_file)

for default_name in ["plasma-caelestia.desktop-appletsrc", "plasma-org.kde.plasma.desktop-appletsrc"]:
    p = os.path.join(config_dir, default_name)
    if os.path.exists(p) and p not in candidate_files:
        candidate_files.append(p)

for f in sorted(glob.glob(os.path.join(config_dir, "*desktop-appletsrc"))):
    if f not in candidate_files:
        candidate_files.append(f)

if not candidate_files:
    default_target = os.path.join(config_dir, "plasma-caelestia.desktop-appletsrc")
    with open(default_target, "w") as fh:
        fh.write("[Containments][1]\nplugin=org.kde.desktopcontainment\n")
    candidate_files = [default_target]

any_new_ids = False

for appletsrc in candidate_files:
    with open(appletsrc, "r") as f:
        text = f.read()

    c_m = re.search(
        r"\[Containments\]\[(\d+)\](?:(?!\[Containments\]).)*?"
        r"(?:plugin=org\.kde\.desktopcontainment|plugin=org\.kde\.plasma\.folder)",
        text, re.S
    )
    c_id = c_m.group(1) if c_m else "1"

    all_ids = set(int(x) for x in re.findall(
        rf"\[Containments\]\[{c_id}\]\[Applets\]\[(\d+)\]", text
    ))

    existing_ids = []
    for a_id in sorted(all_ids):
        pat = (
            rf"\[Containments\]\[{c_id}\]\[Applets\]\[{a_id}\]\n"
            rf"(?:(?!^\[).)*?plugin={re.escape(plugin_id)}"
        )
        if re.search(pat, text, re.S | re.M):
            existing_ids.append(a_id)

    if len(existing_ids) >= count:
        keep_ids = existing_ids[:count]
        remove_ids = existing_ids[count:]
        new_ids = []
    else:
        keep_ids = list(existing_ids)
        remove_ids = []
        new_ids = []
        next_id = max(all_ids, default=0) + 1
        while len(keep_ids) < count:
            while next_id in all_ids:
                next_id += 1
            keep_ids.append(next_id)
            new_ids.append(next_id)
            all_ids.add(next_id)
            next_id += 1

    if new_ids:
        any_new_ids = True

    sections = re.split(r"(?m)(?=^\[)", text)

    # 1. Update ItemGeometries in desktop containment
    c_header = f"[Containments][{c_id}]"
    c_found = False
    for i, sec in enumerate(sections):
        lines = sec.splitlines()
        if not lines or lines[0].strip() != c_header:
            continue
        c_found = True
        c_lines = lines[:]
        for idx, a_id in enumerate(keep_ids, start=1):
            g = templates.get(idx, {}).get("geom", "")
            if not g:
                continue
            for gk in ("ItemGeometries-1920x1080", "ItemGeometriesHorizontal"):
                found_key = False
                for li, line in enumerate(c_lines):
                    if line.startswith(f"{gk}="):
                        found_key = True
                        if f"Applet-{a_id}:" in line:
                            c_lines[li] = re.sub(
                                rf"Applet-{a_id}:[^;\n]+", f"Applet-{a_id}:{g}", line
                            )
                        else:
                            sep = "" if line.endswith("=") else ";"
                            c_lines[li] = line.rstrip(";") + f"{sep}Applet-{a_id}:{g};"
                if not found_key:
                    c_lines.append(f"{gk}=Applet-{a_id}:{g};")
        for r_id in remove_ids:
            for li, line in enumerate(c_lines):
                if line.startswith("ItemGeometries"):
                    c_lines[li] = re.sub(rf"Applet-{r_id}:[^;\n]+;?", "", line)
        sections[i] = "\n".join(c_lines) + "\n\n"
        break

    if not c_found:
        c_lines = [c_header, "plugin=org.kde.desktopcontainment"]
        for idx, a_id in enumerate(keep_ids, start=1):
            g = templates.get(idx, {}).get("geom", "")
            if g:
                c_lines.append(f"ItemGeometries-1920x1080=Applet-{a_id}:{g};")
                c_lines.append(f"ItemGeometriesHorizontal=Applet-{a_id}:{g};")
        sections.insert(0, "\n".join(c_lines) + "\n\n")

    # 2. Filter out removed and updated applet sections
    to_remove_pfx = [f"[Containments][{c_id}][Applets][{r}]" for r in remove_ids]
    to_update_pfx = [f"[Containments][{c_id}][Applets][{k}]" for k in keep_ids]

    filtered = []
    for sec in sections:
        lines = sec.splitlines()
        if not lines or not lines[0].startswith("["):
            if sec.strip():
                filtered.append(sec)
            continue
        hdr = lines[0].strip()
        if any(hdr.startswith(p) for p in to_remove_pfx):
            continue
        if any(hdr.startswith(p) for p in to_update_pfx):
            continue
        filtered.append(sec)

    # 3. Append template applet sections
    for idx, a_id in enumerate(keep_ids, start=1):
        tmpl = templates.get(idx, {})
        if not tmpl:
            continue
        prefix = f"[Containments][{c_id}][Applets][{a_id}]"
        block = tmpl["block"].replace(f"[Applet_{idx}]", prefix)
        filtered.append(block)

    clean = [s.strip() for s in filtered if s.strip()]
    text = "\n\n".join(clean) + "\n"
    with open(appletsrc, "w") as fh:
        fh.write(text)
    print(
        f"✓ Synced {count} {label} widget(s) in {os.path.basename(appletsrc)}"
        f" (kept: {keep_ids}, removed extras: {remove_ids})"
    )

if any_new_ids:
    print("NEEDS_SECOND_RECONFIGURE")
PYEOF
}

plasma_reconfigure() {
    if [[ -z "${CAELESTIA_TEST_MODE:-}" && "$USER_CONFIG_DIR" != "/tmp/"* ]] && command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
        qdbus6 org.kde.plasmashell /PlasmaShell refreshCurrentShell 2>/dev/null || true
    fi
}

remove_kde_applets_live() {
    local plugin_id="$1"
    if [[ -z "${CAELESTIA_TEST_MODE:-}" && "$USER_CONFIG_DIR" != "/tmp/"* ]] && command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
for (var i = 0; i < desktops().length; i++) {
    var ws = desktops()[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === '${plugin_id}') {
            ws[j].remove();
        }
    }
}
" >/dev/null 2>&1 || true
    fi
}

add_kde_applets_live() {
    local conf_path="$1"
    local plugin_id="$2"
    local count="$3"
    shift 3

    if [[ -z "${CAELESTIA_TEST_MODE:-}" && "$USER_CONFIG_DIR" != "/tmp/"* ]] && command -v qdbus6 >/dev/null 2>&1; then
        python3 - "$conf_path" "$plugin_id" "$count" "$@" << 'PYEOF'
import json, re, subprocess, sys, time

conf_path = sys.argv[1]
plugin_id = sys.argv[2]
count = int(sys.argv[3])

custom_geoms = []
if len(sys.argv) >= 12 and sys.argv[4]:
    try:
        custom_geoms = [
            (float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7])),
            (float(sys.argv[8]), float(sys.argv[9]), float(sys.argv[10]), float(sys.argv[11]))
        ]
    except Exception:
        custom_geoms = []

if not custom_geoms:
    sw, sh = 1920.0, 1080.0
    try:
        import shutil
        if shutil.which("kscreen-doctor"):
            out = subprocess.check_output(["kscreen-doctor", "-o"], text=True)
            m = re.search(r"Geometry:\s*\d+,\d+\s+(\d+)x(\d+)", out)
            if m:
                sw, sh = float(m.group(1)), float(m.group(2))
    except Exception:
        pass
    center_gap = round(sw * (224.0 / 1920.0))
    vis_w = (sw - center_gap) / 2.0
    vis_h = round((sh - 56.0) * 0.40)
    vis_y = sh - vis_h - 8.0
    custom_geoms = [
        (0.0, vis_y, vis_w, vis_h),
        (sw - vis_w, vis_y, vis_w, vis_h)
    ]

with open(conf_path, "r") as f:
    text = f.read()

applets_data = []
for idx in range(1, count + 1):
    geom_m = re.search(rf"^\[Applet_{idx}\].*?^geometry=([^\n]+)", text, re.S | re.M)
    if geom_m:
        geom_parts = geom_m.group(1).split(",")
        x, y, w, h = float(geom_parts[0]), float(geom_parts[1]), float(geom_parts[2]), float(geom_parts[3])
    elif idx - 1 < len(custom_geoms):
        x, y, w, h = custom_geoms[idx - 1]
    else:
        x, y, w, h = 0.0, 0.0, 400.0, 300.0

    gen_m = re.search(rf"\[Applet_{idx}\]\[Configuration\]\[General\]\n((?:(?!^\[).)*)", text, re.S | re.M)
    gen_cfg = {}
    if gen_m:
        for line in gen_m.group(1).splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                gen_cfg[k.strip()] = v.strip()

    applets_data.append({"x": x, "y": y, "w": w, "h": h, "config": gen_cfg})

# Check current active widgets in Plasma against last applied target
state_file = "/tmp/plasma-visualizer-last-target.json"
target_key = json.dumps([{"x": a["x"], "y": a["y"], "w": a["w"], "h": a["h"]} for a in applets_data])

js_count = f"""
var count = 0;
for (var d_idx = 0; d_idx < desktops().length; d_idx++) {{
    var ws = desktops()[d_idx].widgets();
    for (var i = 0; i < ws.length; i++) {{
        if (ws[i].type === '{plugin_id}') {{
            count++;
        }}
    }}
}}
print(count);
"""

need_update = True
try:
    cnt_out = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_count],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
    active_count = int(cnt_out) if cnt_out.isdigit() else 0
    last_target = ""
    import os
    if os.path.exists(state_file):
        with open(state_file, "r") as sf:
            last_target = sf.read().strip()
    if active_count == len(applets_data) and last_target == target_key:
        need_update = False
except Exception:
    need_update = True

if need_update:
    # 1. Remove existing widgets
    js_remove = f"""
    var removed = false;
    for (var d_idx = 0; d_idx < desktops().length; d_idx++) {{
        var d = desktops()[d_idx];
        var ws = d.widgets();
        for (var i = 0; i < ws.length; i++) {{
            if (ws[i].type === '{plugin_id}') {{
                ws[i].remove();
                removed = true;
            }}
        }}
    }}
    print(removed ? 'REMOVED' : 'NONE');
    """
    try:
        rm_out = subprocess.check_output(
            ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_remove],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        if "REMOVED" in rm_out:
            # Give Plasma Corona event loop time to delete old widgets from the layout grid to prevent collision displacement
            time.sleep(0.15)
    except Exception:
        pass

    # 2. Add widgets at the target geometry
    js_add = f"""
    var d = desktops()[0];
    var data = {json.dumps(applets_data)};
    for (var i = 0; i < data.length; i++) {{
        var item = data[i];
        var w = d.addWidget('{plugin_id}', item.x, item.y, item.w, item.h);
        if (w) {{
            w.currentConfigGroup = ['General'];
            for (var k in item.config) {{
                w.writeConfig(k, item.config[k]);
            }}
            w.reloadConfig();
        }}
    }}
    """
    try:
        subprocess.run(
            ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_add],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        with open(state_file, "w") as sf:
            sf.write(target_key)
    except Exception:
        pass
PYEOF
    fi
}

set_visualizer_geometry() {
    local x1="${1:-}" y1="${2:-}" w1="${3:-}" h1="${4:-}"
    local x2="${5:-}" y2="${6:-}" w2="${7:-}" h2="${8:-}"
    if [[ -z "$x1" || -z "$x2" ]]; then
        return 0
    fi
    add_kde_applets_live \
        "$CONFIG_DIR/plasma-audio-visualizer.conf" \
        "luisbocanegra.audio.visualizer" \
        "2" \
        "$@"

    sync_kde_applets \
        "$CONFIG_DIR/plasma-audio-visualizer.conf" \
        "$USER_CONFIG_DIR" \
        "luisbocanegra.audio.visualizer" \
        "2" \
        "plasma-audio-visualizer" \
        "$@" >/dev/null 2>&1 || true
}

export_visualizer() {
    echo "Adding plasma-audio-visualizer widgets directly..."
    add_kde_applets_live \
        "$CONFIG_DIR/plasma-audio-visualizer.conf" \
        "luisbocanegra.audio.visualizer" \
        "2" \
        "$@"

    sync_kde_applets \
        "$CONFIG_DIR/plasma-audio-visualizer.conf" \
        "$USER_CONFIG_DIR" \
        "luisbocanegra.audio.visualizer" \
        "2" \
        "plasma-audio-visualizer" \
        "$@" >/dev/null 2>&1 || true
    echo "✓ Plasma audio visualizer enabled"
}

disable_visualizer() {
    echo "Removing plasma-audio-visualizer widgets directly..."
    rm -f "/tmp/plasma-visualizer-last-target.json"
    remove_kde_applets_live "luisbocanegra.audio.visualizer"
    sync_kde_applets \
        "$CONFIG_DIR/plasma-audio-visualizer.conf" \
        "$USER_CONFIG_DIR" \
        "luisbocanegra.audio.visualizer" \
        "0" \
        "plasma-audio-visualizer" >/dev/null 2>&1 || true
    echo "✓ Plasma audio visualizer disabled"
}

configure_visualizer() {
    echo "To configure plasma-audio-visualizer:"
    echo "Right click on desktop -> Edit Mode -> Right click visualizer -> Configure"
}

DO_SKWD=false
VISUALIZER_ACTION=""
VISUALIZER_ARGS=()

if [[ $# -eq 0 ]]; then
    DO_SKWD=true
    VISUALIZER_ACTION="enable"
else
    while [[ $# -gt 0 ]]; do
        case "$1" in
            skwd|skwd-wall|wall|wallpaper|--skwd|--skwd-wall)
                DO_SKWD=true
                shift
                ;;
            visualizer|audio|audio-visualizer|plasma-audio-visualizer|--visualizer|--audio)
                shift
                if [[ $# -gt 0 ]]; then
                    case "$1" in
                        enable|on|sync)
                            VISUALIZER_ACTION="enable"
                            shift
                            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                                VISUALIZER_ARGS+=("$1")
                                shift
                            done
                            ;;
                        geometry|reposition|pos)
                            VISUALIZER_ACTION="geometry"
                            shift
                            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                                VISUALIZER_ARGS+=("$1")
                                shift
                            done
                            ;;
                        disable|off|remove)
                            VISUALIZER_ACTION="disable"
                            shift
                            ;;
                        configure|config|menu)
                            VISUALIZER_ACTION="configure"
                            shift
                            ;;
                        *)
                            VISUALIZER_ACTION="enable"
                            ;;
                    esac
                else
                    VISUALIZER_ACTION="enable"
                fi
                ;;
            enable-visualizer|--enable-visualizer)
                VISUALIZER_ACTION="enable"
                shift
                ;;
            disable-visualizer|--disable-visualizer)
                VISUALIZER_ACTION="disable"
                shift
                ;;
            configure-visualizer|--configure-visualizer)
                VISUALIZER_ACTION="configure"
                shift
                ;;
            all|--all)
                DO_SKWD=true
                VISUALIZER_ACTION="enable"
                shift
                ;;
            -h|--help|help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                show_help >&2
                exit 1
                ;;
        esac
    done
fi

if [[ "$DO_SKWD" == true ]]; then
    export_skwd
fi

if [[ -n "$VISUALIZER_ACTION" ]]; then
    exec 200>"/tmp/plasma-export-config.lock"
    flock -x 200
fi

case "$VISUALIZER_ACTION" in
    enable)
        export_visualizer "${VISUALIZER_ARGS[@]}"
        ;;
    geometry)
        set_visualizer_geometry "${VISUALIZER_ARGS[@]}"
        ;;
    disable)
        disable_visualizer
        ;;
    configure)
        configure_visualizer
        ;;
esac

if [[ "$DO_SKWD" == true ]]; then
    sleep 2
    apply_skwd_wallpaper
fi
