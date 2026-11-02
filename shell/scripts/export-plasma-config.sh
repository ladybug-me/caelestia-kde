#!/usr/bin/env bash
# Plasma Configuration & Widget Management Tool

# General tool for KDE Plasma desktop widget interaction, configuration export,
# and desktop layout synchronization. Supports both direct generic plasma widget
# interactions and modular per-widget helper extensions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CAELESTIA_CONFIG_DIR:-$SCRIPT_DIR/plasma-config}"
USER_CONFIG_DIR="${CAELESTIA_USER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"
WIDGETS_DIR="${CONFIG_DIR}/scripts"

# Source modular widget helpers
if [[ -d "$WIDGETS_DIR" ]]; then
    for mod in "$WIDGETS_DIR"/*.sh; do
        if [[ -f "$mod" ]]; then
            # shellcheck source=/dev/null
            source "$mod"
        fi
    done
elif [[ -d "$SCRIPT_DIR/plasma-config/scripts" ]]; then
    for mod in "$SCRIPT_DIR/plasma-config/scripts"/*.sh; do
        if [[ -f "$mod" ]]; then
            # shellcheck source=/dev/null
            source "$mod"
        fi
    done
fi

# General Plasma Desktop & Applet Helpers

get_plasma_shell_pkg() {
    local shell_pkg=""
    shell_pkg="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.shell 2>/dev/null || true)"
    echo "${shell_pkg:-org.kde.plasma.desktop}"
}

get_candidate_appletsrc_files() {
    local config_dir="${1:-$USER_CONFIG_DIR}"
    local shell_pkg
    shell_pkg="$(get_plasma_shell_pkg)"

    local -a files=()
    if [[ -n "$shell_pkg" && -f "$config_dir/plasma-${shell_pkg}-appletsrc" ]]; then
        files+=("$config_dir/plasma-${shell_pkg}-appletsrc")
    fi
    for name in "plasma-caelestia.desktop-appletsrc" "plasma-org.kde.plasma.desktop-appletsrc"; do
        local p="$config_dir/$name"
        if [[ -f "$p" && ! " ${files[*]} " =~ " ${p} " ]]; then
            files+=("$p")
        fi
    done
    for f in "$config_dir"/*desktop-appletsrc; do
        if [[ -f "$f" && ! " ${files[*]} " =~ " ${f} " ]]; then
            files+=("$f")
        fi
    done
    printf '%s\n' "${files[@]}"
}

get_desktop_containment_id() {
    local appletsrc="$1"
    python3 - "$appletsrc" << 'PYEOF'
import re, sys
try:
    txt = open(sys.argv[1]).read()
    c_m = re.search(
        r"\[Containments\]\[(\d+)\](?:(?!\[Containments\]).)*?"
        r"(?:plugin=org\.kde\.desktopcontainment|plugin=org\.kde\.plasma\.folder)",
        txt, re.S
    )
    print(c_m.group(1) if c_m else "1")
except Exception:
    print("1")
PYEOF
}

get_live_plasma_widgets() {
    local plugin_id="${1:-}"
    python3 - "$plugin_id" << 'PYEOF'
import json, subprocess, sys
plugin_id = sys.argv[1]
js = f"""
var data = {{}};
for (var d_idx = 0; d_idx < desktops().length; d_idx++) {{
    var ws = desktops()[d_idx].widgets();
    for (var i = 0; i < ws.length; i++) {{
        if (!'{plugin_id}' || ws[i].type === '{plugin_id}') {{
            var aid = String(ws[i].id);
            var g = ws[i].geometry;
            data[aid] = {{
                "type": ws[i].type,
                "x": Math.round(g.x),
                "y": Math.round(g.y),
                "width": Math.round(g.width),
                "height": Math.round(g.height)
            }};
        }}
    }}
}}
print(JSON.stringify(data));
"""
try:
    out = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
    print(out if out.startswith("{") else "{}")
except Exception:
    print("{}")
PYEOF
}

get_widget_applet_count() {
    local conf_path="$1"
    local default_count="${2:-1}"

    if [[ -f "$conf_path" ]]; then
        local c
        c="$(grep -c '^\[Applet_[0-9]\+\]$' "$conf_path" 2>/dev/null || true)"
        c="${c:-0}"
        if [[ "$c" -gt 0 ]]; then
            echo "$c"
            return
        fi
    fi
    echo "$default_count"
}

# Generic Plasma Applet Synchronization & Live Operations

# Syncs N applet instances from template or existing configuration into appletsrc files.
sync_kde_applets() {
    python3 - "$@" << 'PYEOF'
import glob, json, os, re, subprocess, sys

conf_path = sys.argv[1]
config_dir = sys.argv[2]
plugin_id = sys.argv[3]
count = int(sys.argv[4])
label = sys.argv[5]
profile = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else "default"

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
cache_file = os.path.join(config_dir, "caelestia", f"{label}-user-cache.conf")

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

        m = re.match(rf"^\[Containments\]\[{c_id}\]\[Applets\]\[(\d+)\]$", hdr)
        if m:
            aid = int(m.group(1))
            all_ids.add(aid)
            for l in lines[1:]:
                if l.strip() == f"plugin={plugin_id}":
                    if aid not in active_ids:
                        active_ids.append(aid)
                    break

        m_dis = re.match(rf"^\[Containments\]\[{c_id}\]\[DisabledApplets\]\[(\d+)\]$", hdr)
        if m_dis:
            aid = int(m_dis.group(1))
            all_ids.add(aid)
            for l in lines[1:]:
                if l.strip() == f"plugin={plugin_id}":
                    if aid not in disabled_ids:
                        disabled_ids.append(aid)
                    break

    # Disable widgets (count == 0): move active applets to [DisabledApplets] and strip ItemGeometries
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

    # Enable / configure widgets (count > 0)
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

    def get_screen_resolution():
        try:
            js_res = "var d = desktops()[0]; print(Math.round(d.geometry.width) + 'x' + Math.round(d.geometry.height));"
            out = subprocess.check_output(
                ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_res],
                text=True, stderr=subprocess.DEVNULL
            ).strip()
            if "x" in out:
                w_str, h_str = out.split("x", 1)
                w, h = float(w_str), float(h_str)
                if w > 0 and h > 0:
                    return w, h
        except Exception:
            pass
        try:
            out = subprocess.check_output(["kscreen-doctor", "-o"], text=True, stderr=subprocess.DEVNULL)
            m = re.search(r"Geometry:\s*\d+,\d+\s+(\d+)x(\d+)", out)
            if m:
                return float(m.group(1)), float(m.group(2))
        except Exception:
            pass
        return 1920.0, 1080.0

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

    screen_w, screen_h = get_screen_resolution()
    screen_w_int = int(round(screen_w))
    screen_h_int = int(round(screen_h))
    default_geoms_sync = compute_default_geoms(screen_w, screen_h, count)

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
            dg = default_geoms_sync[idx - 1] if idx - 1 < len(default_geoms_sync) else None
            dg_str = f"{dg[0]},{dg[1]},{dg[2]},{dg[3]},0" if dg else ""
            if profile == "user":
                g = custom_geoms.get(idx, "") or templates.get(idx, {}).get("geom", "") or c_geoms.get(aid_str, "") or dg_str
            else:
                g = custom_geoms.get(idx, "") or dg_str or templates.get(idx, {}).get("geom", "") or c_geoms.get(aid_str, "")
            if not g:
                continue

            for gk in (f"ItemGeometries-{screen_w_int}x{screen_h_int}", "ItemGeometriesHorizontal"):
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
            dg = default_geoms_sync[idx - 1] if idx - 1 < len(default_geoms_sync) else None
            dg_str = f"{dg[0]},{dg[1]},{dg[2]},{dg[3]},0" if dg else ""
            if profile == "user":
                g = custom_geoms.get(idx, "") or templates.get(idx, {}).get("geom", "") or c_geoms.get(aid_str, "") or dg_str
            else:
                g = custom_geoms.get(idx, "") or dg_str or templates.get(idx, {}).get("geom", "") or c_geoms.get(aid_str, "")
            if g:
                c_lines.append(f"ItemGeometries-{screen_w_int}x{screen_h_int}=Applet-{aid}:{g};")
                c_lines.append(f"ItemGeometriesHorizontal=Applet-{aid}:{g};")
        sections.insert(0, "\n".join(c_lines) + "\n\n")

    # 2. Update sections: strip previous applet blocks and write clean templates
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

    print(f"✓ Synchronized {count} {label} widget(s) in {os.path.basename(appletsrc)} (IDs: {keep_ids})")
PYEOF
}

# Live widget manipulation in Plasmashell via evaluateScript.
add_kde_applets_live() {
    local conf_path="$1"
    local plugin_id="$2"
    local count="${3:-1}"
    local profile="${4:-default}"
    shift 4 || true
    local -a geom_args=("$@")

    local test_mode=false
    if [[ -n "${CAELESTIA_TEST_MODE:-}" || "$USER_CONFIG_DIR" == "/tmp/"* ]]; then
        test_mode=true
    fi

    if [[ "$test_mode" == true ]]; then
        return 0
    fi

    if ! command -v qdbus6 >/dev/null 2>&1; then
        return 0
    fi

    python3 - "$conf_path" "$plugin_id" "$count" "$profile" "${geom_args[@]}" << 'PYEOF'
import json, os, re, subprocess, sys, time

conf_path = sys.argv[1]
plugin_id = sys.argv[2]
count = int(sys.argv[3])
profile = sys.argv[4]
geom_args = sys.argv[5:]

custom_geoms = []
for idx in range(0, len(geom_args), 4):
    try:
        gx, gy, gw, gh = geom_args[idx:idx+4]
        if gx and gy and gw and gh:
            custom_geoms.append((float(gx), float(gy), float(gw), float(gh)))
    except Exception:
        break

def get_screen_resolution():
    try:
        js_res = "var d = desktops()[0]; print(Math.round(d.geometry.width) + 'x' + Math.round(d.geometry.height));"
        out = subprocess.check_output(
            ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_res],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        if "x" in out:
            w_str, h_str = out.split("x", 1)
            w, h = float(w_str), float(h_str)
            if w > 0 and h > 0:
                return w, h
    except Exception:
        pass
    try:
        out = subprocess.check_output(["kscreen-doctor", "-o"], text=True, stderr=subprocess.DEVNULL)
        m = re.search(r"Geometry:\s*\d+,\d+\s+(\d+)x(\d+)", out)
        if m:
            return float(m.group(1)), float(m.group(2))
    except Exception:
        pass
    return 1920.0, 1080.0

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

screen_w, screen_h = get_screen_resolution()
default_geoms = compute_default_geoms(screen_w, screen_h, count)

tmpl_data = {}
if os.path.exists(conf_path):
    with open(conf_path) as f:
        conf = f.read()
    for block in re.split(r"(?m)(?=^\[Applet_\d+\]$)", conf):
        lines = block.strip().splitlines()
        if not lines:
            continue
        m = re.match(r"^\[Applet_(\d+)\]$", lines[0])
        if not m:
            continue
        idx = int(m.group(1))
        geom = None
        for line in lines:
            if line.startswith("geometry="):
                parts = line.split("=", 1)[1].strip().split(",")
                if len(parts) >= 4:
                    try:
                        geom = (float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
                    except Exception:
                        pass
                break
        cfg = {}
        in_gen = False
        for line in lines:
            if line.strip() == f"[Applet_{idx}][Configuration][General]":
                in_gen = True
                continue
            elif in_gen and line.strip().startswith("["):
                in_gen = False
            elif in_gen:
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
    elif profile != "user" and idx - 1 < len(default_geoms):
        x, y, w, h = default_geoms[idx - 1]
    elif td.get("geom") is not None:
        x, y, w, h = td["geom"]
    else:
        x, y, w, h = default_geoms[idx - 1] if idx - 1 < len(default_geoms) else (0.0, 0.0, 400.0, 300.0)
    cfg = dict(td.get("config", {}))
    if "desktopWidgetBg" not in cfg:
        cfg["desktopWidgetBg"] = "0"
    if "fillWave" not in cfg:
        cfg["fillWave"] = "true"
    if "hideWhenIdle" not in cfg:
        cfg["hideWhenIdle"] = "false"
    applets_data.append({"x": x, "y": y, "w": w, "h": h, "config": cfg})

safe_plugin = re.sub(r'[^a-zA-Z0-9_-]', '_', plugin_id)
state_file = f"/tmp/plasma-{safe_plugin}-last-target.json"
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
        subprocess.check_output(
            ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_remove],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
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
                    var valPre = item.config[k];
                    if (k === 'eq' && typeof valPre === 'string' && valPre.indexOf(',') !== -1) {{
                        valPre = valPre.split(',');
                    }}
                    d.writeConfig(k, valPre);
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
                    var val = item.config[k];
                    if (k === 'eq' && typeof val === 'string' && val.indexOf(',') !== -1) {{
                        val = val.split(',');
                    }}
                    w.writeConfig(k, val);
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
            str(item.get("config", {}).get("fillWave", "")).lower() in ("true", "1")
            for item in applets_data
        ]
        if any(fill_flags):
            time.sleep(0.3)
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
}

# Removes all live widgets of the given plugin_id from all Plasma desktops.
remove_kde_applets_live() {
    local plugin_id="$1"

    local test_mode=false
    if [[ -n "${CAELESTIA_TEST_MODE:-}" || "$USER_CONFIG_DIR" == "/tmp/"* ]]; then
        test_mode=true
    fi

    if [[ "$test_mode" == true ]]; then
        return 0
    fi

    if ! command -v qdbus6 >/dev/null 2>&1; then
        return 0
    fi

    local safe_plugin
    safe_plugin="$(echo "$plugin_id" | tr -c 'a-zA-Z0-9_-' '_')"
    rm -f "/tmp/plasma-${safe_plugin}-last-target.json"

    python3 - "$plugin_id" << 'PYEOF'
import subprocess, sys

plugin_id = sys.argv[1]
js = f"""
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
    subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
except Exception:
    pass
PYEOF
}


# General Applet CLI Command Handler


handle_general_applet_command() {
    local subcmd="${1:-list}"
    shift || true

    case "$subcmd" in
        list)
            local plugin="${1:-}"
            get_live_plasma_widgets "$plugin"
            ;;
        add)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $(basename "$0") applet add <PLUGIN_ID> <CONF_PATH> <COUNT> [PROFILE] [GEOM...]" >&2
                return 1
            fi
            local plugin_id="$1"
            local conf_path="$2"
            local count="$3"
            local profile="${4:-default}"
            shift 4 || shift $#
            add_kde_applets_live "$conf_path" "$plugin_id" "$count" "$profile" "$@"
            ;;
        remove|rm|del)
            if [[ $# -lt 1 ]]; then
                echo "Usage: $(basename "$0") applet remove <PLUGIN_ID>" >&2
                return 1
            fi
            remove_kde_applets_live "$1"
            ;;
        sync)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $(basename "$0") applet sync <CONF_PATH> <PLUGIN_ID> <COUNT> [LABEL] [PROFILE] [GEOM...]" >&2
                return 1
            fi
            local conf_path="$1"
            local plugin_id="$2"
            local count="$3"
            local label="${4:-applet}"
            local profile="${5:-default}"
            shift 5 || shift $#
            sync_kde_applets "$conf_path" "$USER_CONFIG_DIR" "$plugin_id" "$count" "$label" "$profile" "$@"
            ;;
        *)
            echo "Unknown applet subcommand: $subcmd" >&2
            echo "Available: list, add, remove, sync" >&2
            return 1
            ;;
    esac
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [TARGET [ACTION [ARGS...]]]

General tool for Plasma widget interactions, configuration export, and synchronization.

Generic Plasma Widget Commands:
  applet list [PLUGIN_ID]                             List live desktop widgets (JSON)
  applet add <PLUGIN_ID> <CONF_PATH> <COUNT> [ARGS]   Add & position widgets live in Plasma
  applet remove <PLUGIN_ID>                           Remove all live widgets of plugin
  applet sync <CONF_PATH> <PLUGIN_ID> <COUNT> [ARGS]  Sync widget sections in appletsrc

Target Modules:
  visualizer [enable|disable|geometry|configure|snapshot|check-edit-mode] [PROFILE] [GEOM...]
                                                      Manage audio visualizer widgets
  skwd, skwd-wall, wall                               Export and apply skwd-wall-v2 config
  all                                                 Export and apply all configs (default)

Options:
  -h, --help                                          Show this help message
EOF
}


# CLI Entry Point & Dispatcher

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
DO_SKWD=false
VISUALIZER_ACTION=""
VISUALIZER_ARGS=()
APPLET_ARGS=()

if [[ $# -eq 0 ]]; then
    DO_SKWD=true
    is_vis_enabled=true
    vis_profile="double_reversed"
    if [[ -f "$USER_CONFIG_DIR/caelestia/shell.json" ]]; then
        is_vis_enabled="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")"
        vis_profile="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('profile', 'double_reversed')).lower())" 2>/dev/null || echo "double_reversed")"
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
            applet|widget)
                shift
                exec 200>"/tmp/plasma-export-config.lock"
                flock -x 200
                handle_general_applet_command "$@"
                exit 0
                ;;
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
                        snapshot)
                            VISUALIZER_ACTION="snapshot"
                            shift
                            ;;
                        check-edit-mode|check_edit_mode)
                            VISUALIZER_ACTION="check-edit-mode"
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
                vis_profile="double_reversed"
                if [[ -f "$USER_CONFIG_DIR/caelestia/shell.json" ]]; then
                    is_vis_enabled="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")"
                    vis_profile="$(python3 -c "import json; print(str(json.load(open('$USER_CONFIG_DIR/caelestia/shell.json')).get('background', {}).get('visualiser', {}).get('profile', 'double_reversed')).lower())" 2>/dev/null || echo "double_reversed")"
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
    handle_skwd_command "export"
fi

if [[ -n "$VISUALIZER_ACTION" ]]; then
    exec 200>"/tmp/plasma-export-config.lock"
    flock -x 200
    handle_visualizer_command "$VISUALIZER_ACTION" "${VISUALIZER_ARGS[@]}"
fi
fi
