#!/usr/bin/env bash
# Helper for ensuring matugen is installed across different distributions and migrating
# legacy cargo installations to distro-managed packages where available.
if [[ -z "${CAELESTIA_MATUGEN_SOURCED:-}" ]]; then
CAELESTIA_MATUGEN_SOURCED=1

# shellcheck source=scripts/lib/log.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/log.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/privileges.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/privileges.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/packages.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/packages.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/install-fs.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/install-fs.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/download.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/download.sh" 2>/dev/null || true

# The release the binary comes from, fixed here rather than read from `latest`: what root
# installs is then this project's decision, and the asset names belong to the tag.
MATUGEN_VERSION="4.2.0"

# The pinned release, as "<url>\t<digest>" for the asset this machine needs. InioX publishes
# no .sha256 beside the asset, but GitHub reports a sha256 for each one in the same response
# that names it, so the archive can be checked against the release it came from. Printed as
# one line: callers split on the tab.
matugen_asset_url() {
    local carch="$1" release_json asset name curl jq
    curl="$(system_tool curl)"
    jq="$(system_tool jq)"
    [[ -n "$curl" && -n "$jq" ]] || return 1
    release_json="$("$curl" -fsSL "https://api.github.com/repos/InioX/matugen/releases/tags/v${MATUGEN_VERSION}" 2>/dev/null || true)"
    [[ -n "$release_json" ]] || return 1
    name="matugen-${MATUGEN_VERSION}-${carch}.tar.gz"

    asset="$(printf '%s' "$release_json" | "$jq" -r --arg name "$name" '
        first(.assets[] | select(.name == $name))
        | "\(.browser_download_url // "")\t\(.digest // "")"
    ' 2>/dev/null)"
    [[ -n "$asset" && "$asset" != $'\t' ]] || return 1
    printf '%s\n' "$asset"
}

matugen_present() {
    if ! command -v matugen >/dev/null 2>&1; then
        return 1
    fi
    local ver
    ver="$(matugen --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
    [[ -n "$ver" ]] || return 1
    [[ "$(printf '%s\n%s\n' "4.2" "$ver" | sort -V | head -n1)" == "4.2" ]]
}

cleanup_legacy_cargo_matugen() {
    if [[ -f "/usr/local/bin/matugen" && ! -L "/usr/local/bin/matugen" ]]; then
        local local_ver
        local_ver="$(/usr/local/bin/matugen --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
        if [[ -z "$local_ver" || "$(printf '%s\n%s\n' "4.2" "$local_ver" | sort -V | head -n1)" != "4.2" ]] || package_present matugen; then
            info "Removing legacy /usr/local/bin/matugen binary..."
            caelestia_sudo rm -f "/usr/local/bin/matugen"
        fi
    fi
    if [[ -f "$HOME/.cargo/bin/matugen" ]]; then
        local cargo_ver
        cargo_ver="$("$HOME/.cargo/bin/matugen" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
        if [[ -z "$cargo_ver" || "$(printf '%s\n%s\n' "4.2" "$cargo_ver" | sort -V | head -n1)" != "4.2" ]] || package_present matugen; then
            info "Removing legacy Cargo matugen binary..."
            if command -v cargo >/dev/null 2>&1; then
                cargo uninstall matugen >/dev/null 2>&1 || true
            fi
            rm -f "$HOME/.cargo/bin/matugen"
        fi
    fi
    return 0
}

install_matugen_github() {
    info "Fetching matugen $MATUGEN_VERSION binary from GitHub releases..."
    local arch carch="x86_64"
    arch="$(uname -m 2>/dev/null || echo "x86_64")"
    case "$arch" in
        x86_64)          carch="x86_64" ;;
        aarch64|arm64)   carch="aarch64" ;;
        armv7*|armhf)    carch="armv7" ;;
        *)               carch="x86_64" ;;
    esac

    local dl_url tmpdir="" archive asset digest=""
    dl_url="https://github.com/InioX/matugen/releases/download/v${MATUGEN_VERSION}/matugen-${MATUGEN_VERSION}-${carch}.tar.gz"

    # The asset URL and the digest beside it come from the pinned tag, so a release that
    # moved the asset cannot change what is downloaded or how it is checked. When the API
    # cannot answer, the URL above still stands and the checksum falls back to a sidecar.
    if asset="$(matugen_asset_url "$carch")"; then
        IFS=$'\t' read -r dl_url digest <<< "$asset"
    fi

    tmpdir="$(mktemp -d)"
    archive="$tmpdir/matugen.tar.gz"
    if ! fetch_verified_asset "$dl_url" "$archive" "$digest" install; then
        rm -rf "$tmpdir"
        return 1
    fi

    # tar takes the member names as they are, so an archive with a `..` or an absolute
    # path writes outside the directory it is handed. Nothing in it is needed with the
    # owner or the mode the archive carries either.
    if ! archive_entries_are_safe "$archive"; then
        warn "Refusing to unpack $dl_url: the archive has setuid, setgid or escaping entries."
        rm -rf "$tmpdir"
        return 1
    fi

    if tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$tmpdir" 2>/dev/null; then
        # A tarball can carry a symlink in place of the binary, and `install`
        # would follow it as root. Only a file the archive really holds is used.
        if regular_file "$tmpdir/matugen"; then
            if caelestia_sudo install -m 755 "$tmpdir/matugen" /usr/local/bin/matugen 2>/dev/null; then
                rm -rf "$tmpdir"
                ok "matugen installed successfully to /usr/local/bin from GitHub release."
                return 0
            fi
            mkdir -p "$HOME/.local/bin"
            install -m 755 "$tmpdir/matugen" "$HOME/.local/bin/matugen"
            rm -rf "$tmpdir"
            ok "matugen installed successfully to $HOME/.local/bin from GitHub release."
            return 0
        fi
    fi

    rm -rf "$tmpdir"
    return 1
}

install_matugen_cargo() {
    info "Attempting to install matugen via Cargo..."
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

    if ! command -v cargo >/dev/null 2>&1; then
        case "${BASE_DISTRO:-unknown}" in
            fedora)
                caelestia_sudo dnf install -y cargo rust || true
                ;;
            debian)
                caelestia_sudo apt-get install -y cargo rustc || true
                ;;
            arch)
                caelestia_sudo pacman -S --needed --noconfirm rust cargo 2>/dev/null || true
                ;;
        esac

        if ! command -v cargo >/dev/null 2>&1; then
            info "Installing Rust toolchain via rustup..."
            # The installer is written to a file this user named rather than piped into a
            # shell, so a transfer that stops halfway cannot leave half a script executing
            # and the hash of the one that does run ends up in the log.
            local rustup_script
            rustup_script="$(mktemp)"
            if fetch_asset https://sh.rustup.rs "$rustup_script" --proto '=https' --tlsv1.2 2>/dev/null; then
                info "rustup installer SHA-256: $(file_sha256 "$rustup_script")"
                sh -s -- -y --default-toolchain stable --profile minimal < "$rustup_script" || true
            else
                warn "Could not download the rustup installer; install Rust yourself from https://rustup.rs and re-run the installer."
            fi
            rm -f "$rustup_script"
            export PATH="$HOME/.cargo/bin:$PATH"
        fi
    fi

    if command -v cargo >/dev/null 2>&1 && cargo install matugen; then
        # ~/.cargo/bin is the user's, and both `cp` and `install` follow a symlink: only a
        # file cargo wrote there itself is promoted, and root opens it with O_NOFOLLOW
        # rather than following a link planted between the check and the copy.
        if regular_file "$HOME/.cargo/bin/matugen"; then
            privileged_copy_file "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen 0755 2>/dev/null || {
                mkdir -p "$HOME/.local/bin"
                install -m 755 "$HOME/.cargo/bin/matugen" "$HOME/.local/bin/matugen"
            }
        fi
        local rc
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [[ -f "$rc" || -w "$HOME" ]]; then
                grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' "$rc" 2>/dev/null || echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc" 2>/dev/null || true
            fi
        done
        if command -v fish >/dev/null 2>&1; then
            fish -c 'fish_add_path ~/.cargo/bin' >/dev/null 2>&1 || true
        fi
        ok "matugen installed successfully via Cargo."
        return 0
    fi

    err "Failed to install matugen via Cargo."
    return 1
}

install_matugen_fedora() {
    info "Installing/updating matugen from COPR (avengemedia/danklinux)..."
    if caelestia_sudo dnf copr enable -y avengemedia/danklinux && (caelestia_sudo dnf install -y matugen || caelestia_sudo dnf upgrade -y matugen); then
        if package_present matugen; then
            cleanup_legacy_cargo_matugen
            ok "matugen is installed via dnf (avengemedia/danklinux)."
            return 0
        fi
    fi

    warn "COPR installation failed; attempting GitHub release fallback for Fedora..."
    if install_matugen_github; then
        return 0
    fi

    warn "GitHub release download failed or unavailable; attempting Cargo fallback for Fedora..."
    install_matugen_cargo
}

install_matugen_debian() {
    if install_matugen_github; then
        return 0
    fi

    warn "GitHub release download failed or unavailable; attempting Cargo fallback for Debian..."
    install_matugen_cargo
}

ensure_matugen() {
    cleanup_legacy_cargo_matugen
    case "${BASE_DISTRO:-unknown}" in
        fedora)
            if package_present matugen && matugen_present; then
                ok "matugen is installed."
                return 0
            fi
            install_matugen_fedora
            ;;
        arch)
            if matugen_present; then
                ok "matugen is installed."
                return 0
            fi
            if command -v yay >/dev/null 2>&1 && yay -S --needed --noconfirm matugen; then
                ok "matugen is installed via yay."
                return 0
            fi
            if caelestia_sudo pacman -S --needed --noconfirm matugen 2>/dev/null; then
                ok "matugen is installed via pacman."
                return 0
            fi
            warn "Arch package managers failed; attempting GitHub release fallback for Arch..."
            if install_matugen_github; then
                return 0
            fi
            warn "GitHub release download failed or unavailable; attempting Cargo fallback for Arch..."
            install_matugen_cargo
            ;;
        debian)
            if matugen_present; then
                ok "matugen is installed."
                return 0
            fi
            install_matugen_debian
            ;;
        *)
            if matugen_present; then
                ok "matugen is installed."
                return 0
            fi
            if install_matugen_github || install_matugen_cargo; then
                return 0
            fi
            warn "matugen is not installed: wallpapers and schemes cannot generate a palette."
            record_failed_package "matugen" 2>/dev/null || true
            return 1
            ;;
    esac
}

fi
