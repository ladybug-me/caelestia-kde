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
# shellcheck source=scripts/lib/download.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/download.sh" 2>/dev/null || true

# Where a font a user downloaded belongs. The installers and the login-screen mirror both
# need it, and a second spelling of it is how the two drift apart.
user_font_dir() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
}

# Copies a downloaded font into the user's font directory, once the transfer is known to
# have produced a font. The branch URL the Material Symbols font comes from publishes no
# hash, so the file's type is what says the bytes are the font that was asked for rather
# than an error page saved under a font's name; the hash is printed either way, so a run
# records what it installed.
install_checked_font() {
    local source="$1" name="$2" dest kind hash

    dest="$(user_font_dir)"
    if [[ ! -s "$source" ]]; then
        err "Refusing to install $name: the download is empty."
        return 1
    fi
    if command -v file >/dev/null 2>&1; then
        kind="$(file -b "$source" 2>/dev/null || true)"
        case "$kind" in
            *TrueType*|*OpenType*) ;;
            *)
                err "Refusing to install $name: it is not a TrueType or OpenType font ($kind)."
                return 1
                ;;
        esac
    fi
    hash="$(file_sha256 "$source")"
    if ! mkdir -p "$dest" || ! mv -f "$source" "$dest/$name" 2>/dev/null; then
        err "Failed to install $name into $dest."
        return 1
    fi
    info "$name installed (SHA-256 $hash)."
}

# A version-pinned archive is only unpacked once its bytes are the ones the version names.
# The project publishes no checksum beside the archive, so the hash is a constant.
nerd_font_archive_matches() {
    local archive="$1" expected="$2" name="$3" actual
    actual="$(file_sha256 "$archive")"
    if [[ "$actual" != "$expected" ]]; then
        err "Checksum mismatch for $name - not extracting it (got $actual, expected $expected)."
        return 1
    fi
    info "$name matches the pinned SHA-256."
}

# Mirrors the fonts downloaded into the user's font directory into a system-wide
# one, so the login screen picks them up instead of falling back to fonts that
# lack the Material Symbols and Nerd Font glyphs.
mirror_login_fonts() {
    local dest="${CAELESTIA_LOGIN_FONT_DIR:-/usr/share/fonts/caelestia}"
    local src
    src="$(user_font_dir)"
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
