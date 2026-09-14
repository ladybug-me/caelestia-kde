#!/usr/bin/env bash
if [[ -z "${CAELESTIA_PRIVILEGES_SOURCED:-}" ]]; then
CAELESTIA_PRIVILEGES_SOURCED=1

caelestia_real_sudo() {
    if [[ -x /usr/bin/sudo ]]; then
        /usr/bin/sudo "$@"
    else
        sudo "$@"
    fi
}

caelestia_find_askpass() {
    local helper
    for helper in ksshaskpass /usr/lib/ssh/ksshaskpass /usr/libexec/ksshaskpass \
        lxqt-openssh-askpass x11-ssh-askpass ssh-askpass; do
        if command -v "$helper" >/dev/null 2>&1; then
            command -v "$helper"
            return 0
        fi
    done
    return 1
}

caelestia_prime_sudo() {
    if [[ "$EUID" -eq 0 || -n "${CAELESTIA_SUDO_PRIMED:-}" ]]; then
        return 0
    fi

    if caelestia_real_sudo -n true 2>/dev/null; then
        :
    elif [[ -n "${SUDO_PASS:-}" ]]; then
        printf '%s\n' "$SUDO_PASS" | caelestia_real_sudo -S -p '' -v || return 1
    elif [[ -t 0 ]]; then
        caelestia_real_sudo -v || return 1
    else
        local askpass
        if askpass="$(caelestia_find_askpass)"; then
            export SUDO_ASKPASS="$askpass"
            caelestia_real_sudo -A -v || return 1
        elif command -v pkexec >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi

    export CAELESTIA_SUDO_PRIMED=1

    (
        while kill -0 "$$" 2>/dev/null; do
            sleep 30
            caelestia_real_sudo -nv 2>/dev/null || true
        done
    ) &
    CAELESTIA_SUDO_KEEPALIVE_PID=$!
    export CAELESTIA_SUDO_KEEPALIVE_PID
    return 0
}

caelestia_stop_sudo_keepalive() {
    if [[ -n "${CAELESTIA_SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$CAELESTIA_SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$CAELESTIA_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

caelestia_sudo() {
    if [[ "$EUID" -ne 0 ]] && ! caelestia_real_sudo -n true 2>/dev/null; then
        caelestia_prime_sudo || true
    fi

    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif caelestia_real_sudo -n true 2>/dev/null; then
        caelestia_real_sudo -n "$@"
    elif [[ -n "${SUDO_PASS:-}" ]]; then
        printf '%s\n' "$SUDO_PASS" | caelestia_real_sudo -S -p '' "$@"
    elif [[ -t 0 ]]; then
        caelestia_real_sudo "$@"
    elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
        caelestia_real_sudo -A "$@"
    elif command -v pkexec >/dev/null 2>&1; then
        pkexec "$@"
    else
        if declare -F err >/dev/null; then
            err "Cannot elevate privileges. Install ksshaskpass or pkexec, or run from a terminal."
        else
            echo "  [ERR]   Cannot elevate privileges." >&2
        fi
        return 1
    fi
}

caelestia_sudo_quiet() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif [[ -n "${SUDO_PASS:-}" ]]; then
        printf '%s\n' "$SUDO_PASS" | caelestia_real_sudo -S -p '' "$@"
    else
        caelestia_real_sudo -n "$@"
    fi
}

fi # CAELESTIA_PRIVILEGES_SOURCED
