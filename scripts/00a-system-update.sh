#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

kwin_session_identity() {
    local pid
    pid="$(pgrep -x kwin_wayland 2>/dev/null | head -n1 || true)"
    [[ -n "$pid" ]] || pid="$(pgrep -x kwin_x11 2>/dev/null | head -n1 || true)"
    [[ -n "$pid" ]] || return 1
    printf '%s %s\n' "$pid" "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo '?')"
}

STALE_SESSION_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/stale-session"

if [[ -f "$STALE_SESSION_STAMP" ]]; then
    if [[ "$(cat "$STALE_SESSION_STAMP" 2>/dev/null)" == "$(kwin_session_identity 2>/dev/null)" ]]; then
        err "This Plasma session still predates the last KWin/Qt upgrade. Log out and"
        err "back in (or reboot), then run the installer again."
        exit 1
    fi
    rm -f "$STALE_SESSION_STAMP"
fi

if [[ "${SKIP_SYSTEM_UPDATE:-false}" == "true" ]]; then
    info "Skipping full system update (SKIP_SYSTEM_UPDATE=true)."
    exit 0
fi

SESSION_PACKAGES=(kwin plasma-workspace libplasma qt6-base qt6-declarative)

session_package_versions() {
    local pkg
    for pkg in "${SESSION_PACKAGES[@]}"; do
        pacman -Q "$pkg" 2>/dev/null || printf '%s not-installed\n' "$pkg"
    done
}

if [[ "${BASE_DISTRO:-unknown}" == "arch" ]]; then
    versions_before="$(session_package_versions)"
    if [[ -n "${CONFIRM_ARG:-}" ]]; then
        sudo pacman -Syu --noconfirm
    else
        sudo pacman -Syu
    fi

    if [[ "$(session_package_versions)" != "$versions_before" ]]; then
        err "The upgrade replaced packages the running session still has loaded in memory:"
        diff <(printf '%s\n' "$versions_before") <(session_package_versions) \
            | grep -E '^[<>]' | sed 's/^</  [ERR]   had /; s/^>/  [ERR]   now /' >&2 || true
        err "Building and loading the Caelestia KWin plugin now would link against the new"
        err "libraries while the live KWin still runs the old ones, which fails later with"
        err "errors that look unrelated to this upgrade."
        err "Exit the installer, log out and back in (or reboot), then run it again - the"
        err "upgrade is already applied, so the re-run goes straight to the rest."
        if identity="$(kwin_session_identity 2>/dev/null)" && [[ -n "$identity" ]]; then
            mkdir -p "$(dirname "$STALE_SESSION_STAMP")"
            printf '%s\n' "$identity" > "$STALE_SESSION_STAMP"
        fi
        exit 1
    fi
elif [[ "${BASE_DISTRO:-unknown}" == "fedora" ]]; then
    if [[ -n "${CONFIRM_ARG:-}" ]]; then
        sudo dnf upgrade --refresh -y
    else
        sudo dnf upgrade --refresh
    fi
elif [[ "${BASE_DISTRO:-unknown}" == "debian" ]]; then
    if [[ -n "${CONFIRM_ARG:-}" ]]; then
        sudo apt-get update && sudo apt-get upgrade -y
    else
        sudo apt-get update && sudo apt-get upgrade
    fi
else
    warn "Distro not set properly, skipping system update."
fi
