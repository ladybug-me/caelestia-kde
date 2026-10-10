#!/usr/bin/env bash
# Enable KDE desktop mode and sync KDE wallpaper layout to desktop mode.
set -euo pipefail

CONFIG_FILE="$HOME/.config/caelestia/shell.json"

if [[ -f "$CONFIG_FILE" ]]; then
    if updated=$(jq '.background.wallpaperEnabled = false' "$CONFIG_FILE" 2>/dev/null); then
        printf '%s\n' "$updated" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
else
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat <<EOF > "$CONFIG_FILE"
{
    "background": {
        "wallpaperEnabled": false
    }
}
EOF
fi

echo "StartupTasks: Enabled KDE desktop mode (wallpaperEnabled = false)"

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

if [[ -n "$SYNC_SCRIPT" ]]; then
    bash "$SYNC_SCRIPT" desktop
    echo "StartupTasks: Synced KDE wallpaper layout to desktop mode"
fi

exit 0
