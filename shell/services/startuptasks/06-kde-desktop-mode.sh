#!/usr/bin/env bash
# Enable KDE desktop mode and sync KDE wallpaper layout to desktop mode.
set -euo pipefail

SYNC_SCRIPT=""
for candidate in \
    "${SCRIPTS_DIR:-}/sync-kde-wallpaper-layout.sh" \
    "$HOME/.config/quickshell/caelestia/scripts/sync-kde-wallpaper-layout.sh" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/scripts/sync-kde-wallpaper-layout.sh"; do
    if [[ -f "$candidate" ]]; then
        SYNC_SCRIPT="$candidate"
        break
    fi
done

SHELL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json"
MODE="desktop"
if [[ -f "$SHELL_CONFIG" ]] && command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("background",{}).get("disableQuickshellDesktop") else 1)' "$SHELL_CONFIG" 2>/dev/null; then
        MODE="folder"
    fi
fi

if [[ -n "$SYNC_SCRIPT" ]]; then
    bash "$SYNC_SCRIPT" "$MODE"
    echo "StartupTasks: Synced KDE wallpaper layout to $MODE mode"
fi

exit 0
