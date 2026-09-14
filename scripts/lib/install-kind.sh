#!/usr/bin/env bash
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

install_lib_dir() {
    if install_is_packaged; then
        printf '%s\n' /usr/lib/caelestia
    else
        printf '%s\n' "$HOME/.local/lib/caelestia"
    fi
}

install_bin_dir() {
    if install_is_packaged; then
        printf '%s\n' /usr/bin
    else
        printf '%s\n' "$HOME/.local/bin"
    fi
}

install_qml_import_path() {
    if install_is_packaged; then
        printf '%s\n' "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia"
    else
        printf '%s\n' "$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia"
    fi
}

install_shell_config() {
    if install_is_packaged; then
        printf '%s\n' /etc/xdg/quickshell/caelestia/shell.qml
    else
        printf '%s\n' "$HOME/.config/quickshell/caelestia/shell.qml"
    fi
}

install_assets_dir() {
    printf '%s\n' "$(dirname -- "$(install_shell_config)")/assets"
}

fi
