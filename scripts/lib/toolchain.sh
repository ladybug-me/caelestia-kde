#!/usr/bin/env bash

linguist_tools_available() {
    local fallback="${CAELESTIA_LRELEASE_FALLBACK:-/usr/lib/qt6/bin/lrelease}"

    command -v lrelease >/dev/null 2>&1 || [[ -x "$fallback" ]]
}

install_linguist_tools() {
    if linguist_tools_available; then
        return 0
    fi

    if command -v pacman >/dev/null 2>&1; then
        caelestia_sudo pacman -S --needed --noconfirm qt6-tools
    elif command -v dnf >/dev/null 2>&1; then
        caelestia_sudo dnf install -y qt6-qttools-devel
    elif command -v apt-get >/dev/null 2>&1; then
        caelestia_sudo apt-get install -y qt6-l10n-tools qt6-tools-dev
    else
        return 1
    fi
}

install_cava_sdk() {
    local arch="${CAELESTIA_TARGET_ARCH:-}"
    if [[ -z "$arch" ]]; then
        arch="$(uname -m 2>/dev/null || echo "x86_64")"
    fi

    local distro="${1:-${BASE_DISTRO:-}}"
    if [[ -z "$distro" ]]; then
        if command -v pacman >/dev/null 2>&1; then
            distro="arch"
        elif command -v dnf >/dev/null 2>&1; then
            distro="fedora"
        elif command -v apt-get >/dev/null 2>&1; then
            distro="ubuntu"
        fi
    fi

    local asset_suffix
    case "$distro" in
        arch) asset_suffix="arch" ;;
        fedora) asset_suffix="fedora" ;;
        debian|ubuntu) asset_suffix="ubuntu" ;;
        *) return 1 ;;
    esac

    local url="https://github.com/ladybug-me/cava/releases/download/continuous/cava-${arch}-${asset_suffix}.tar.gz"
    local tar_cmd=(tar -C /usr -xzf - --exclude='bin')
    if [[ "$EUID" -ne 0 ]]; then
        if command -v caelestia_sudo >/dev/null 2>&1; then
            tar_cmd=(caelestia_sudo "${tar_cmd[@]}")
        elif command -v sudo >/dev/null 2>&1; then
            tar_cmd=(sudo "${tar_cmd[@]}")
        fi
    fi

    curl -fsSL "$url" | "${tar_cmd[@]}" 2>/dev/null
}
