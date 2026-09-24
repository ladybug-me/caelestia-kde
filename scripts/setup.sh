#!/usr/bin/env bash

set -euo pipefail
export CAELESTIA_SETUP_RUNNING=1

tput civis 2>/dev/null || true

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$BUNDLE_DIR/scripts"
export BUNDLE_DIR
export INSTALL_START_EPOCH="$(date +%s)"

export PATH="$HOME/.local/bin:$PATH"

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/caelestia-setup.lock"
flock -n 9 || { echo "Another Caelestia setup is already running."; exit 1; }

# shellcheck source=scripts/lib/privileges.sh
source "$SCRIPTS_DIR/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$SCRIPTS_DIR/lib/packages.sh"
# shellcheck source=scripts/lib/download.sh
source "$SCRIPTS_DIR/lib/download.sh"

# Fork identity: the owner publishing release artifacts (the prebuilt TUI
# binary here). Upstream default stays ladybug-me; a fork that does not
# publish binaries points this at the owner whose releases it ships.
: "${CAELESTIA_PREBUILT_OWNER:=ladybug-me}"

run_arch_pacman_install() {
    local -a pkgs=("$@")
    local -a pacman_args=(-S --needed --noconfirm)

    if (( ${#pkgs[@]} == 0 )); then
        return 0
    fi

    caelestia_sudo pacman -Sy --noconfirm >/dev/null 2>&1 || echo "[WARN]  Failed to refresh pacman sources before install. Continuing..."
    caelestia_sudo pacman "${pacman_args[@]}" "${pkgs[@]}" && return 0

    echo "[WARN]  pacman install failed. Refreshing sources and retrying once..."
    caelestia_sudo pacman -Sy --noconfirm >/dev/null 2>&1 || true
    caelestia_sudo pacman "${pacman_args[@]}" "${pkgs[@]}"
}

normalize_line_endings_first() {
    local -a crlf_files=()
    local convert_choice=""

    mapfile -t crlf_files < <(
        find "$BUNDLE_DIR" -path "$BUNDLE_DIR/.git" -prune -o -type f -name '*.sh' -print0 | \
            xargs -0 grep -Il $'\r' 2>/dev/null || true
    )

    if (( ${#crlf_files[@]} == 0 )); then
        return 0
    fi

    echo "[WARN]  Detected ${#crlf_files[@]} file(s) with CRLF line endings."
    while true; do
        read -r -p "Convert all files under this repo to LF with dos2unix? [Y/n]: " convert_choice
        convert_choice="${convert_choice:-y}"

        case "${convert_choice,,}" in
            y|yes)
                if ! command -v dos2unix >/dev/null 2>&1; then
                    echo "[WARN]  dos2unix is not installed. Attempting to install it now..."
                    case "$BASE_DISTRO" in
                        arch)
                            run_arch_pacman_install dos2unix || return 1
                            ;;
                        fedora)
                            caelestia_sudo dnf install -y dos2unix || return 1
                            ;;
                        debian)
                            caelestia_sudo apt-get update && caelestia_sudo apt-get install -y dos2unix || return 1
                            ;;
                        *)
                            echo "[WARN]  Could not detect distro for automatic dos2unix installation."
                            return 1
                            ;;
                    esac
                    echo "[OK]    dos2unix installed."
                fi

                (
                    cd "$BUNDLE_DIR" || exit 1
                    printf '%s\0' "${crlf_files[@]}" | xargs -0 -r dos2unix --
                ) || return 1

                echo "[OK]    Line endings normalized to LF."
                return 0
                ;;
            n|no)
                echo "[WARN]  Skipping line ending normalization by user choice."
                return 0
                ;;
            *)
                echo "Please answer with y or n."
                ;;
        esac
    done
}

if ! normalize_line_endings_first; then
    echo "[FATAL] Line ending normalization step failed. Aborting installer." >&2
    exit 1
fi

BIN="$BUNDLE_DIR/caelestia-install"

tui_version() {
    tr -d '[:space:]' < "$BUNDLE_DIR/installer/data/tui.version" 2>/dev/null || true
}

release_tag() {
    sed -nE 's/^[[:space:]]*VERSION=//p' "$BUNDLE_DIR/.github/version.env" 2>/dev/null | tr -d '[:space:]'
}

try_download_prebuilt_installer() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|aarch64) ;;
        *) return 1 ;;
    esac

    local version tag tmp_bin url status=0
    version="$(tui_version)"
    tag="$(release_tag)"
    [[ -n "$version" && -n "$tag" ]] || return 1
    tmp_bin="$(mktemp)"
    url="https://github.com/${CAELESTIA_PREBUILT_OWNER}/caelestia-kde/releases/download/${tag}/caelestia-install-${arch}-v${version}"
    if ! fetch_asset "$url" "$tmp_bin" --max-time 30 2>/dev/null; then
        rm -f "$tmp_bin"
        return 1
    fi

    verify_download "$url" "$tmp_bin" || status=$?
    if [[ "$status" -eq 1 ]]; then
        echo "[WARN]  Checksum mismatch for the prebuilt installer - compiling locally."
    elif [[ "$status" -eq 2 ]]; then
        echo "[WARN]  No published checksum for the prebuilt installer - compiling locally."
    fi
    if [[ "$status" -ne 0 ]]; then
        rm -f "$tmp_bin"
        return 1
    fi

    chmod +x "$tmp_bin"
    printf '%s\n' "$tmp_bin"
    return 0
}

start_spinner() {
    echo -n "Preparing Caelestia installer"
    {
        while true; do
            printf "."
            sleep 0.5
            printf "."
            sleep 0.5
            printf "."
            sleep 0.5
            printf "\b\b\b   \b\b\b"
        done
    } &
    SPINNER_PID=$!
}

stop_spinner() {
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    echo ""
}

start_spinner

PREBUILT_BIN=""
if [[ -z "${CAELESTIA_FORCE_BUILD_INSTALLER:-}" ]] && command -v curl >/dev/null 2>&1; then
    PREBUILT_BIN="$(try_download_prebuilt_installer || true)"
fi

if [[ -n "$PREBUILT_BIN" ]]; then
    stop_spinner
    rm -f "$BIN"
    mv "$PREBUILT_BIN" "$BIN"
    echo "[OK]    Using prebuilt installer binary v$(tui_version)."
else
    stop_spinner
    if [[ -n "${CAELESTIA_FORCE_BUILD_INSTALLER:-}" ]]; then
        echo "[INFO]  CAELESTIA_FORCE_BUILD_INSTALLER set - compiling locally."
    else
        echo "[INFO]  No prebuilt binary for v$(tui_version) - compiling locally."
    fi
    STAMP="$BUNDLE_DIR/installer/build/.tui_stamp"
    if [[ -x "$BIN" && -f "$STAMP" ]] && [[ "$(cat "$STAMP" 2>/dev/null)" == "$(tui_version)" ]]; then
        stop_spinner
        echo "[OK]    Reusing compiled installer binary (matches TUI version)."
    else
        MISSING_PKGS=()
        if ! command -v g++ >/dev/null 2>&1; then MISSING_PKGS+=("g++"); fi
        if ! command -v cmake >/dev/null 2>&1; then MISSING_PKGS+=("cmake"); fi
        if ! command -v make >/dev/null 2>&1; then MISSING_PKGS+=("make"); fi
        if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
            stop_spinner
            echo "Missing build tools: ${MISSING_PKGS[*]}. Installing..."
            if [[ "$BASE_DISTRO" == "arch" ]]; then
                run_arch_pacman_install base-devel cmake
            elif [[ "$BASE_DISTRO" == "fedora" ]]; then
                caelestia_sudo dnf install -y gcc-c++ cmake make
            elif [[ "$BASE_DISTRO" == "debian" ]]; then
                caelestia_sudo apt-get update && caelestia_sudo apt-get install -y build-essential g++ cmake make
            else
                echo "Could not auto-install build tools. Please install manually: ${MISSING_PKGS[*]}"
                exit 1
            fi
            start_spinner
        fi

        BUILD_DIR="$BUNDLE_DIR/installer/build"
        BUILD_LOG="/tmp/caelestia_build.log"
        # Configure from a clean directory: cmake bakes absolute source paths into
        # CMakeCache.txt and refuses to configure over a cache naming a different tree.
        # One checkout routinely has two names here - ~/Desktop/caelestia-kwin and
        # /mnt/c/.../caelestia-kwin are the same tree - and reusing that cache fails the
        # build outright instead of falling back to anything.
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        (
            cd "$BUILD_DIR" || exit 1
            cmake -DCMAKE_BUILD_TYPE=Release "$BUNDLE_DIR/installer/tui" >"$BUILD_LOG" 2>&1 || exit 1
            make -j"$(nproc 2>/dev/null || echo 1)" >>"$BUILD_LOG" 2>&1 || exit 1
        ) || {
            stop_spinner
            echo "[FATAL] Failed to build the Caelestia installer." >&2
            echo "--- build log (last 60 lines) ---"
            tail -n 60 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            echo "--- end build log ---"
            echo "Full log saved to: $BUILD_LOG"
            exit 1
        }

        stop_spinner
        rm -f "$BIN"
        cp "$BUILD_DIR/caelestia-install" "$BIN" || {
            echo "[FATAL] Failed to copy the compiled Caelestia installer to $BIN." >&2
            exit 1
        }
        echo "$(tui_version)" > "$STAMP"
    fi
fi

cleanup_install_state() {
    stty sane 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf '\033[0m\033[?1049l\033[?25h' 2>/dev/null || true

    local inhibit_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/caelestia"
    local inhibit_pid="$inhibit_dir/inhibit.pid"
    local kde_cookie="$inhibit_dir/kde_inhibit.cookie"
    if [[ -f "$inhibit_pid" ]]; then
        local pid
        pid="$(cat "$inhibit_pid")"
        if [[ -r "/proc/$pid/cmdline" ]] &&
            tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q systemd-inhibit; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    if [[ -f "$kde_cookie" ]]; then
        qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.UnInhibit "$(cat "$kde_cookie")" 2>/dev/null || true
    fi
    rm -f "$inhibit_pid" "$kde_cookie"
}
trap cleanup_install_state EXIT

if [[ ! -x "$BIN" ]]; then
    echo ""
    echo "============================================================"
    echo "  FATAL: Installer binary missing: $BIN"
    echo "  C++ compilation likely failed — check g++, cmake, make."
    echo "============================================================"
    echo ""
    echo "Press Enter to close this window..."
    read -r
    exit 1
fi

_installer_start=$(date +%s)
"$BIN" "$@" 2>/tmp/caelestia_installer_err.log
_exit_code=$?
_installer_elapsed=$(($(date +%s) - _installer_start))

_reached_done=0
if grep -q '\[installer\] done (success)' /tmp/caelestia_installer_err.log 2>/dev/null; then
    _reached_done=1
fi

_show_diagnostic=0
_diag_title=""

if [[ $_exit_code -ne 0 ]]; then
    _show_diagnostic=1
    _diag_title="INSTALLER FAILED (exit code: $_exit_code)"
elif [[ $_reached_done -eq 0 ]]; then
    _show_diagnostic=1
    if [[ $_installer_elapsed -lt 3 ]]; then
        _diag_title="INSTALLER EXITED PREMATURELY (ran ${_installer_elapsed}s, exit 0)"
    else
        _diag_title="INSTALLER EXITED UNEXPECTEDLY (no completion marker)"
    fi
fi

if [[ $_show_diagnostic -eq 1 ]]; then
    stty sane 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf '\033[0m\033[?1049l\033[?25h' 2>/dev/null || true

    echo ""
    echo "============================================================"
    echo "  $_diag_title"
    echo "============================================================"
    echo ""

    if [[ -s /tmp/caelestia_installer_err.log ]]; then
        echo "--- stderr output ---"
        cat /tmp/caelestia_installer_err.log
        echo "--- end stderr ------"
        echo ""
    else
        echo "(no stderr output captured)"
        echo ""
    fi

    if [[ $_exit_code -eq 139 ]]; then
        echo "Exit code 139 = SIGSEGV (segmentation fault / memory crash)."
    elif [[ $_exit_code -eq 127 ]]; then
        echo "Exit code 127 = command not found (missing shared library or binary)."
    elif [[ $_exit_code -eq 134 ]] || [[ $_exit_code -eq 135 ]]; then
        echo "Exit code $_exit_code = SIGABRT (aborted, possible assertion failure)."
    elif [[ $_exit_code -eq 0 ]] && [[ $_reached_done -eq 0 ]]; then
        echo "Binary exited cleanly (code 0) but never reached the summary screen."
        echo "This usually means it returned early before phase 6."
    fi
    echo ""

    echo "Press Enter to close this window..."
    read -r
fi

exit $_exit_code
