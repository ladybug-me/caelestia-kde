#!/usr/bin/env bash

# Reports whether the workspace-tracker KWin effect the installer enabled is
# actually loaded. KWin promises binary effects no ABI stability, so after a KDE
# point release it refuses the binary built against the old libkwin: per-output
# desktops and the swipe offset stop arriving, and nothing on screen says why.
#
# Exit status: 0 when the effect is loaded or this install does not use it, 3
# when it is enabled but absent, so the caller can tell the user to rebuild. On 3
# it prints one line saying why, for the caller to put in front of the user.

set -euo pipefail

# Without these there is no way to ask, and a missing tool must not be reported
# as a missing effect.
command -v kreadconfig6 >/dev/null 2>&1 || exit 0
command -v qdbus6 >/dev/null 2>&1 || exit 0

enabled="$(kreadconfig6 --file kwinrc --group Plugins --key kwin_workspace_trackerEnabled 2>/dev/null || true)"
[[ "$enabled" == "true" ]] || exit 0

PLUGIN_DIRS=(/usr/lib/qt6/plugins/kwin/effects/plugins /usr/lib64/qt6/plugins/kwin/effects/plugins)

# The effect is a binary plugin stamped with the exact KWin it was built against,
# so naming both versions turns "it is not running" into something the user can
# act on. Anything unreadable falls back to the plain statement.
explain_not_loaded() {
    local dir plugin="" built="" running=""

    for dir in "${PLUGIN_DIRS[@]}"; do
        if [[ -f "$dir/kwin_workspace_tracker.so" ]]; then
            plugin="$dir/kwin_workspace_tracker.so"
            break
        fi
    done

    if [[ -n "$plugin" ]] && command -v strings >/dev/null 2>&1; then
        built="$(strings "$plugin" 2>/dev/null | grep -o 'EffectPluginFactory[0-9.]*' | head -n1 | sed 's/EffectPluginFactory//' || true)"
    fi
    if command -v kwin_wayland >/dev/null 2>&1; then
        running="$(kwin_wayland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    fi

    if [[ -n "$built" && -n "$running" && "$built" != "$running" ]]; then
        printf 'built for KWin %s, KWin %s running' "$built" "$running"
    else
        printf 'not registered by KWin'
    fi
}

# The effect registers this object on KWin's bus as it loads. If not yet loaded,
# attempt to load it before declaring failure (e.g. after a rebuild or late startup).
if ! qdbus6 org.kde.KWin /Caelestia/Workspaces org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kwin_workspace_tracker >/dev/null 2>&1 || true
fi

if ! qdbus6 org.kde.KWin /Caelestia/Workspaces org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1; then
    explain_not_loaded
    exit 3
fi

exit 0

