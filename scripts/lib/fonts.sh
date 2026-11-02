#!/usr/bin/env bash
# Helper for making the theme fonts readable by SDDM, which runs as its own
# user and never reads the user's font directory.
if [[ -z "${CAELESTIA_FONTS_SOURCED:-}" ]]; then
CAELESTIA_FONTS_SOURCED=1

# shellcheck source=scripts/lib/log.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/log.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/privileges.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/privileges.sh" 2>/dev/null || true

# Mirrors the fonts downloaded into the user's font directory into a system-wide
# one, so the login screen picks them up instead of falling back to fonts that
# lack the Material Symbols and Nerd Font glyphs.
mirror_login_fonts() {
    local dest="${CAELESTIA_LOGIN_FONT_DIR:-/usr/share/fonts/caelestia}"
    local src="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
    local theme_fonts=()

    if ! caelestia_sudo install -d -m 755 "$dest"; then
        err "Failed to create $dest."
        return 1
    fi

    shopt -s nullglob
    theme_fonts=("$src"/MaterialSymbolsRounded.ttf "$src"/Rubik-*.ttf "$src"/CaskaydiaCove*.ttf "$src"/JetBrainsMono*.ttf)
    shopt -u nullglob

    if [[ ${#theme_fonts[@]} -eq 0 ]]; then
        err "No login screen fonts found to mirror system-wide under $src."
        return 1
    fi

    if ! caelestia_sudo install -m 644 "${theme_fonts[@]}" "$dest/"; then
        err "Failed to install the login screen fonts system-wide."
        return 1
    fi

    caelestia_sudo fc-cache -f "$dest" >/dev/null 2>&1 || true
}

fi
