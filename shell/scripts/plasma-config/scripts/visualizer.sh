#!/usr/bin/env bash
# Plasma Audio Visualizer Widget Helper
# Plugin: luisbocanegra.audio.visualizer

VISUALIZER_PLUGIN_ID="luisbocanegra.audio.visualizer"
USER_CONFIG_DIR="${USER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"
CONFIG_DIR="${CONFIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

normalize_visualizer_profile() {
    local raw="${1,,}"
    case "$raw" in
        user|user_defined|user-defined|"user defined")
            echo "user"
            ;;
        single)
            echo "single"
            ;;
        circle)
            echo "circle"
            ;;
        double_reversed|double-reversed|"double reversed"|double|default|*)
            echo "double_reversed"
            ;;
    esac
}

save_user_visualizer_config() {
    python3 - "$USER_CONFIG_DIR" "$CONFIG_DIR/plasma-audio-visualizer/double_reversed.conf" "$VISUALIZER_PLUGIN_ID" << 'PYEOF'
import json, os, re, subprocess, sys

config_dir = sys.argv[1]
fallback_tmpl = sys.argv[2]
plugin_id = sys.argv[3]
target_file = os.path.join(config_dir, "caelestia", "plasma-audio-visualizer", "user.conf")

# Check live visualizer widgets and geometries from Plasma via D-Bus
live_ids = None
live_geoms = {}
try:
    js_live = f"""
    var data = {{}};
    for (var d_idx = 0; d_idx < desktops().length; d_idx++) {{
        var ws = desktops()[d_idx].widgets();
        for (var i = 0; i < ws.length; i++) {{
            if (ws[i].type === '{plugin_id}') {{
                var aid = String(ws[i].id);
                var g = ws[i].geometry;
                data[aid] = [Math.round(g.x), Math.round(g.y), Math.round(g.width), Math.round(g.height)];
            }}
        }}
    }}
    print(JSON.stringify(data));
    """
    out = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_live],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
    if out.startswith("{"):
        live_data = json.loads(out)
        live_ids = list(live_data.keys())
        for k, v in live_data.items():
            live_geoms[k] = (float(v[0]), float(v[1]), float(v[2]), float(v[3]))
except Exception:
    live_ids = None
    live_geoms = {}

if live_ids is not None and len(live_ids) == 0:
    os.makedirs(os.path.dirname(target_file), exist_ok=True)
    with open(target_file, "w") as fh:
        fh.write("# User visualizer configuration\n# No visualizer widgets configured\n")
    sys.exit(0)

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
for name in ["plasma-caelestia.desktop-appletsrc", "plasma-org.kde.plasma.desktop-appletsrc"]:
    p = os.path.join(config_dir, name)
    if os.path.exists(p) and p not in candidate_files:
        candidate_files.append(p)

found_blocks = []
for appletsrc in candidate_files:
    try:
        txt = open(appletsrc).read()
    except Exception:
        continue
    sections = re.split(r"(?m)(?=^\[)", txt)
    c_m = re.search(
        r"\[Containments\]\[(\d+)\](?:(?!\[Containments\]).)*?"
        r"(?:plugin=org\.kde\.desktopcontainment|plugin=org\.kde\.plasma\.folder)",
        txt, re.S
    )
    c_id = c_m.group(1) if c_m else "1"
    c_geoms = {}
    for sec in sections:
        lines = sec.strip().splitlines()
        if lines and lines[0].strip() == f"[Containments][{c_id}]":
            for l in lines[1:]:
                if l.startswith("ItemGeometries"):
                    for gm in re.finditer(r"Applet-(\d+):(-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)", l):
                        c_geoms[gm.group(1)] = (float(gm.group(2)), float(gm.group(3)), float(gm.group(4)), float(gm.group(5)))
    vis_ids = []
    saved_geoms = {}
    for sec in sections:
        lines = sec.strip().splitlines()
        if not lines: continue
        hdr = lines[0].strip()
        m = re.match(rf"^\[Containments\]\[{c_id}\]\[Applets\]\[(\d+)\]$", hdr)
        if m:
            aid = m.group(1)
            if live_ids is not None and aid not in live_ids:
                continue
            for l in lines[1:]:
                if l.strip() == f"plugin={plugin_id}":
                    if aid not in vis_ids:
                        vis_ids.append(aid)
                if l.startswith("saved_geometry="):
                    try:
                        sp = l.split("=", 1)[1].strip().split(",")
                        saved_geoms[aid] = (float(sp[0]), float(sp[1]), float(sp[2]), float(sp[3]))
                    except Exception:
                        pass
    if not vis_ids:
        continue

    vis_ids.sort(key=lambda a: (live_geoms.get(a, c_geoms.get(a, (0,)))[0], a))

    blocks = []
    for idx, aid in enumerate(vis_ids, start=1):
        g = live_geoms.get(aid) or c_geoms.get(aid) or saved_geoms.get(aid)
        geom_str = f"{g[0]},{g[1]},{g[2]},{g[3]},0" if g else ""
        lines = [
            f"[Applet_{idx}]",
            f"geometry={geom_str}" if geom_str else "",
            "immutability=1",
            f"plugin={plugin_id}",
            "",
            f"[Applet_{idx}][Configuration]",
            "popupHeight=450",
            "popupWidth=450",
            "",
            f"[Applet_{idx}][Configuration][ConfigDialog]",
            "DialogHeight=630",
            "DialogWidth=810",
            "",
            f"[Applet_{idx}][Configuration][General]"
        ]
        lines = [l for l in lines if l != ""]
        cfg_lines = []
        for sec in sections:
            sl = sec.strip().splitlines()
            if sl and re.match(rf"^\[Containments\]\[{c_id}\]\[Applets\]\[{aid}\]\[Configuration\]\[General\]$", sl[0].strip()):
                for l in sl[1:]:
                    l = l.strip()
                    if l and not l.startswith("#") and "=" in l:
                        cfg_lines.append(l)
                break
        if cfg_lines:
            lines.extend(cfg_lines)
        blocks.append("\n".join(lines))

    if blocks:
        found_blocks = blocks
        break

os.makedirs(os.path.dirname(target_file), exist_ok=True)
with open(target_file, "w") as fh:
    if found_blocks:
        fh.write("\n\n".join(found_blocks) + "\n")
    else:
        fh.write("# User visualizer configuration\n# No visualizer widgets configured\n")
PYEOF
}

snapshot_visualizer_config() {
    python3 - "$USER_CONFIG_DIR" "$VISUALIZER_PLUGIN_ID" << 'PYEOF'
import json, os, re, subprocess, sys

config_dir = sys.argv[1]
plugin_id = sys.argv[2]
snapshot_file = "/tmp/plasma-visualizer-editmode-snapshot.json"


live_data = {}
try:
    js_live = f"""
    var data = {{}};
    for (var d_idx = 0; d_idx < desktops().length; d_idx++) {{
        var ws = desktops()[d_idx].widgets();
        for (var i = 0; i < ws.length; i++) {{
            if (ws[i].type === '{plugin_id}') {{
                var aid = String(ws[i].id);
                var g = ws[i].geometry;
                data[aid] = [Math.round(g.x), Math.round(g.y), Math.round(g.width), Math.round(g.height)];
            }}
        }}
    }}
    print(JSON.stringify(data));
    """
    out = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_live],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
    if out.startswith("{"):
        live_data = json.loads(out)
except Exception:
    pass

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
for name in ["plasma-caelestia.desktop-appletsrc", "plasma-org.kde.plasma.desktop-appletsrc"]:
    p = os.path.join(config_dir, name)
    if os.path.exists(p) and p not in candidate_files:
        candidate_files.append(p)

widget_configs = {}
for appletsrc in candidate_files:
    try:
        txt = open(appletsrc).read()
    except Exception:
        continue
    sections = re.split(r"(?m)(?=^\[)", txt)
    for sec in sections:
        sl = sec.strip().splitlines()
        if not sl: continue
        hdr = sl[0].strip()
        m = re.match(r"^\[Containments\]\[\d+\]\[Applets\]\[(\d+)\]\[Configuration\]\[General\]$", hdr)
        if m:
            aid = m.group(1)
            if aid in live_data and aid not in widget_configs:
                cfg = {}
                for l in sl[1:]:
                    l = l.strip()
                    if l and not l.startswith("#") and "=" in l:
                        k, v = l.split("=", 1)
                        cfg[k.strip()] = v.strip()
                widget_configs[aid] = cfg

items = []
for aid, geom in live_data.items():
    items.append({
        "id": aid,
        "geom": geom,
        "config": widget_configs.get(aid, {})
    })
items.sort(key=lambda w: (w["geom"][0], w["geom"][1], w["id"]))

with open(snapshot_file, "w") as f:
    json.dump(items, f, indent=2, sort_keys=True)
print("SNAPSHOT_SAVED")
PYEOF
}

check_visualizer_edit_mode_changes() {
    python3 - "$USER_CONFIG_DIR" "$CONFIG_DIR/plasma-audio-visualizer/double_reversed.conf" "$VISUALIZER_PLUGIN_ID" << 'PYEOF'
import json, os, re, subprocess, sys

config_dir = sys.argv[1]
fallback_tmpl = sys.argv[2]
plugin_id = sys.argv[3]
snapshot_file = "/tmp/plasma-visualizer-editmode-snapshot.json"
target_file = os.path.join(config_dir, "caelestia", "plasma-audio-visualizer", "user.conf")


# If no snapshot was taken before entering edit mode, we cannot ascertain changes
if not os.path.exists(snapshot_file):
    print("STATUS_UNCHANGED")
    sys.exit(0)

try:
    with open(snapshot_file, "r") as f:
        snap_items = json.load(f)
except Exception:
    snap_items = None
finally:
    try:
        os.remove(snapshot_file)
    except Exception:
        pass

if not isinstance(snap_items, list):
    print("STATUS_UNCHANGED")
    sys.exit(0)

# Query live widgets
live_data = {}
try:
    js_live = f"""
    var data = {{}};
    for (var d_idx = 0; d_idx < desktops().length; d_idx++) {{
        var ws = desktops()[d_idx].widgets();
        for (var i = 0; i < ws.length; i++) {{
            if (ws[i].type === '{plugin_id}') {{
                var aid = String(ws[i].id);
                var g = ws[i].geometry;
                data[aid] = [Math.round(g.x), Math.round(g.y), Math.round(g.width), Math.round(g.height)];
            }}
        }}
    }}
    print(JSON.stringify(data));
    """
    out = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_live],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
    if out.startswith("{"):
        live_data = json.loads(out)
except Exception:
    pass

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
for name in ["plasma-caelestia.desktop-appletsrc", "plasma-org.kde.plasma.desktop-appletsrc"]:
    p = os.path.join(config_dir, name)
    if os.path.exists(p) and p not in candidate_files:
        candidate_files.append(p)

widget_configs = {}
for appletsrc in candidate_files:
    try:
        txt = open(appletsrc).read()
    except Exception:
        continue
    sections = re.split(r"(?m)(?=^\[)", txt)
    for sec in sections:
        sl = sec.strip().splitlines()
        if not sl: continue
        hdr = sl[0].strip()
        m = re.match(r"^\[Containments\]\[\d+\]\[Applets\]\[(\d+)\]\[Configuration\]\[General\]$", hdr)
        if m:
            aid = m.group(1)
            if aid in live_data and aid not in widget_configs:
                cfg = {}
                for l in sl[1:]:
                    l = l.strip()
                    if l and not l.startswith("#") and "=" in l:
                        k, v = l.split("=", 1)
                        cfg[k.strip()] = v.strip()
                widget_configs[aid] = cfg

current_items = []
for aid, geom in live_data.items():
    current_items.append({
        "id": aid,
        "geom": geom,
        "config": widget_configs.get(aid, {})
    })
current_items.sort(key=lambda w: (w["geom"][0], w["geom"][1], w["id"]))

snap_by_id = {s["id"]: s for s in snap_items if isinstance(s, dict) and "id" in s}
cur_by_id = {c["id"]: c for c in current_items}

changed = False
if set(snap_by_id.keys()) != set(cur_by_id.keys()):
    changed = True
else:
    for aid, cur in cur_by_id.items():
        snp = snap_by_id[aid]
        cg = cur.get("geom", [0, 0, 0, 0])
        sg = snp.get("geom", [0, 0, 0, 0])
        if any(abs(c - s) > 2 for c, s in zip(cg, sg)):
            changed = True
            break
        if cur.get("config", {}) != snp.get("config", {}):
            changed = True
            break

if not changed:
    print("STATUS_UNCHANGED")
    sys.exit(0)

# Save changed state to user.conf
os.makedirs(os.path.dirname(target_file), exist_ok=True)
if not current_items:
    with open(target_file, "w") as fh:
        fh.write("# User visualizer configuration\n# No visualizer widgets configured\n")
else:
    blocks = []
    for idx, item in enumerate(current_items, start=1):
        g = item["geom"]
        geom_str = f"{g[0]},{g[1]},{g[2]},{g[3]},0"
        lines = [
            f"[Applet_{idx}]",
            f"geometry={geom_str}",
            "immutability=1",
            f"plugin={plugin_id}",
            "",
            f"[Applet_{idx}][Configuration]",
            "popupHeight=450",
            "popupWidth=450",
            "",
            f"[Applet_{idx}][Configuration][ConfigDialog]",
            "DialogHeight=630",
            "DialogWidth=810",
            "",
            f"[Applet_{idx}][Configuration][General]"
        ]
        cfg = item["config"]
        for k in sorted(cfg.keys()):
            lines.append(f"{k}={cfg[k]}")
        blocks.append("\n".join(lines))
    with open(target_file, "w") as fh:
        fh.write("\n\n".join(blocks) + "\n")

# Update last-target state so profile switch won't flicker
safe_plugin = re.sub(r'[^a-zA-Z0-9_-]', '_', plugin_id)
state_file = f"/tmp/plasma-{safe_plugin}-last-target.json"
applets_data = []
for item in current_items:
    g = item["geom"]
    cfg = dict(item["config"])
    if "desktopWidgetBg" not in cfg:
        cfg["desktopWidgetBg"] = "0"
    if str(cfg.get("fillWave", "")).strip().lower() in ("false", "0"):
        cfg["fillWave"] = "false"
    else:
        cfg["fillWave"] = "true"
    if "hideWhenIdle" not in cfg:
        cfg["hideWhenIdle"] = "false"
    applets_data.append({"x": float(g[0]), "y": float(g[1]), "w": float(g[2]), "h": float(g[3]), "config": cfg})

try:
    with open(state_file, "w") as sf:
        sf.write(json.dumps({"profile": "user", "applets": applets_data}, sort_keys=True))
except Exception:
    pass

print("STATUS_CHANGED")
PYEOF
}

get_visualizer_conf_path() {
    local profile="$1"
    local user_p_conf="$USER_CONFIG_DIR/caelestia/plasma-audio-visualizer/${profile}.conf"
    local sys_p_conf="$CONFIG_DIR/plasma-audio-visualizer/${profile}.conf"

    if [[ "$profile" == "user" ]]; then
        if [[ -f "$user_p_conf" ]]; then
            echo "$user_p_conf"
            return
        fi
        save_user_visualizer_config
        if [[ -f "$user_p_conf" ]]; then
            echo "$user_p_conf"
            return
        fi
        echo "$CONFIG_DIR/plasma-audio-visualizer/double_reversed.conf"
        return
    fi

    if [[ -f "$sys_p_conf" ]]; then
        echo "$sys_p_conf"
    elif [[ -f "$user_p_conf" ]]; then
        echo "$user_p_conf"
    elif [[ -f "$CONFIG_DIR/plasma-audio-visualizer/double_reversed.conf" ]]; then
        echo "$CONFIG_DIR/plasma-audio-visualizer/double_reversed.conf"
    else
        echo ""
    fi
}

parse_visualizer_args() {
    local -n out_profile="$1"
    local -n out_geoms="$2"
    shift 2

    local default_profile="double_reversed"
    if [[ -f "$USER_CONFIG_DIR/caelestia/shell.json" ]]; then
        local cfg_prof
        cfg_prof="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('profile', '')).lower())" 2>/dev/null || true)"
        if [[ -n "$cfg_prof" ]]; then
            default_profile="$(normalize_visualizer_profile "$cfg_prof")"
        fi
    fi

    out_profile="$default_profile"
    out_geoms=()

    if [[ $# -gt 0 ]]; then
        local first="$1"
        case "${first,,}" in
            user|user_defined|user-defined|"user defined"|double_reversed|double-reversed|"double reversed"|double|default|single|circle)
                out_profile="$(normalize_visualizer_profile "$first")"
                shift
                ;;
            *)
                if ! [[ "$first" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                    out_profile="$(normalize_visualizer_profile "$first")"
                    shift
                fi
                ;;
        esac
    fi
    out_geoms=("$@")
}

get_visualizer_applet_count() {
    local conf_path="$1"
    local profile="${2:-double_reversed}"

    if [[ -f "$conf_path" ]]; then
        local c
        c="$(grep -c '^\[Applet_[0-9]\+\]$' "$conf_path" 2>/dev/null || true)"
        c="${c:-0}"
        if [[ "$profile" == "user" ]]; then
            echo "$c"
            return
        fi
        if [[ "$c" -gt 0 ]]; then
            echo "$c"
            return
        fi
    fi
    echo 2
}

set_visualizer_geometry() {
    local profile=""
    local -a geoms=()
    parse_visualizer_args profile geoms "$@"

    local conf_path
    conf_path="$(get_visualizer_conf_path "$profile")"
    local count
    count="$(get_visualizer_applet_count "$conf_path" "$profile")"

    add_kde_applets_live \
        "$conf_path" \
        "$VISUALIZER_PLUGIN_ID" \
        "$count" \
        "$profile" \
        "${geoms[@]}"

    sync_kde_applets \
        "$conf_path" \
        "$USER_CONFIG_DIR" \
        "$VISUALIZER_PLUGIN_ID" \
        "$count" \
        "plasma-audio-visualizer" \
        "$profile" \
        "${geoms[@]}" >/dev/null 2>&1 || true
}

export_visualizer() {
    local profile=""
    local -a geoms=()
    parse_visualizer_args profile geoms "$@"

    local safe_plugin
    safe_plugin="$(echo "$VISUALIZER_PLUGIN_ID" | tr -c 'a-zA-Z0-9_-' '_')"
    local state_file="/tmp/plasma-${safe_plugin}-last-target.json"

    local prev_profile=""
    if [[ -f "$state_file" ]]; then
        prev_profile="$(python3 -c "import json; print(json.load(open('$state_file')).get('profile', ''))" 2>/dev/null || true)"
    fi
    if [[ "$prev_profile" == "user" && "$profile" != "user" ]]; then
        save_user_visualizer_config
    fi

    local conf_path
    conf_path="$(get_visualizer_conf_path "$profile")"
    local count
    count="$(get_visualizer_applet_count "$conf_path" "$profile")"

    echo "Adding plasma-audio-visualizer widgets directly (profile: $profile, count: $count)..."
    add_kde_applets_live \
        "$conf_path" \
        "$VISUALIZER_PLUGIN_ID" \
        "$count" \
        "$profile" \
        "${geoms[@]}"

    sync_kde_applets \
        "$conf_path" \
        "$USER_CONFIG_DIR" \
        "$VISUALIZER_PLUGIN_ID" \
        "$count" \
        "plasma-audio-visualizer" \
        "$profile" \
        "${geoms[@]}" >/dev/null 2>&1 || true
    echo "✓ Plasma audio visualizer enabled ($profile)"
}

disable_visualizer() {
    local profile=""
    local -a geoms=()
    parse_visualizer_args profile geoms "$@"

    if [[ "$profile" == "user" ]]; then
        save_user_visualizer_config
    fi

    local conf_path
    conf_path="$(get_visualizer_conf_path "$profile")"

    echo "Removing plasma-audio-visualizer widgets directly..."
    local safe_plugin
    safe_plugin="$(echo "$VISUALIZER_PLUGIN_ID" | tr -c 'a-zA-Z0-9_-' '_')"
    rm -f "/tmp/plasma-${safe_plugin}-last-target.json"

    sync_kde_applets \
        "$conf_path" \
        "$USER_CONFIG_DIR" \
        "$VISUALIZER_PLUGIN_ID" \
        "0" \
        "plasma-audio-visualizer" \
        "$profile" >/dev/null 2>&1 || true

    remove_kde_applets_live "$VISUALIZER_PLUGIN_ID"
    echo "✓ Plasma audio visualizer disabled"
}

configure_visualizer() {
    echo "To configure plasma-audio-visualizer:"
    echo "Right click on desktop -> Edit Mode -> Right click visualizer -> Configure"
}

handle_visualizer_command() {
    local action="${1:-enable}"
    shift || true

    case "$action" in
        enable|on|sync)
            export_visualizer "$@"
            ;;
        geometry|reposition|pos)
            set_visualizer_geometry "$@"
            ;;
        disable|off|remove)
            disable_visualizer "$@"
            ;;
        configure|config|menu)
            configure_visualizer
            ;;
        snapshot)
            snapshot_visualizer_config
            ;;
        check-edit-mode|check_edit_mode)
            check_visualizer_edit_mode_changes
            ;;
        user|user_defined|user-defined|"user defined"|double_reversed|double-reversed|"double reversed"|single|circle)
            export_visualizer "$action" "$@"
            ;;
        *)
            export_visualizer "$action" "$@"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _MAIN_SCRIPT="$(cd "$_SCRIPT_DIR/../.." && pwd)/export-plasma-config.sh"
    if [[ -f "$_MAIN_SCRIPT" ]]; then
        exec bash "$_MAIN_SCRIPT" visualizer "$@"
    fi
    handle_visualizer_command "$@"
fi
