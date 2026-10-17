#!/usr/bin/env bash
# Export skwd-wall and audio visualizer plasma configurations on startup.
set -euo pipefail

EXPORT_SCRIPT=""
for candidate in \
    "${SCRIPTS_DIR:-}/export-plasma-config.sh" \
    "$HOME/.config/quickshell/caelestia/scripts/export-plasma-config.sh" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/scripts/export-plasma-config.sh"; do
    if [[ -f "$candidate" ]]; then
        EXPORT_SCRIPT="$candidate"
        break
    fi
done

if [[ -n "$EXPORT_SCRIPT" ]]; then
    bash "$EXPORT_SCRIPT" all
    echo "StartupTasks: Exported Plasma configuration"
fi

exit 0
