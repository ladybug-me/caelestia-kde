#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/plasma-config"
VISUALIZER_CONFIG_DIR="$CONFIG_DIR/plasma-audio-visualizer"
USER_CONFIG_DIR="${USER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"

normalize_visualizer_profile() {
    local p="${1:-double_reversed}"
    case "${p,,}" in
        user|user_defined|user-defined|"user defined")
            echo "user"
            ;;
        double_reversed|double-reversed|"double reversed"|double|default|"")
            echo "double_reversed"
            ;;
        single)
            echo "single"
            ;;
        circle)
            echo "circle"
            ;;
        *)
            echo "$p"
            ;;
    esac
}

save_user_visualizer_config() {
    python3 - "$USER_CONFIG_DIR" "$CONFIG_DIR/plasma-audio-visualizer/double_reversed.conf" << 'PYEOF'
import os, re, subprocess, sys

config_dir = sys.argv[1]
fallback_tmpl = sys.argv[2]
plugin_id = "luisbocanegra.audio.visualizer"
target_file = os.path.join(config_dir, "caelestia", "plasma-audio-visualizer", "user.conf")

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
        m = re.match(rf"^\[Containments\]\[{c_id}\]\[(?:Applets|DisabledApplets)\]\[(\d+)\]$", hdr)
        if m:
            aid = m.group(1)
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

    blocks = []
    for idx, aid in enumerate(vis_ids, start=1):
        g = c_geoms.get(aid) or saved_geoms.get(aid)
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
            if sl and re.match(rf"^\[Containments\]\[{c_id}\]\[(?:Applets|DisabledApplets)\]\[{aid}\]\[Configuration\]\[General\]$", sl[0].strip()):
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

if found_blocks:
    os.makedirs(os.path.dirname(target_file), exist_ok=True)
    with open(target_file, "w") as fh:
        fh.write("\n\n".join(found_blocks) + "\n")
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
        c="$(grep -c '^\[Applet_[0-9]\+\]$' "$conf_path" 2>/dev/null || echo 0)"
        if [[ "$c" -gt 0 ]]; then
            echo "$c"
            return
        fi
    fi
    echo 2
}


show_help() {
    cat << EOF
Usage: $(basename "$0") [TARGET [ACTION [PROFILE]]]

Exports, configures, or removes Plasma configurations and widgets.
If no target is specified, all configurations are exported.

Targets:
  skwd, skwd-wall, wall       Export skwd-wall-v2 config
  visualizer [enable|disable|configure|geometry] [PROFILE] [GEOM...]
                              Manage plasma-audio-visualizer widgets
                              Profiles: double_reversed (default), user, single, circle
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

# Syncs N applet instances from template or existing configuration into appletsrc files.
# Syncs N applet instances from template or existing configuration into appletsrc files.
# Preserves user-defined configuration when profile is "user" or when visualizer is disabled.
sync_kde_applets() {
    python3 - "$@" << 'PYEOF'
import glob, json, os, re, subprocess, sys

conf_path = sys.argv[1]
config_dir = sys.argv[2]
plugin_id = sys.argv[3]
count = int(sys.argv[4])
label = sys.argv[5]
profile = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else "double_reversed"

custom_geoms = {}
geom_args = sys.argv[7:]
for idx in range(1, (len(geom_args) // 4) + 1):
    base = (idx - 1) * 4
    try:
        gx, gy, gw, gh = geom_args[base:base+4]
        if gx and gy and gw and gh:
            custom_geoms[idx] = f"{gx},{gy},{gw},{gh},0"
    except Exception:
        break

templates = {}
if os.path.exists(conf_path):
    with open(conf_path) as f:
        conf = f.read()
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
cache_file = os.path.join(config_dir, "caelestia", "visualizer-user-cache.conf")

for appletsrc in candidate_files:
    with open(appletsrc, "r") as f:
        text = f.read()

    sections = re.split(r"(?m)(?=^\[)", text)

    c_m = re.search(
        r"\[Containments\]\[(\d+)\](?:(?!\[Containments\]).)*?"
        r"(?:plugin=org\.kde\.desktopcontainment|plugin=org\.kde\.plasma\.folder)",
        text, re.S
    )
    c_id = c_m.group(1) if c_m else "1"

    c_geoms = {}
    for sec in sections:
        lines = sec.strip().splitlines()
        if lines and lines[0].strip() == f"[Containments][{c_id}]":
            for l in lines[1:]:
                if l.startswith("ItemGeometries"):
                    for gm in re.finditer(r"Applet-(\d+):([^;\n]+)", l):
                        c_geoms[gm.group(1)] = gm.group(2)

    active_ids = []
    disabled_ids = []
    all_ids = set()

    for sec in sections:
        lines = sec.strip().splitlines()
        if not lines:
            continue
        hdr = lines[0].strip()
        am = re.match(rf"^\[Containments\]\[{c_id}\]\[Applets\]\[(\d+)\]$", hdr)
        if am:
            aid = int(am.group(1))
            all_ids.add(aid)
            for l in lines[1:]:
                if l.strip() == f"plugin={plugin_id}":
                    if aid not in active_ids:
                        active_ids.append(aid)
                    break
        dm = re.match(rf"^\[Containments\]\[{c_id}\]\[DisabledApplets\]\[(\d+)\]$", hdr)
        if dm:
            aid = int(dm.group(1))
            all_ids.add(aid)
            for l in lines[1:]:
                if l.strip() == f"plugin={plugin_id}":
                    if aid not in disabled_ids:
                        disabled_ids.append(aid)
                    break

    # Disable visualizer (count == 0): move active applets to [DisabledApplets] and strip ItemGeometries
    if count == 0:
        c_header = f"[Containments][{c_id}]"
        all_vis = active_ids + disabled_ids
        for i, sec in enumerate(sections):
            lines = sec.splitlines()
            if lines and lines[0].strip() == c_header:
                c_lines = lines[:]
                for aid in all_vis:
                    for li, line in enumerate(c_lines):
                        if line.startswith("ItemGeometries"):
                            c_lines[li] = re.sub(rf"Applet-{aid}:[^;\n]+;?", "", line)
                sections[i] = "\n".join(c_lines) + "\n\n"
                break

        new_sections = []
        user_blocks_to_cache = []
        for sec in sections:
            lines = sec.splitlines()
            if not lines or not lines[0].startswith("["):
                if sec.strip():
                    new_sections.append(sec)
                continue
            hdr = lines[0].strip()
            renamed = False
            for aid in active_ids:
                pfx = f"[Containments][{c_id}][Applets][{aid}]"
                if hdr == pfx or hdr.startswith(pfx + "["):
                    new_hdr = f"[Containments][{c_id}][DisabledApplets][{aid}]" + hdr[len(pfx):]
                    sec_lines = sec.splitlines()
                    sec_lines[0] = new_hdr
                    if hdr == pfx and str(aid) in c_geoms:
                        sec_lines.append(f"saved_geometry={c_geoms[str(aid)]}")
                    new_sec = "\n".join(sec_lines) + "\n"
                    new_sections.append(new_sec)
                    user_blocks_to_cache.append(sec)
                    renamed = True
                    break
            if not renamed:
                new_sections.append(sec)

        if user_blocks_to_cache and (profile == "user" or not os.path.exists(cache_file)):
            try:
                os.makedirs(os.path.dirname(cache_file), exist_ok=True)
                with open(cache_file, "w") as cf:
                    cf.write("\n\n".join(user_blocks_to_cache) + "\n")
            except Exception:
                pass

        clean = [s.strip() for s in new_sections if s.strip()]
        with open(appletsrc, "w") as fh:
            fh.write("\n\n".join(clean) + "\n")
        print(
            f"✓ Disabled {len(active_ids)} {label} widget(s) in {os.path.basename(appletsrc)}"
            f" (preserved in [DisabledApplets])"
        )
        continue

    # Enable / configure visualizer (count > 0)
    existing_vis_ids = active_ids + [d for d in disabled_ids if d not in active_ids]

    if len(existing_vis_ids) >= count:
        keep_ids = existing_vis_ids[:count]
        disable_ids = existing_vis_ids[count:]
        new_ids = []
    else:
        keep_ids = list(existing_vis_ids)
        disable_ids = []
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

    # 1. Update ItemGeometries in desktop containment
    c_header = f"[Containments][{c_id}]"
    c_found = False
    for i, sec in enumerate(sections):
        lines = sec.splitlines()
        if not lines or lines[0].strip() != c_header:
            continue
        c_found = True
        c_lines = lines[:]
        for idx, aid in enumerate(keep_ids, start=1):
            aid_str = str(aid)
            g = custom_geoms.get(idx, "") or templates.get(idx, {}).get("geom", "") or c_geoms.get(aid_str, "")
            if not g:
                continue

            for gk in ("ItemGeometries-1920x1080", "ItemGeometriesHorizontal"):
                found_key = False
                for li, line in enumerate(c_lines):
                    if line.startswith(f"{gk}="):
                        found_key = True
                        if f"Applet-{aid}:" in line:
                            c_lines[li] = re.sub(
                                rf"Applet-{aid}:[^;\n]+", f"Applet-{aid}:{g}", line
                            )
                        else:
                            sep = "" if line.endswith("=") else ";"
                            c_lines[li] = line.rstrip(";") + f"{sep}Applet-{aid}:{g};"
                if not found_key:
                    c_lines.append(f"{gk}=Applet-{aid}:{g};")

        for rid in disable_ids:
            for li, line in enumerate(c_lines):
                if line.startswith("ItemGeometries"):
                    c_lines[li] = re.sub(rf"Applet-{rid}:[^;\n]+;?", "", line)
        sections[i] = "\n".join(c_lines) + "\n\n"
        break

    if not c_found:
        c_lines = [c_header, "plugin=org.kde.desktopcontainment"]
        for idx, aid in enumerate(keep_ids, start=1):
            aid_str = str(aid)
            g = custom_geoms.get(idx, "") or templates.get(idx, {}).get("geom", "") or c_geoms.get(aid_str, "")
            if g:
                c_lines.append(f"ItemGeometries-1920x1080=Applet-{aid}:{g};")
                c_lines.append(f"ItemGeometriesHorizontal=Applet-{aid}:{g};")
        sections.insert(0, "\n".join(c_lines) + "\n\n")

    # 2. Update sections: strip previous visualizer applet blocks and write clean templates
    new_sections = []
    affected_ids = set(keep_ids + disable_ids)
    for sec in sections:
        lines = sec.splitlines()
        if not lines or not lines[0].startswith("["):
            if sec.strip():
                new_sections.append(sec)
            continue
        hdr = lines[0].strip()
        is_affected = False
        for aid in affected_ids:
            pfx = f"[Containments][{c_id}][Applets][{aid}]"
            dpfx = f"[Containments][{c_id}][DisabledApplets][{aid}]"
            if hdr == pfx or hdr.startswith(pfx + "[") or hdr == dpfx or hdr.startswith(dpfx + "["):
                is_affected = True
                break
        if not is_affected:
            new_sections.append(sec)

    for idx, aid in enumerate(keep_ids, start=1):
        tmpl = templates.get(idx, {})
        if not tmpl:
            continue
        prefix = f"[Containments][{c_id}][Applets][{aid}]"
        block = tmpl["block"].replace(f"[Applet_{idx}]", prefix)
        new_sections.append(block)

    clean = [s.strip() for s in new_sections if s.strip()]
    text = "\n\n".join(clean) + "\n"
    with open(appletsrc, "w") as fh:
        fh.write(text)
    print(
        f"✓ Synced {len(keep_ids)} {label} widget(s) (profile: {profile}) in {os.path.basename(appletsrc)}"
        f" (kept: {keep_ids})"
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
    local profile="${4:-user}"
    local user_cfg_dir="${USER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"
    shift 4

    if [[ -z "${CAELESTIA_TEST_MODE:-}" && "$USER_CONFIG_DIR" != "/tmp/"* ]] && command -v qdbus6 >/dev/null 2>&1; then
        python3 - "$conf_path" "$plugin_id" "$count" "$profile" "$user_cfg_dir" "$@" << 'PYEOF'
import glob, json, os, re, subprocess, sys, time

conf_path = sys.argv[1]
plugin_id = sys.argv[2]
count = int(sys.argv[3])
profile = sys.argv[4]
config_dir = sys.argv[5]

custom_geoms = []
geom_args = sys.argv[6:]
for idx in range(1, (len(geom_args) // 4) + 1):
    base = (idx - 1) * 4
    try:
        gx, gy, gw, gh = geom_args[base:base+4]
        if gx and gy and gw and gh:
            custom_geoms.append((float(gx), float(gy), float(gw), float(gh)))
    except Exception:
        break

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
default_geoms = [
    (0.0, vis_y, vis_w, vis_h),
    (sw - vis_w, vis_y, vis_w, vis_h)
]

tmpl_data = {}
if os.path.exists(conf_path):
    with open(conf_path, "r") as f:
        text = f.read()
    for idx in range(1, count + 1):
        geom_m = re.search(rf"^\[Applet_{idx}\].*?^geometry=([^\n]+)", text, re.S | re.M)
        geom = None
        if geom_m:
            try:
                gp = geom_m.group(1).split(",")
                geom = (float(gp[0]), float(gp[1]), float(gp[2]), float(gp[3]))
            except Exception:
                pass
        gen_m = re.search(rf"\[Applet_{idx}\]\[Configuration\]\[General\]\n((?:(?!^\[).)*)", text, re.S | re.M)
        cfg = {}
        if gen_m:
            for line in gen_m.group(1).splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip()
        tmpl_data[idx] = {"geom": geom, "config": cfg}

applets_data = []
for idx in range(1, count + 1):
    td = tmpl_data.get(idx, {})
    if profile == "user" and td.get("geom") is not None:
        x, y, w, h = td["geom"]
    elif idx - 1 < len(custom_geoms):
        x, y, w, h = custom_geoms[idx - 1]
    elif td.get("geom") is not None:
        x, y, w, h = td["geom"]
    else:
        x, y, w, h = default_geoms[idx - 1] if idx - 1 < len(default_geoms) else (0.0, 0.0, 400.0, 300.0)
    cfg = dict(td.get("config", {}))
    if "desktopWidgetBg" not in cfg:
        cfg["desktopWidgetBg"] = "0"
    if str(cfg.get("fillWave", "")).strip().lower() in ("false", "0"):
        cfg["fillWave"] = "false"
    else:
        cfg["fillWave"] = "true"
    if "hideWhenIdle" not in cfg:
        cfg["hideWhenIdle"] = "true"
    applets_data.append({"x": x, "y": y, "w": w, "h": h, "config": cfg})

state_file = "/tmp/plasma-visualizer-last-target.json"
target_data = {"profile": profile, "applets": applets_data}
target_key = json.dumps(target_data, sort_keys=True)

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
    if os.path.exists(state_file):
        with open(state_file, "r") as sf:
            last_target = sf.read().strip()
    if active_count == len(applets_data) and last_target == target_key:
        need_update = False
except Exception:
    need_update = True

if need_update:
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
            time.sleep(0.15)
    except Exception:
        pass

    js_add = f"""
    var d = desktops()[0];
    var data = {json.dumps(applets_data)};

    // Probe next applet ID by creating an invisible dummy spacer
    var dummy = d.addWidget('org.kde.plasma.panelspacer', -10000, -10000, 1, 1);
    var nextId = dummy ? (dummy.id + 1) : 0;
    if (dummy) {{
        dummy.remove();
    }}

    var createdIds = [];
    for (var i = 0; i < data.length; i++) {{
        var item = data[i];
        var targetId = nextId + i;

        if (nextId > 0) {{
            // Pre-populate KConfigGroup before widget instantiation with fillWave=false
            // so QML never paints frame 0 with an uninitialized wave bounding-box fill flash
            d.currentConfigGroup = ['Applets', String(targetId), 'Configuration', 'General'];
            for (var k in item.config) {{
                if (k !== 'fillWave') {{
                    d.writeConfig(k, item.config[k]);
                }}
            }}
            d.writeConfig('fillWave', false);
            d.currentConfigGroup = ['Applets', String(targetId)];
            d.writeConfig('immutability', 1);
            d.writeConfig('plugin', '{plugin_id}');
        }}

        var w = d.addWidget('{plugin_id}', item.x, item.y, item.w, item.h);
        if (w) {{
            createdIds.push(w.id);
            w.userBackgroundHints = 'NoBackground';
            w.currentConfigGroup = ['General'];
            for (var k in item.config) {{
                if (k !== 'fillWave') {{
                    w.writeConfig(k, item.config[k]);
                }}
            }}
            w.writeConfig('fillWave', false);
            w.reloadConfig();
        }}
    }}
    print(JSON.stringify(createdIds));
    """
    try:
        add_out = subprocess.check_output(
            ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_add],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        created_ids = json.loads(add_out) if add_out.startswith("[") else []

        fill_flags = [
            str(item.get("config", {}).get("fillWave", "true")).strip().lower() not in ("false", "0")
            for item in applets_data
        ]
        if any(fill_flags):
            time.sleep(0.25)
            js_fill = f"""
            var d = desktops()[0];
            var createdIds = {json.dumps(created_ids)};
            var fills = {json.dumps(fill_flags)};
            var ws = d.widgets();
            if (createdIds.length > 0) {{
                for (var i = 0; i < ws.length; i++) {{
                    var idx = createdIds.indexOf(ws[i].id);
                    if (idx !== -1 && fills[idx]) {{
                        ws[i].currentConfigGroup = ['General'];
                        ws[i].writeConfig('fillWave', true);
                        ws[i].reloadConfig();
                    }}
                }}
            }} else {{
                var visWs = [];
                for (var i = 0; i < ws.length; i++) {{
                    if (ws[i].type === '{plugin_id}') visWs.push(ws[i]);
                }}
                for (var i = 0; i < visWs.length && i < fills.length; i++) {{
                    if (fills[i]) {{
                        visWs[i].currentConfigGroup = ['General'];
                        visWs[i].writeConfig('fillWave', true);
                        visWs[i].reloadConfig();
                    }}
                }}
            }}
            """
            subprocess.run(
                ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_fill],
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
    local profile=""
    local -a geoms=()
    parse_visualizer_args profile geoms "$@"
    if [[ ${#geoms[@]} -eq 0 ]]; then
        return 0
    fi

    local conf_path
    conf_path="$(get_visualizer_conf_path "$profile")"
    local count
    count="$(get_visualizer_applet_count "$conf_path" "$profile")"

    add_kde_applets_live \
        "$conf_path" \
        "luisbocanegra.audio.visualizer" \
        "$count" \
        "$profile" \
        "${geoms[@]}"

    sync_kde_applets \
        "$conf_path" \
        "$USER_CONFIG_DIR" \
        "luisbocanegra.audio.visualizer" \
        "$count" \
        "plasma-audio-visualizer" \
        "$profile" \
        "${geoms[@]}" >/dev/null 2>&1 || true
}

export_visualizer() {
    local profile=""
    local -a geoms=()
    parse_visualizer_args profile geoms "$@"

    local prev_profile=""
    if [[ -f "/tmp/plasma-visualizer-last-target.json" ]]; then
        prev_profile="$(python3 -c "import json; print(json.load(open('/tmp/plasma-visualizer-last-target.json')).get('profile', ''))" 2>/dev/null || true)"
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
        "luisbocanegra.audio.visualizer" \
        "$count" \
        "$profile" \
        "${geoms[@]}"

    sync_kde_applets \
        "$conf_path" \
        "$USER_CONFIG_DIR" \
        "luisbocanegra.audio.visualizer" \
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
    rm -f "/tmp/plasma-visualizer-last-target.json"

    # Sync applets to disabled state FIRST so user settings are preserved in desktop-appletsrc
    sync_kde_applets \
        "$conf_path" \
        "$USER_CONFIG_DIR" \
        "luisbocanegra.audio.visualizer" \
        "0" \
        "plasma-audio-visualizer" \
        "$profile" >/dev/null 2>&1 || true

    remove_kde_applets_live "luisbocanegra.audio.visualizer"
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
    # When no args (or startup), respect user configuration
    is_vis_enabled=true
    vis_profile="user"
    if [[ -f "$USER_CONFIG_DIR/caelestia/shell.json" ]]; then
        is_vis_enabled="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")"
        vis_profile="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('profile', 'user')).lower())" 2>/dev/null || echo "user")"
    fi
    VISUALIZER_ARGS=("$vis_profile")
    if [[ "$is_vis_enabled" == "false" ]]; then
        VISUALIZER_ACTION="disable"
    else
        VISUALIZER_ACTION="enable"
    fi
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
                            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                                VISUALIZER_ARGS+=("$1")
                                shift
                            done
                            ;;
                        configure|config|menu)
                            VISUALIZER_ACTION="configure"
                            shift
                            ;;
                        user|user_defined|user-defined|"user defined"|double_reversed|double-reversed|"double reversed"|single|circle)
                            VISUALIZER_ACTION="enable"
                            VISUALIZER_ARGS+=("$1")
                            shift
                            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                                VISUALIZER_ARGS+=("$1")
                                shift
                            done
                            ;;
                        *)
                            VISUALIZER_ACTION="enable"
                            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                                VISUALIZER_ARGS+=("$1")
                                shift
                            done
                            ;;
                    esac
                else
                    VISUALIZER_ACTION="enable"
                fi
                ;;
            enable-visualizer|--enable-visualizer)
                VISUALIZER_ACTION="enable"
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    VISUALIZER_ARGS+=("$1")
                    shift
                done
                ;;
            disable-visualizer|--disable-visualizer)
                VISUALIZER_ACTION="disable"
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    VISUALIZER_ARGS+=("$1")
                    shift
                done
                ;;
            configure-visualizer|--configure-visualizer)
                VISUALIZER_ACTION="configure"
                shift
                ;;
            all|--all)
                DO_SKWD=true
                is_vis_enabled=true
                vis_profile="user"
                if [[ -f "$USER_CONFIG_DIR/caelestia/shell.json" ]]; then
                    is_vis_enabled="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")"
                    vis_profile="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('profile', 'user')).lower())" 2>/dev/null || echo "user")"
                fi
                VISUALIZER_ARGS=("$vis_profile")
                if [[ "$is_vis_enabled" == "false" ]]; then
                    VISUALIZER_ACTION="disable"
                else
                    VISUALIZER_ACTION="enable"
                fi
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
        disable_visualizer "${VISUALIZER_ARGS[@]}"
        ;;
    configure)
        configure_visualizer
        ;;
esac

if [[ "$DO_SKWD" == true ]]; then
    sleep 2
    apply_skwd_wallpaper
fi
