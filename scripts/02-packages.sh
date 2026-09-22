#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"

echo

info "Ensuring Python tooling for konsave backups"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -m pip --version >/dev/null 2>&1; then
    if [[ "$BASE_DISTRO" == "arch" ]]; then
        caelestia_sudo pacman -S --needed --noconfirm python python-pip
    elif [[ "$BASE_DISTRO" == "fedora" ]]; then
        caelestia_sudo dnf install -y python3 python3-pip
    elif [[ "$BASE_DISTRO" == "debian" ]]; then
        caelestia_sudo apt-get update && caelestia_sudo apt-get install -y python3 python3-pip python3-venv
    else
        warn "Could not determine the distro for Python tooling installation."
    fi
fi

echo
info "Ensuring the palette generator"
export PATH="$HOME/.cargo/bin:$PATH"
if command -v matugen >/dev/null 2>&1; then
    ok "matugen is installed."
else
    if [[ "$BASE_DISTRO" == "fedora" ]]; then
        info "Installing matugen for Fedora..."
        if caelestia_sudo dnf install -y matugen 2>/dev/null; then
            ok "matugen is installed via dnf."
        else
            if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
                caelestia_sudo dnf install -y cargo rust || true
            fi
            cargo install matugen || true
            if command -v matugen >/dev/null 2>&1; then
                ok "matugen is installed."
                if [[ -f "$HOME/.cargo/bin/matugen" ]]; then
                    caelestia_sudo cp "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen 2>/dev/null || true
                fi
                for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
                    grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' "$rc" 2>/dev/null || echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc" 2>/dev/null || true
                done
                fish -c 'fish_add_path ~/.cargo/bin' >/dev/null 2>&1 || true
            else
                mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
                echo "matugen" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"
                warn "matugen installation failed: wallpapers and schemes cannot generate a palette."
            fi
        fi
    else
        warn "matugen is not installed: wallpapers and schemes cannot generate a palette."
        mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
        echo "matugen" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"
        info "  Arch:   sudo pacman -S matugen"
        info "  Fedora: cargo install matugen"
        info "  Debian: cargo install matugen (the installer builds it for you)"
    fi
fi

echo
ok "Package installation complete."
