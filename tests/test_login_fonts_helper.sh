#!/usr/bin/env bash

# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/fonts.sh"

test_mirror_login_fonts_installs_the_theme_fonts() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.local/share/fonts"

    local font
    for font in MaterialSymbolsRounded.ttf Rubik-VariableFont_wght.ttf CaskaydiaCoveNerdFont-Regular.ttf JetBrainsMonoNerdFont-Regular.ttf; do
        : > "$tmp/.local/share/fonts/$font"
    done

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        CAELESTIA_LOGIN_FONT_DIR="$tmp/share/fonts/caelestia"
        caelestia_sudo() { "$@"; }
        fc-cache() { return 0; }
        export -f caelestia_sudo fc-cache

        mirror_login_fonts
    ) || fail "mirror_login_fonts should succeed when the theme fonts are present"

    for font in MaterialSymbolsRounded.ttf Rubik-VariableFont_wght.ttf CaskaydiaCoveNerdFont-Regular.ttf JetBrainsMonoNerdFont-Regular.ttf; do
        assert_file_exists "$tmp/share/fonts/caelestia/$font" "expected $font to be mirrored system-wide"
    done
}

test_mirror_login_fonts_fails_without_fonts() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.local/share/fonts"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        CAELESTIA_LOGIN_FONT_DIR="$tmp/share/fonts/caelestia"
        caelestia_sudo() { "$@"; }
        fc-cache() { return 0; }
        export -f caelestia_sudo fc-cache

        mirror_login_fonts
    ) >/dev/null 2>&1 && fail "mirror_login_fonts should fail when no theme fonts were downloaded"
}

test_mirror_login_fonts_fails_when_the_destination_cannot_be_created() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.local/share/fonts"
    : > "$tmp/.local/share/fonts/MaterialSymbolsRounded.ttf"
    # A file where the system font directory should go makes mkdir fail.
    : > "$tmp/share"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        CAELESTIA_LOGIN_FONT_DIR="$tmp/share/fonts/caelestia"
        caelestia_sudo() { "$@"; }
        fc-cache() { return 0; }
        export -f caelestia_sudo fc-cache

        mirror_login_fonts
    ) >/dev/null 2>&1 && fail "mirror_login_fonts should fail when the destination directory cannot be created"
}

run_tests
