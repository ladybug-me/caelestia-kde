#!/usr/bin/env bash
# The directory this user's own processes share for lock files and sockets.
#
# It is claimed rather than assumed: a fixed name under a world-writable /tmp could
# be a symlink someone else planted before the script ran, and opening through it
# would clobber or expose whatever it points at.
if [[ -z "${CAELESTIA_RUNTIME_DIR_SOURCED:-}" ]]; then
CAELESTIA_RUNTIME_DIR_SOURCED=1

# Sets CAELESTIA_RUNTIME_DIR. Returns non-zero when this user cannot claim it.
caelestia_runtime_dir() {
    if [[ -n "${CAELESTIA_RUNTIME_DIR:-}" ]]; then
        return 0
    fi

    local dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/caelestia-$UID"
    if [[ -L "$dir" ]] || { [[ -e "$dir" ]] && [[ ! -O "$dir" ]]; }; then
        return 1
    fi
    install -d -m 700 "$dir" 2>/dev/null || return 1
    CAELESTIA_RUNTIME_DIR="$dir"
}

fi
