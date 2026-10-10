#!/usr/bin/env bash
# Syncs KDE Plasma desktop wallpaper layout between Desktop View (org.kde.desktopcontainment)
# and Folder View (org.kde.plasma.folder).
# Usage: sync-kde-wallpaper-layout.sh [desktop|folder|true|false]

set -euo pipefail

exec 200>/tmp/sync-kde-wallpaper-layout.lock
flock -n 200 || exit 0

MODE="${1:-}"
case "$MODE" in
    desktop|true|1|enable)
        TARGET_PLUGIN="org.kde.desktopcontainment"
        ;;
    folder|false|0|disable)
        TARGET_PLUGIN="org.kde.plasma.folder"
        ;;
    *)
        TARGET_PLUGIN="org.kde.desktopcontainment"
        ;;
esac

python3 - "$TARGET_PLUGIN" << 'EOF'
import os, re, subprocess, sys

target_plugin = sys.argv[1]

shell_pkg = ""
try:
    shell_pkg = subprocess.check_output(
        ["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.shell"],
        text=True, stderr=subprocess.DEVNULL
    ).strip()
except Exception:
    pass

candidate_files = []
if shell_pkg:
    candidate_files.append(f"plasma-{shell_pkg}-appletsrc")
for default_name in ["plasma-caelestia.desktop-appletsrc", "plasma-org.kde.plasma.desktop-appletsrc"]:
    if default_name not in candidate_files:
        candidate_files.append(default_name)

modified = False
for fname in candidate_files:
    fpath = os.path.expanduser(f"~/.config/{fname}")
    if not os.path.exists(fpath):
        continue

    with open(fpath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    current_id = None
    formfactors = {}
    plugins = {}
    for line in lines:
        s = line.strip()
        m = re.match(r"^\[Containments\]\[(\d+)\]$", s)
        if m:
            current_id = m.group(1)
            continue
        elif s.startswith("["):
            current_id = None
            continue

        if current_id is not None:
            if s.startswith("formfactor="):
                formfactors[current_id] = s.split("=", 1)[1].strip()
            elif s.startswith("plugin="):
                plugins[current_id] = s.split("=", 1)[1].strip()

    for cid in set(list(formfactors.keys()) + list(plugins.keys())):
        ff = formfactors.get(cid, "")
        p = plugins.get(cid, "")
        if ff == "0" or p in ("org.kde.desktopcontainment", "org.kde.plasma.folder"):
            if ff in ("2", "3") or p == "org.kde.panel":
                continue
            if p != target_plugin:
                subprocess.run([
                    "kwriteconfig6", "--file", fname,
                    "--group", "Containments", "--group", cid,
                    "--key", "plugin", target_plugin
                ], check=True)
                modified = True

if modified:
    subprocess.run(["systemctl", "--user", "reset-failed", "plasma-plasmashell"], check=False)
    res = subprocess.run(["systemctl", "--user", "restart", "plasma-plasmashell"])
    if res.returncode != 0:
        subprocess.run(["systemctl", "--user", "reset-failed", "plasma-plasmashell"], check=False)
        res = subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell"])
    if subprocess.run(["systemctl", "--user", "is-active", "--quiet", "plasma-plasmashell"]).returncode != 0:
        if subprocess.run(["pgrep", "-x", "plasmashell"], stdout=subprocess.DEVNULL).returncode != 0:
            cmd = ["kstart", "plasmashell"] if os.path.exists("/usr/bin/kstart") else ["plasmashell"]
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        else:
            subprocess.run(["kquitapp6", "plasmashell"], check=False)
            cmd = ["kstart", "plasmashell", "--replace"] if os.path.exists("/usr/bin/kstart") else ["plasmashell", "--replace"]
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
EOF


