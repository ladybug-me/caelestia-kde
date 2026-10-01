#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/caelestia/shell.json"

if [[ -f "$CONFIG_FILE" ]]; then
    if grep -q '"wallpaperFillMode":' "$CONFIG_FILE"; then
        sed -i 's/"wallpaperFillMode": [0-9]*/"wallpaperFillMode": 2/g' "$CONFIG_FILE"
    else
        sed -i '/"background": {/a \        "wallpaperFillMode": 2,' "$CONFIG_FILE"
    fi
else
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat <<EOF > "$CONFIG_FILE"
{
    "background": {
        "wallpaperFillMode": 2
    }
}
EOF
fi

echo "StartupTasks: Set Caelestia wallpaperFillMode to 2"

exit 0
