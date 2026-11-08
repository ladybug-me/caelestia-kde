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

# The copy is the thing a same-user writer would race: a font that is a file when it is
# checked can be a link by the time root opens it. The helper opens each source with
# O_NOFOLLOW, so the test asks the shim what it was actually asked to run.
test_mirror_login_fonts_copies_each_font_without_following_a_link() {
    local tmp log
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    mkdir -p "$tmp/.local/share/fonts"
    printf 'font-data\n' > "$tmp/.local/share/fonts/Rubik-VariableFont_wght.ttf"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        CAELESTIA_LOGIN_FONT_DIR="$tmp/share/fonts/caelestia"
        caelestia_sudo() {
            printf '%s\n' "$*" >> "$log"
            "$@"
        }
        fc-cache() { return 0; }
        export -f caelestia_sudo fc-cache

        mirror_login_fonts
    ) || fail "mirror_login_fonts should succeed when a theme font is present"

    assert_file_contains "$log" 'dd if=' "the font should be copied without following a link"
    assert_file_contains "$log" 'iflag=nofollow' "which is what makes the copy refuse one"
    assert_file_contains "$log" 'chmod 0644' "and the mirrored font should stay readable"
    assert_file_not_contains "$log" 'install -m 644' "install follows a link, so it must not do the copy"
    assert_eq "font-data" "$(cat "$tmp/share/fonts/caelestia/Rubik-VariableFont_wght.ttf")" \
        "the font's contents should land in the system font directory"
}

test_mirror_login_fonts_skips_a_symlinked_font() {
    local tmp out
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.local/share/fonts"
    printf 'elsewhere\n' > "$tmp/elsewhere.ttf"
    ln -s "$tmp/elsewhere.ttf" "$tmp/.local/share/fonts/MaterialSymbolsRounded.ttf"
    : > "$tmp/.local/share/fonts/CaskaydiaCoveNerdFont-Regular.ttf"

    out="$(
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        CAELESTIA_LOGIN_FONT_DIR="$tmp/share/fonts/caelestia"
        caelestia_sudo() { "$@"; }
        fc-cache() { return 0; }
        export -f caelestia_sudo fc-cache

        mirror_login_fonts 2>&1
    )"

    assert_contains "$out" "Skipping symlinked font" "the link should be reported, not mirrored"
    assert_file_missing "$tmp/share/fonts/caelestia/MaterialSymbolsRounded.ttf" \
        "a link is not the font that was downloaded"
    assert_file_exists "$tmp/share/fonts/caelestia/CaskaydiaCoveNerdFont-Regular.ttf" \
        "while a real file beside it is still mirrored"
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
