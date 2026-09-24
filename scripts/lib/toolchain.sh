#!/usr/bin/env bash
# The build toolchain's own dependencies: the Qt Linguist tools the translations step
# needs, and the prebuilt CAVA SDK the shell links against. Nothing here knows which
# distro it is on beyond the name its caller passes in.

source "$(dirname "${BASH_SOURCE[0]}")/download.sh"
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# Fork identity: the owner publishing release artifacts (the prebuilt CAVA
# SDK below). Upstream default stays ladybug-me; a fork that does not publish
# binaries points this at the owner whose releases it ships.
: "${CAELESTIA_PREBUILT_OWNER:=ladybug-me}"

# What the shell build can link against, in the same words 08-build-shell.sh stores
# in its toolchain stamp: a pkg-config version, "sdk" for the prebuilt headers, or
# "none". One probe, so the stamp and the guard cannot disagree.
cava_state() {
    local version=""
    if command -v pkg-config >/dev/null 2>&1; then
        version="$(pkg-config --modversion libcava 2>/dev/null || pkg-config --modversion cava 2>/dev/null || true)"
    fi
    if [[ -n "$version" ]]; then
        printf '%s\n' "$version"
    elif [[ -f /usr/include/cava/cavacore.h ]]; then
        printf 'sdk\n'
    else
        printf 'none\n'
    fi
}

cava_sdk_installed() {
    [[ "$(cava_state)" != "none" ]]
}

linguist_tools_available() {
    local fallback="${CAELESTIA_LRELEASE_FALLBACK:-/usr/lib/qt6/bin/lrelease}"

    command -v lrelease >/dev/null 2>&1 || [[ -x "$fallback" ]]
}

# install_linguist_tools <arch|fedora|debian>
#
# Takes the distro for the same reason install_cava_sdk does: "whichever manager is on
# PATH" answers for the wrong package universe on a machine with a second one installed.
install_linguist_tools() {
    local distro="${1:-}"

    if linguist_tools_available; then
        return 0
    fi

    case "$distro" in
        arch) caelestia_sudo pacman -S --needed --noconfirm qt6-tools ;;
        fedora) caelestia_sudo dnf install -y qt6-qttools-devel ;;
        debian) caelestia_sudo apt-get install -y qt6-l10n-tools qt6-tools-dev ;;
        *) return 1 ;;
    esac
}

# install_cava_sdk <arch|fedora|debian>
#
# Unpacks the prebuilt SDK into /usr, which needs escalation. Callers that cannot
# know the SDK is missing should ask cava_sdk_installed first: this asks for a
# password, and asking for one to re-unpack what is already there is a password for
# nothing. The archive is only unpacked when the release publishes a matching
# checksum beside it and its listing stays inside include/, lib/ and bin/; anything
# else is left to the caller's distro-package fallback.
install_cava_sdk() {
    local distro="${1:-}"

    local asset_suffix
    case "$distro" in
        arch) asset_suffix="arch" ;;
        fedora) asset_suffix="fedora" ;;
        debian|ubuntu) asset_suffix="ubuntu" ;;
        *) return 1 ;;
    esac

    local arch="${CAELESTIA_TARGET_ARCH:-}"
    if [[ -z "$arch" ]]; then
        arch="$(uname -m 2>/dev/null || echo "x86_64")"
    fi

    local url="https://github.com/${CAELESTIA_PREBUILT_OWNER}/cava/releases/download/continuous/cava-${arch}-${asset_suffix}.tar.gz"
    local archive status=0
    archive="$(mktemp)"

    if ! fetch_asset "$url" "$archive" 2>/dev/null; then
        rm -f "$archive"
        return 1
    fi

    # The archive is unpacked into /usr, so both checksum failures refuse it -
    # a mismatch (1) and a missing sidecar (2) alike, exactly like the prebuilt
    # installer binary in setup.sh. Callers fall back to a distro package.
    verify_download "$url" "$archive" || status=$?
    if [[ "$status" -ne 0 ]]; then
        if [[ "$status" -eq 1 ]]; then
            warn "Checksum mismatch for $url - not unpacking it."
        else
            warn "No published checksum for $url - not unpacking it."
        fi
        rm -f "$archive"
        return 1
    fi

    # It may only hold the trees an SDK ships into /usr: include/, lib/ and the
    # bin/ the extraction itself excludes. Everything else - a member with a
    # ".." component, an absolute path, a link pointing outside, or a tree that
    # has no business in /usr - is refused before tar runs as root.
    if ! archive_is_safe "$archive" include lib bin; then
        warn "Refusing to unpack $url into /usr: unexpected archive content."
        rm -f "$archive"
        return 1
    fi

    local tar_cmd=(tar --no-same-owner --exclude='bin' -C /usr -xzf "$archive")
    if [[ "$EUID" -ne 0 ]]; then
        if command -v caelestia_sudo >/dev/null 2>&1; then
            tar_cmd=(caelestia_sudo "${tar_cmd[@]}")
        elif command -v sudo >/dev/null 2>&1; then
            tar_cmd=(sudo "${tar_cmd[@]}")
        fi
    fi

    "${tar_cmd[@]}" 2>/dev/null || status=$?
    rm -f "$archive"
    return "$status"
}
