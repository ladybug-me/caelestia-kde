#!/usr/bin/env bash
# Helper for making the theme fonts readable by SDDM, which runs as its own
# user and never reads the user's font directory.
if [[ -z "${CAELESTIA_FONTS_SOURCED:-}" ]]; then
CAELESTIA_FONTS_SOURCED=1

# shellcheck source=scripts/lib/log.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/log.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/privileges.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/privileges.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/install-fs.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/install-fs.sh" 2>/dev/null || true

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

    # The source directory is writable by the user, so only what they put there
    # directly is mirrored: a link is not the font they downloaded.
    local candidate
    shopt -s nullglob
    for candidate in "$src"/MaterialSymbolsRounded.ttf "$src"/Rubik-*.ttf "$src"/CaskaydiaCove*.ttf \
        "$src"/JetBrainsMono*.ttf; do
        if regular_file "$candidate"; then
            theme_fonts+=("$candidate")
        elif [[ -L "$candidate" ]]; then
            warn "Skipping symlinked font $candidate."
        fi
    done
    shopt -u nullglob

    if [[ ${#theme_fonts[@]} -eq 0 ]]; then
        err "No login screen fonts found to mirror system-wide under $src."
        return 1
    fi

    # The check above and the copy are two moments, and a file this user can write can be
    # replaced by a link between them. Each source is opened as root with O_NOFOLLOW
    # instead, so what lands in the system font directory is the file that was checked.
    local font
    for font in "${theme_fonts[@]}"; do
        if ! privileged_copy_file "$font" "$dest/$(basename -- "$font")" 0644; then
            err "Failed to install the login screen fonts system-wide."
            return 1
        fi
    done

    caelestia_sudo fc-cache -f "$dest" >/dev/null 2>&1 || true
}

fi
