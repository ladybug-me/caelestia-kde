#!/usr/bin/env bash
set -euo pipefail

# krohnkite_setup.sh - Install, update, and manage the Krohnkite KWin tiling script.

REPO_API="https://codeberg.org/api/v1/repos/anametologin/Krohnkite/releases?limit=10"

notify() {
    local title="$1"
    local message="$2"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" || true
    fi
}

get_installed_version() {
    python3 -c '
import subprocess, json, os

def check():
    try:
        out = subprocess.check_output(["kpackagetool6", "-t", "KWin/Script", "-s", "krohnkite"], stderr=subprocess.DEVNULL, text=True)
        for line in out.splitlines():
            if "Path" in line and ":" in line:
                path = line.split(":", 1)[1].strip()
                meta = os.path.join(path, "metadata.json")
                if os.path.exists(meta):
                    with open(meta, "r", encoding="utf-8") as f:
                        return json.load(f).get("KPlugin", {}).get("Version", "").lstrip("v")
    except Exception:
        pass
    for p in ["~/.local/share/kwin/scripts/krohnkite/metadata.json", "/usr/share/kwin/scripts/krohnkite/metadata.json"]:
        path = os.path.expanduser(p)
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f).get("KPlugin", {}).get("Version", "").lstrip("v")
            except Exception:
                pass
    return ""

print(check())
'
}

get_release_info() {
    python3 -c '
import urllib.request, json, os, subprocess, re

def get_installed():
    try:
        out = subprocess.check_output(["kpackagetool6", "-t", "KWin/Script", "-s", "krohnkite"], stderr=subprocess.DEVNULL, text=True)
        for line in out.splitlines():
            if "Path" in line and ":" in line:
                path = line.split(":", 1)[1].strip()
                meta = os.path.join(path, "metadata.json")
                if os.path.exists(meta):
                    with open(meta, "r", encoding="utf-8") as f:
                        return json.load(f).get("KPlugin", {}).get("Version", "").lstrip("v")
    except Exception:
        pass
    for p in ["~/.local/share/kwin/scripts/krohnkite/metadata.json", "/usr/share/kwin/scripts/krohnkite/metadata.json"]:
        path = os.path.expanduser(p)
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f).get("KPlugin", {}).get("Version", "").lstrip("v")
            except Exception:
                pass
    return ""

def get_latest():
    url = "'"$REPO_API"'"
    req = urllib.request.Request(url, headers={"User-Agent": "Caelestia-Krohnkite-Updater"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            releases = json.loads(resp.read().decode())
            for r in releases:
                if not r.get("prerelease") and not r.get("draft"):
                    tag = r.get("tag_name", "").lstrip("v")
                    assets = r.get("assets", [])
                    dl_url = next((a["browser_download_url"] for a in assets if a["name"].endswith(".kwinscript")), None)
                    if dl_url:
                        return tag, dl_url
    except Exception:
        pass
    return "", ""

def version_tuple(v):
    return [int(x) for x in re.findall(r"\d+", v)]

def is_newer(latest, installed):
    if not installed or not latest:
        return False
    return version_tuple(latest) > version_tuple(installed)

inst = get_installed()
lat, dl = get_latest()
upd = is_newer(lat, inst)

print(json.dumps({
    "installed": inst,
    "latest": lat,
    "update_available": upd,
    "download_url": dl
}))
'
}

is_installed() {
    if command -v kpackagetool6 >/dev/null 2>&1; then
        if kpackagetool6 -t KWin/Script -s krohnkite >/dev/null 2>&1; then
            return 0
        fi
    fi
    if [[ -f "$HOME/.local/share/kwin/scripts/krohnkite/metadata.json" || -f "/usr/share/kwin/scripts/krohnkite/metadata.json" ]]; then
        return 0
    fi
    return 1
}

fetch_download_url() {
    python3 -c '
import urllib.request, json
url = "'"$REPO_API"'"
req = urllib.request.Request(url, headers={"User-Agent": "Caelestia-Krohnkite-Updater"})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        releases = json.loads(resp.read().decode())
        for r in releases:
            if not r.get("prerelease") and not r.get("draft"):
                assets = r.get("assets", [])
                dl_url = next((a["browser_download_url"] for a in assets if a["name"].endswith(".kwinscript")), None)
                if dl_url:
                    print(dl_url)
                    exit(0)
except Exception:
    pass
'
}

fetch_latest_version() {
    python3 -c '
import urllib.request, json
url = "'"$REPO_API"'"
req = urllib.request.Request(url, headers={"User-Agent": "Caelestia-Krohnkite-Updater"})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        releases = json.loads(resp.read().decode())
        for r in releases:
            if not r.get("prerelease") and not r.get("draft"):
                print(r.get("tag_name", "").lstrip("v"))
                exit(0)
except Exception:
    pass
'
}

do_install() {
    if ! command -v kpackagetool6 >/dev/null 2>&1; then
        echo "Error: kpackagetool6 is not available." >&2
        notify "Installation Failed" "kpackagetool6 command not found."
        return 1
    fi

    local dl_url
    dl_url="$(fetch_download_url)"
    if [[ -z "$dl_url" ]]; then
        echo "Error: Could not determine Krohnkite download URL." >&2
        notify "Installation Failed" "Could not fetch Krohnkite release information."
        return 1
    fi

    notify "Installing Krohnkite..." "Please stay connected to the internet..."

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT INT TERM
    local kwinscript="$tmpdir/krohnkite.kwinscript"

    if curl -sL --proto '=https' --tlsv1.2 -- "$dl_url" -o "$kwinscript"; then
        if is_installed; then
            kpackagetool6 -t KWin/Script -u "$kwinscript" 2>/dev/null || {
                kpackagetool6 -t KWin/Script -r krohnkite 2>/dev/null || true
                kpackagetool6 -t KWin/Script -i "$kwinscript" 2>/dev/null || true
            }
        else
            kpackagetool6 -t KWin/Script -i "$kwinscript" 2>/dev/null || true
        fi

        kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled" "true" 2>/dev/null || true
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
        notify "Installation Completed" "Krohnkite has been installed successfully."
        rm -rf "$tmpdir"
        trap - EXIT INT TERM
        return 0
    else
        notify "Installation Failed" "Krohnkite download failed. Please try again."
        rm -rf "$tmpdir"
        trap - EXIT INT TERM
        return 1
    fi
}

do_update() {
    if ! command -v kpackagetool6 >/dev/null 2>&1; then
        echo "Error: kpackagetool6 is not available." >&2
        notify "Update Failed" "kpackagetool6 command not found."
        return 1
    fi

    local dl_url
    dl_url="$(fetch_download_url)"
    local latest_ver
    latest_ver="$(fetch_latest_version)"

    if [[ -z "$dl_url" ]]; then
        echo "Error: Could not determine Krohnkite download URL." >&2
        notify "Update Failed" "Could not fetch Krohnkite release information."
        return 1
    fi

    notify "Updating Krohnkite..." "Downloading version ${latest_ver:-latest}..."

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT INT TERM
    local kwinscript="$tmpdir/krohnkite.kwinscript"

    if curl -sL --proto '=https' --tlsv1.2 -- "$dl_url" -o "$kwinscript"; then
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "krohnkite" 2>/dev/null || true

        if is_installed; then
            if ! kpackagetool6 -t KWin/Script -u "$kwinscript" 2>/dev/null; then
                kpackagetool6 -t KWin/Script -r krohnkite 2>/dev/null || true
                kpackagetool6 -t KWin/Script -i "$kwinscript" 2>/dev/null || true
            fi
        else
            kpackagetool6 -t KWin/Script -i "$kwinscript" 2>/dev/null || true
        fi

        kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled" "true" 2>/dev/null || true
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
        notify "Krohnkite Updated" "Updated to version ${latest_ver}."
        rm -rf "$tmpdir"
        trap - EXIT INT TERM
        return 0
    else
        notify "Update Failed" "Krohnkite download failed. Please try again."
        rm -rf "$tmpdir"
        trap - EXIT INT TERM
        return 1
    fi
}

do_disable() {
    qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "KrohnkiteFloatAll" 2>/dev/null || true
    sleep 0.1
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "krohnkite" 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled" "false" 2>/dev/null || true
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
}

mode="${1:-}"

case "$mode" in
    --status|--check|--check-update)
        get_release_info
        ;;
    --installed-version)
        get_installed_version
        ;;
    --latest-version)
        fetch_latest_version
        ;;
    --install)
        if ! is_installed; then
            do_install
        else
            kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled" "true" 2>/dev/null || true
            qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
        fi
        ;;
    --force-install)
        do_install
        ;;
    --update)
        do_update
        ;;
    --disable)
        do_disable
        ;;
    -h|--help)
        echo "Usage: krohnkite_setup.sh [--status|--check-update|--install|--update|--disable]"
        ;;
    *)
        if ! is_installed; then
            do_install
        else
            info="$(get_release_info)"
            if echo "$info" | grep -q '"update_available": true'; then
                do_update
            else
                echo "Krohnkite is up to date."
            fi
        fi
        ;;
esac
