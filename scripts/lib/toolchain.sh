#!/usr/bin/env bash
# toolchain.sh - build-tool prerequisites for the install/update step scripts.
#
# Source alongside lib/privileges.sh, which provides caelestia_sudo.
#
#   linguist_tools_available   Is Qt's lrelease reachable?
#   install_linguist_tools     Install it through caelestia_sudo
#   install_cava_sdk           Download & extract prebuilt CAVA SDK tarball
#
# Helpers never log; callers decide what to tell the user.

# linguist_tools_available
#
# True when `lrelease` runs, from PATH or from the location distros use when
# they keep the Qt tools out of PATH.
linguist_tools_available() {
    local fallback="${CAELESTIA_LRELEASE_FALLBACK:-/usr/lib/qt6/bin/lrelease}"

    command -v lrelease >/dev/null 2>&1 || [[ -x "$fallback" ]]
}

# install_linguist_tools
#
# Install Qt's Linguist tools so CMake can compile the translation catalogs.
# Without lrelease CMake only warns and the shell ships English regardless of
# the catalogs in shell/translations.
#
# Goes through caelestia_sudo, not plain sudo: this also runs from a GUI-driven
# update with no controlling terminal, where bare sudo has nothing to prompt on
# and fails silently (#664).
#
# Returns 0 when the tools are present or were installed, 1 otherwise.
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

# install_cava_sdk [distro]
#
# Download and extract the prebuilt CAVA SDK (libcava + headers) from CAVA's
# continuous release. Distro defaults to $BASE_DISTRO or the detected package
# manager.
#
# Returns 0 on success, 1 on failure.
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
