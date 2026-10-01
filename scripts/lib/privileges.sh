#!/usr/bin/env bash
if [[ -z "${CAELESTIA_PRIVILEGES_SOURCED:-}" ]]; then
CAELESTIA_PRIVILEGES_SOURCED=1

caelestia_sudo_bin() {
    if [[ -n "${CAELESTIA_SUDO_BIN:-}" ]]; then
        printf '%s\n' "$CAELESTIA_SUDO_BIN"
    elif [[ -x /usr/bin/sudo ]]; then
        printf '%s\n' /usr/bin/sudo
    else
        command -v sudo
    fi
}

caelestia_real_sudo() {
    "$(caelestia_sudo_bin)" "$@"
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

caelestia_have_askpass() {
    [[ -n "${SUDO_ASKPASS:-}" && -x "${SUDO_ASKPASS}" ]]
}

# Which way this shell can elevate: root, cached, askpass, terminal or pkexec.
# Prints the one it would use, in that order, and fails when there is none. Nothing
# runs here, so callers that must not prompt can reject the last two and stop.
caelestia_sudo_method() {
    if [[ "$EUID" -eq 0 ]]; then
        printf 'root\n'
    elif caelestia_real_sudo -n true 2>/dev/null; then
        printf 'cached\n'
    elif caelestia_have_askpass; then
        printf 'askpass\n'
    elif [[ -t 0 ]]; then
        printf 'terminal\n'
    elif command -v pkexec >/dev/null 2>&1; then
        printf 'pkexec\n'
    else
        return 1
    fi
}

caelestia_sudo_run() {
    local method="$1"
    shift
    case "$method" in
        root) "$@" ;;
        cached) caelestia_real_sudo -n "$@" ;;
        askpass) caelestia_real_sudo -A "$@" ;;
        terminal) caelestia_real_sudo "$@" ;;
        pkexec) pkexec "$@" ;;
    esac
}

caelestia_prime_sudo() {
    if [[ "$EUID" -eq 0 || -n "${CAELESTIA_SUDO_PRIMED:-}" ]]; then
        return 0
    fi

    # A GUI askpass helper beats pkexec here, and the export has to happen in this
    # shell rather than inside the lookup that runs in a subshell.
    if [[ ! -t 0 ]] && ! caelestia_have_askpass; then
        local found
        if found="$(caelestia_find_askpass)"; then
            export SUDO_ASKPASS="$found"
        fi
    fi

    local method
    if ! method="$(caelestia_sudo_method)"; then
        return 1
    fi
    if [[ "$method" == pkexec ]]; then
        # pkexec asks for itself when the real command runs.
        return 0
    fi
    if ! caelestia_sudo_run "$method" -v; then
        return 1
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

    local method
    if ! method="$(caelestia_sudo_method)"; then
        if declare -F err >/dev/null; then
            err "Cannot elevate privileges. Install ksshaskpass or pkexec, or run from a terminal."
        else
            echo "  [ERR]   Cannot elevate privileges." >&2
        fi
        return 1
    fi

    caelestia_sudo_run "$method" "$@"
}

caelestia_sudo_quiet() {
    local method
    method="$(caelestia_sudo_method)" || return 1
    case "$method" in
        terminal|pkexec) return 1 ;;
    esac
    caelestia_sudo_run "$method" "$@"
}

fi
