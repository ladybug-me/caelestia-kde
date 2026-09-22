#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

if [[ "$BASE_DISTRO" == "arch" ]]; then
    ensure_yay() {
        if command -v yay >/dev/null 2>&1; then
            ok "yay is already installed."
            return 0
        fi

        info "yay not found, installing..."

        if ! command -v pacman >/dev/null 2>&1; then
            die "pacman not found. This installer requires Arch Linux."
        fi

        caelestia_sudo pacman -S --needed --noconfirm base-devel git

        local tmpdir
        tmpdir="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmpdir"
        (
            cd "$tmpdir" || exit 1
            makepkg -si --noconfirm
        )
        rm -rf "$tmpdir"
        ok "yay installed."
    }

    ensure_yay

    info "Enabling ccache for makepkg builds (caches AUR rebuilds)..."
    if ! command -v ccache >/dev/null 2>&1; then
        info "ccache not found, installing..."
        caelestia_sudo pacman -S --needed --noconfirm ccache
    fi
    if [[ -f /etc/makepkg.conf ]] && grep -q '!ccache' /etc/makepkg.conf; then
        info "Enabling ccache in /etc/makepkg.conf (system-wide makepkg setting)..."
        mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
        touch "${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/ccache-enabled"
        caelestia_sudo sed -i 's/!ccache/ccache/' /etc/makepkg.conf
    fi
    ok "makepkg ccache configured."

    info "Configuring yay sudo looping and disabling interactive menus..."
    yay -Y --sudoloop --nocleanmenu --nodiffmenu --save 2>/dev/null || true
    ok "yay configured."

elif [[ "$BASE_DISTRO" == "fedora" ]]; then
    info "Checking for Fedora prerequisites (dnf, yq, createrepo_c, jq)..."

    if ! command -v dnf >/dev/null 2>&1; then
        die "dnf not found. This installer requires Fedora 42 or later."
    fi

    if command -v yq >/dev/null 2>&1 && command -v createrepo_c >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        ok "Prerequisites are already installed."
    else
        info "Missing prerequisites, installing..."
        caelestia_sudo dnf install -y yq createrepo_c jq
        ok "Prerequisites installed."
    fi
elif [[ "$BASE_DISTRO" == "debian" ]]; then
    info "Checking for Debian prerequisites (apt-get, yq, jq, build-essential)..."

    if ! command -v apt-get >/dev/null 2>&1; then
        die "apt-get not found. This installer requires a Debian-based distribution."
    fi

    if command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
        ok "Prerequisites are already installed."
    else
        info "Missing prerequisites, installing..."
        caelestia_sudo apt-get update
        caelestia_sudo apt-get install -y yq jq build-essential git curl
        ok "Prerequisites installed."
    fi
fi
