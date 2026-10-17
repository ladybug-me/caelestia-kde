#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"
# shellcheck source=scripts/lib/matugen.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/matugen.sh"
# shellcheck source=scripts/lib/skwd-wall.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/skwd-wall.sh"
# shellcheck source=scripts/lib/plasma-audio-visualizer.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/plasma-audio-visualizer.sh"

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
if ensure_matugen; then
    ok "Palette generator ready."
else
    warn "matugen installation failed: wallpapers and schemes cannot generate a palette."
    info "  Arch:   sudo pacman -S matugen"
    info "  Fedora: sudo dnf copr enable avengemedia/danklinux && sudo dnf install matugen"
    info "  Debian: cargo install matugen (the installer builds it for you)"
fi

echo
info "Ensuring wallpaper selector (skwd-wall)"
if ensure_skwd_wall; then
    ok "Wallpaper selector ready."
else
    warn "skwd-wall installation failed."
    info "  Arch:   yay -S skwd-wall-v2-bin skwd-lens-bin skwd-paper-plasma"
    info "  Fedora: sudo dnf copr enable piixini/skwd-wall-v2 && sudo dnf install skwd-wall-v2 skwd-lens skwd-paper-plasma"
fi

echo
info "Ensuring plasma audio visualizer"
if ensure_plasma_audio_visualizer; then
    ok "Audio visualizer ready."
else
    warn "plasma-audio-visualizer installation failed."
    info "  Arch:   yay -S plasma6-applets-audio-visualizer"
    info "  Fedora: https://software.opensuse.org//download.html?project=home%3Aluisbocanegra&package=plasma-audio-visualizer"
fi

echo
ok "Package installation complete."
