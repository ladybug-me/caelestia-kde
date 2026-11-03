#!/usr/bin/env bash
# Update skwd-wall-v2 post-processing hook to include SKWD_WALLD=1 on deployed systems.
set -euo pipefail

SKWD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/skwd-wall-v2/config.json"

if [[ -f "$SKWD_CONFIG" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 -c '
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    modified = False
    for item in data.get("postProcessing", []):
        cmd = item.get("command", "")
        if "caelestia-color" in cmd and "SKWD_WALLD" not in cmd:
            if "PATH=" in cmd:
                item["command"] = cmd.replace("PATH=", "SKWD_WALLD=1 PATH=")
            else:
                item["command"] = cmd.replace("caelestia-color", "SKWD_WALLD=1 caelestia-color")
            modified = True
    if modified:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print("StartupTasks: Updated skwd-wall post-processing command with SKWD_WALLD=1")
except Exception as e:
    sys.stderr.write(f"StartupTasks: Failed to update skwd-wall config: {e}\n")
' "$SKWD_CONFIG"
    elif grep -q 'caelestia-color' "$SKWD_CONFIG" && ! grep -q 'SKWD_WALLD' "$SKWD_CONFIG"; then
        sed -i 's|"command": "PATH=\$HOME/.local/bin:\$PATH caelestia-color|"command": "SKWD_WALLD=1 PATH=$HOME/.local/bin:$PATH caelestia-color|g; s|"command": "caelestia-color|"command": "SKWD_WALLD=1 caelestia-color|g' "$SKWD_CONFIG"
        echo "StartupTasks: Updated skwd-wall post-processing command with SKWD_WALLD=1 via sed"
    fi
fi

exit 0

