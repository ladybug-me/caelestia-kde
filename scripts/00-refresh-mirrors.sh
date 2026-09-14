#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

BASE_DISTRO="${BASE_DISTRO:-unknown}"

is_cachyos() {
    local os_id=""
    local os_like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"
        os_like="${ID_LIKE:-}"
    fi
    [[ "$os_id" == "cachyos" || " $os_like " == *" cachyos "* ]]
}

case "$BASE_DISTRO" in
    arch)
        if [[ -f /etc/pacman.conf ]]; then
            if grep -q '^#\?ParallelDownloads' /etc/pacman.conf; then
                sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
            else
                echo "ParallelDownloads = 5" | sudo tee -a /etc/pacman.conf >/dev/null
            fi
        fi

        if is_cachyos; then
            if command -v cachyos-rate-mirrors >/dev/null 2>&1; then
                info "Ranking CachyOS mirrors..."
                sudo cachyos-rate-mirrors >/dev/null 2>&1 || \
                    warn "cachyos-rate-mirrors failed, continuing with current mirrors."
            else
                warn "cachyos-rate-mirrors is not installed; continuing with current mirrors."
            fi
        else
            if ! command -v reflector >/dev/null 2>&1; then
                sudo pacman -Sy --noconfirm reflector >/dev/null 2>&1 || true
            fi
            if command -v reflector >/dev/null 2>&1; then
                info "Ranking Arch mirrors by download speed..."
                sudo reflector --latest 20 --protocol https --sort rate \
                    --save /etc/pacman.d/mirrorlist >/dev/null 2>&1 || \
                    warn "reflector failed, continuing with current mirrors."
            fi
        fi

        info "Refreshing pacman package databases..."
        sudo pacman -Sy --noconfirm >/dev/null 2>&1 || \
            warn "Failed to refresh pacman sources. Continuing..."
        ;;
    fedora)
        info "Refreshing Fedora repository metadata with DNF..."
        sudo dnf makecache --refresh >/dev/null 2>&1 || \
            warn "Failed to refresh DNF metadata. Continuing..."
        ;;
    debian)
        info "Refreshing Debian repository metadata with APT..."
        sudo apt-get update >/dev/null 2>&1 || \
            warn "Failed to refresh APT metadata. Continuing..."
        ;;
    *)
        warn "Unknown distro '${BASE_DISTRO}'. Skipping mirror refresh."
        ;;
esac

info "Finished mirror refresh step."
