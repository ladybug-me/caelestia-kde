#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"
# shellcheck source=scripts/lib/matugen.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/matugen.sh"

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
    elif [[ "$BASE_DISTRO" == "opensuse" ]]; then
        caelestia_sudo zypper --non-interactive install python3 python3-pip
    else
        warn "Could not determine the distro for Python tooling installation."
    fi
fi

echo
info "Ensuring the palette generator"
if ensure_matugen; then
    ok "Palette generator ready."
else
    warn "matugen installation failed: wallpapers and schemes cannot generate a palette."
    info "  Arch:   sudo pacman -S matugen"
    info "  Fedora: sudo dnf copr enable avengemedia/danklinux && sudo dnf install matugen"
    info "  openSUSE: cargo install matugen (the installer attempts this for you)"
    info "  Debian: cargo install matugen (the installer builds it for you)"
fi

echo
ok "Package installation complete."
