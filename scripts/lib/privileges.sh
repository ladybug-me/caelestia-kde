#!/usr/bin/env bash
# privileges.sh - one credential prompt for the whole run, terminal or not.
#
#   caelestia_prime_sudo   Obtain credentials once and keep them warm
#   caelestia_sudo         Run a command as root, reusing those credentials
#   caelestia_sudo_quiet   Same, but never prompts (returns 1 instead)
#
# The updater sources this and then runs step scripts that source it again; the
# guard is an if rather than a return so a false test cannot trip `set -e`.
if [[ -z "${CAELESTIA_PRIVILEGES_SOURCED:-}" ]]; then
CAELESTIA_PRIVILEGES_SOURCED=1

# The TUI puts a sudo wrapper on PATH that forces -A against its own askpass
# helper. That defeats the -n probe and the -S feed below, so those bypass it.
caelestia_real_sudo() {
    if [[ -x /usr/bin/sudo ]]; then
        /usr/bin/sudo "$@"
    else
        sudo "$@"
    fi
}

# First askpass helper found, for when there is no terminal to prompt on.
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

# Seed sudo's timestamp once and refresh it in the background, so a long build
# or a GUI-launched update never prompts twice.
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
            # Nothing to prime; each command escalates through pkexec instead.
            return 0
        else
            return 1
        fi
    fi

    export CAELESTIA_SUDO_PRIMED=1

    # -n extends the timestamp without ever re-prompting.
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

# Lazy on purpose: most updates have no root work left, so only the first
# command that needs root primes the credentials.
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

# Root work that must never interrupt: cached credentials or the exported
# password, otherwise fail. Feeding the password beats -n, which refuses before
# the password is even read.
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
