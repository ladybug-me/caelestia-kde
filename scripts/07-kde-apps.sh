#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

echo
echo ""
info "Installing KDE theme applications"
echo ""

install_if_missing() {
    local pkg="$1"
    if [[ "$BASE_DISTRO" == "arch" ]]; then
        if pacman -Qi "$pkg" >/dev/null 2>&1; then
            skip "$pkg already installed."
            return 0
        fi
        info "Installing $pkg..."
        yay -S --needed ${CONFIRM_ARG:-} "$pkg" 2>/dev/null || \
        sudo pacman -S --needed ${CONFIRM_ARG:-} "$pkg" 2>/dev/null || {
            warn "Could not install $pkg, skipping."
            return 1
        }
        ok "$pkg installed."
    elif [[ "$BASE_DISTRO" == "fedora" ]]; then
        if dnf list --installed "$pkg" >/dev/null 2>&1; then
            skip "$pkg already installed."
            return 0
        fi
        info "Installing $pkg..."
        sudo dnf install -y "$pkg" 2>/dev/null || {
            warn "Could not install $pkg, skipping."
            return 1
        }
        ok "$pkg installed."
    elif [[ "$BASE_DISTRO" == "debian" ]]; then
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            skip "$pkg already installed."
            return 0
        fi
        info "Installing $pkg..."
        sudo apt-get install -y "$pkg" 2>/dev/null || {
            warn "Could not install $pkg, skipping."
            return 1
        }
        ok "$pkg installed."
    fi
}

if [[ "${INSTALL_KVANTUM:-true}" == "true" ]]; then
    if [[ "$BASE_DISTRO" == "debian" ]]; then
        install_if_missing qt6-style-kvantum || install_if_missing kvantum
        install_if_missing qt5-style-kvantum || true
    else
        install_if_missing kvantum
        install_if_missing kvantum-qt5 || true
    fi
else
    skip "Skipping Kvantum installation by user choice."
fi

kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

echo "[OK]  KDE extra apps step complete."
