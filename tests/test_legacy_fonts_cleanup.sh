#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SHELL="$REPO_ROOT/scripts/08-build-shell.sh"
INSTALL_KIND="$REPO_ROOT/scripts/lib/install-kind.sh"

# The cleanup only ever touches directories under the user's own HOME: the shell tree an
# older install wrote and the asset directory 12-fetch-assets.sh downloaded into. The test
# drives the real function against a throwaway HOME, and lets the step's own
# install_shell_config() resolve the tree path, so what is checked is the path an install
# resolves at run time.
CLEANUP_SOURCE="$(extract_function "$BUILD_SHELL" cleanup_legacy_fonts)"

if [[ -z "$CLEANUP_SOURCE" ]]; then
    fail "could not find cleanup_legacy_fonts in scripts/08-build-shell.sh"
    run_tests
    exit 1
fi

# The step scripts log through lib/log.sh, which this harness does not source.
LOG_STUBS='
ok() { :; }
info() { :; }
warn() { :; }
skip() { :; }
'

run_cleanup() {
    local home="$1"
    HOME="$home" XDG_DATA_HOME="" bash -c "source '$INSTALL_KIND'
${LOG_STUBS}${CLEANUP_SOURCE}
cleanup_legacy_fonts" 2>&1
}

tree_fonts() {
    printf '%s\n' "$1/.config/quickshell/caelestia/assets/fonts"
}

data_fonts() {
    printf '%s\n' "$1/.local/share/caelestia/assets/fonts"
}

# What the two mechanisms could have left behind: the three font directories they copied and
# the tree's own README, with one folder of the user's own beside them and the emoji
# database the same parent directory holds.
seed_legacy_fonts() {
    local home="$1" fonts
    for fonts in "$(tree_fonts "$home")" "$(data_fonts "$home")"; do
        mkdir -p "$fonts/SF-Pro" "$fonts/SF-Mono" "$fonts/google-sans-flex" "$fonts/MyFonts"
        printf 'font\n' > "$fonts/SF-Pro/SF-Pro.ttf"
        printf 'font\n' > "$fonts/SF-Mono/SF-Mono-Regular.otf"
        printf 'font\n' > "$fonts/google-sans-flex/GoogleSansFlex-Subset.ttf"
        printf 'font\n' > "$fonts/MyFonts/MyFont.ttf"
        printf '# Fonts\n\nThe shell loads every .ttf/.otf found here at startup.\n' > "$fonts/README.md"
        printf 'emoji\n' > "$(dirname -- "$fonts")/emojis.txt"
    done
}

test_the_fonts_an_older_install_left_go() {
    local home fonts
    home="$(new_tmpdir)"
    seed_legacy_fonts "$home"

    run_cleanup "$home" >/dev/null

    for fonts in "$(tree_fonts "$home")" "$(data_fonts "$home")"; do
        assert_file_missing "$fonts/SF-Pro"
        assert_file_missing "$fonts/SF-Mono"
        assert_file_missing "$fonts/google-sans-flex"
        assert_file_missing "$fonts/README.md"
    done
}

test_the_users_own_font_folder_and_emoji_database_stay() {
    local home fonts
    home="$(new_tmpdir)"
    seed_legacy_fonts "$home"

    run_cleanup "$home" >/dev/null

    for fonts in "$(tree_fonts "$home")" "$(data_fonts "$home")"; do
        assert_file_exists "$fonts/MyFonts/MyFont.ttf"
        assert_file_exists "$(dirname -- "$fonts")/emojis.txt"
    done
}

test_only_the_shipped_readme_is_removed() {
    local home fonts
    home="$(new_tmpdir)"
    fonts="$(data_fonts "$home")"
    mkdir -p "$fonts"
    printf 'mine\n' > "$fonts/MyFont.ttf"
    printf '# My own font notes\n' > "$fonts/README.md"

    run_cleanup "$home" >/dev/null

    assert_file_exists "$fonts"
    assert_file_exists "$fonts/MyFont.ttf"
    assert_file_exists "$fonts/README.md"
}

test_a_machine_that_never_installed_fonts_is_a_no_op() {
    local home status
    home="$(new_tmpdir)"

    run_cleanup "$home" >/dev/null
    status=$?

    assert_status 0 "$status" "the cleanup should not fail when there is nothing to remove"
    assert_file_missing "$(tree_fonts "$home")"
    assert_file_missing "$(data_fonts "$home")"
}

test_a_fonts_directory_goes_once_it_is_empty() {
    local home fonts
    home="$(new_tmpdir)"
    fonts="$(tree_fonts "$home")"
    mkdir -p "$fonts/SF-Pro"
    printf 'font\n' > "$fonts/SF-Pro/SF-Pro.ttf"
    printf 'emoji\n' > "$(dirname -- "$fonts")/emojis.txt"

    run_cleanup "$home" >/dev/null

    assert_file_missing "$fonts"
    assert_file_exists "$(dirname -- "$fonts")/emojis.txt"
}

run_tests
