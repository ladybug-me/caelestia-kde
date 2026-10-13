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
    info "Fetching matugen binary from GitHub releases..."
    local arch carch="x86_64"
    arch="$(uname -m 2>/dev/null || echo "x86_64")"
    case "$arch" in
        x86_64)          carch="x86_64" ;;
        aarch64|arm64)   carch="aarch64" ;;
        armv7*|armhf)    carch="armv7" ;;
        *)               carch="x86_64" ;;
    esac

    local release_json="" dl_url="" tmpdir=""
    release_json="$(curl -fsSL "https://api.github.com/repos/InioX/matugen/releases/latest" 2>/dev/null || true)"
    if [[ -n "$release_json" ]]; then
        dl_url="$(printf '%s' "$release_json" | grep -oE "https://[^\"]*${carch}[^\"]*\.tar\.gz" | head -n1)"
    fi

    if [[ -n "$dl_url" ]]; then
        tmpdir="$(mktemp -d)"
        if curl -fsSL "$dl_url" | tar -xz -C "$tmpdir" 2>/dev/null; then
            if [[ -f "$tmpdir/matugen" ]]; then
                if caelestia_sudo install -m 755 "$tmpdir/matugen" /usr/local/bin/matugen 2>/dev/null; then
                    rm -rf "$tmpdir"
                    ok "matugen installed successfully to /usr/local/bin from GitHub release."
                    return 0
                else
                    mkdir -p "$HOME/.local/bin"
                    install -m 755 "$tmpdir/matugen" "$HOME/.local/bin/matugen"
                    rm -rf "$tmpdir"
                    ok "matugen installed successfully to $HOME/.local/bin from GitHub release."
                    return 0
                fi
            fi
        fi
        rm -rf "$tmpdir"
    fi

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
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || true # ci:allow-curl-pipe
            export PATH="$HOME/.cargo/bin:$PATH"
        fi
    fi

    if command -v cargo >/dev/null 2>&1 && cargo install matugen; then
        if [[ -f "$HOME/.cargo/bin/matugen" ]]; then
            caelestia_sudo cp "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen 2>/dev/null || true
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
