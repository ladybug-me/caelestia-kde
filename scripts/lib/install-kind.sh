#!/usr/bin/env bash
# install-kind.sh - which half of an install a run is doing, and where that
# half keeps its files.
#
# A checkout (install.sh + the TUI) owns user files. A package owns everything
# under /usr and /etc, including files an older installer wrote there, so a
# package run must not touch those. The step scripts ask here rather than
# guessing from what they find.
#
#   CAELESTIA_INSTALL_KIND=source|package   set by the front end running the steps
#   install_kind                            prints which one this run is
#   install_is_packaged                     true when a package owns the files
#
# Unset falls back to where this library sits: under $HOME = source, under /usr =
# package, which keeps a step run by hand honest about which install it belongs
# to. Both halves stay one implementation of the steps (parity-6); this only
# decides which of their own sections apply.
if [[ -z "${CAELESTIA_INSTALL_KIND_SOURCED:-}" ]]; then
CAELESTIA_INSTALL_KIND_SOURCED=1

install_kind() {
    case "${CAELESTIA_INSTALL_KIND:-}" in
        source | package)
            printf '%s\n' "$CAELESTIA_INSTALL_KIND"
            return 0
            ;;
    esac

    local lib_dir
    lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    case "$lib_dir" in
        /usr/*) printf 'package\n' ;;
        *) printf 'source\n' ;;
    esac
}

install_is_packaged() {
    [[ "$(install_kind)" == "package" ]]
}

# Where that half keeps its files - the single definition of the layout.
# `src/bin/caelestia` sources this file for these too, so the command and the
# steps cannot drift. Named functions rather than one string-keyed lookup: the
# callers want five different things.
#
# `caelestia` used to carry the checkout paths unconditionally, so on a packaged
# machine it put a leftover ~/.config/quickshell/caelestia ahead of the installed
# /etc/xdg one for everything it spawned.
# The palette's templates and named schemes.
install_lib_dir() {
    if install_is_packaged; then
        printf '%s\n' /usr/lib/caelestia
    else
        printf '%s\n' "$HOME/.local/lib/caelestia"
    fi
}

# Where the helper commands live.
install_bin_dir() {
    if install_is_packaged; then
        printf '%s\n' /usr/bin
    else
        printf '%s\n' "$HOME/.local/bin"
    fi
}

# QML2_IMPORT_PATH entries for the shell's own tree and its plugin modules.
install_qml_import_path() {
    if install_is_packaged; then
        printf '%s\n' "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia"
    else
        printf '%s\n' "$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia"
    fi
}

# The shell's entrypoint, which is what the autostart unit runs.
install_shell_config() {
    if install_is_packaged; then
        printf '%s\n' /etc/xdg/quickshell/caelestia/shell.qml
    else
        printf '%s\n' "$HOME/.config/quickshell/caelestia/shell.qml"
    fi
}

# The shell's assets beside the entrypoint. 12-fetch-assets.sh writes the fonts
# here; Fonts.qml also looks in the user's own directory.
install_assets_dir() {
    printf '%s\n' "$(dirname -- "$(install_shell_config)")/assets"
}

fi
