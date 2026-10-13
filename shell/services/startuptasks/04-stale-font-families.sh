#!/usr/bin/env bash

# The SF fonts were selectable once, so a config written back then still stores a family
# that resolves to nothing now. Clearing just those values lands those installs on the
# "Follow system" font option without touching a family the user still has.
CONFIG_FILE="$HOME/.config/caelestia/shell.json"

if [[ -f "$CONFIG_FILE" ]] && grep -q '"SF Pro"\|"SF Mono"' "$CONFIG_FILE"; then
    if updated=$(jq '
        if .appearance.font? then
            .appearance.font |= walk(if type == "string" and (. == "SF Pro" or . == "SF Mono") then "" else . end)
        else . end' "$CONFIG_FILE" 2>/dev/null) && printf '%s\n' "$updated" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"; then
        echo "StartupTasks: Cleared the removed SF font families from shell.json; those fonts now follow the system."
    fi
fi

exit 0
