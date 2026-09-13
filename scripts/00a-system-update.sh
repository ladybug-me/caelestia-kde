#!/usr/bin/env bash
# 00a-system-update.sh - full system upgrade, refusing to continue when the
# upgrade would strand the running session.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

# Stale-session guard (issue #627).
#
# Upgrading kwin/plasma-workspace/libplasma/qt6-base/qt6-declarative pulls
# libraries out from under the running session: live KWin keeps the old ones in
# memory while 08-build-shell.sh compiles the plugin against the new headers and
# 06-services.sh loads it into that same old process. The resulting Wayland
# protocol/ABI errors look like a broken build, not a stale session.
#
# Session identity is KWin's PID plus its start time in clock ticks; both change
# on restart, which is the only thing that clears a stale verdict. No running
# KWin (TTY install, another desktop) means there is no session to invalidate.
kwin_session_identity() {
    local pid
    pid="$(pgrep -x kwin_wayland 2>/dev/null | head -n1 || true)"
    [[ -n "$pid" ]] || pid="$(pgrep -x kwin_x11 2>/dev/null | head -n1 || true)"
    [[ -n "$pid" ]] || return 1
    # Field 22 of /proc/<pid>/stat is the start time in clock ticks.
    printf '%s %s\n' "$pid" "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo '?')"
}

STALE_SESSION_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/stale-session"

# Checked before the SKIP_SYSTEM_UPDATE exit: a session flagged by an earlier run
# is stale whether or not this run updates anything, and "retry" on the failure
# prompt re-runs this step, by which time the upgrade is no longer a difference
# to detect.
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

# Arch-only: the rolling distro where this happens routinely, and where `pacman -Q`
# is the version query. Fedora and Debian get the stamp check but not this.
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
