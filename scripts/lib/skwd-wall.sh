#!/usr/bin/env bash
# Helper for ensuring skwd-wall (wallpaper selector + Plasma integration + daemon)
# is installed across different distributions and its user service is enabled.
if [[ -z "${CAELESTIA_SKWD_WALL_SOURCED:-}" ]]; then
CAELESTIA_SKWD_WALL_SOURCED=1

# shellcheck source=scripts/lib/log.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/log.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/privileges.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/privileges.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/packages.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/packages.sh" 2>/dev/null || true

skwd_wall_binary_present() {
    command -v skwd-wall-v2 >/dev/null 2>&1 || \
    command -v skwd-wall >/dev/null 2>&1 || \
    package_present "skwd-wall-v2" 2>/dev/null || \
    package_present "skwd-wall-v2-bin" 2>/dev/null
}

skwd_paper_plasma_present() {
    package_present "skwd-paper-plasma" 2>/dev/null || \
    [[ -d "${SKWD_PLASMA_DIR:-/usr/share}/plasma/wallpapers/org.skwd.wall.plasma" ]] || \
    [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/org.skwd.wall.plasma" ]] || \
    [[ -f "${SKWD_QML_DIR:-/usr/lib/qt6/qml}/org/skwd/wallpaper/libskwdwallpaperplugin.so" ]] || \
    [[ -f "$HOME/.local/lib/qml/org/skwd/wallpaper/libskwdwallpaperplugin.so" ]]
}

skwd_wall_present() {
    skwd_wall_binary_present && skwd_paper_plasma_present
}

enable_skwd_walld_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable --now skwd-walld.service 2>/dev/null || true
    fi
}

install_skwd_paper_plasma_source() {
    if skwd_paper_plasma_present; then
        return 0
    fi
    info "Installing skwd-paper-plasma plugin from source..."
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    if git clone --depth 1 "https://github.com/liixini/skwd-paper-plasma.git" "$tmp_dir" 2>/dev/null; then
        if cmake -B "$tmp_dir/build" -S "$tmp_dir" -DCMAKE_INSTALL_PREFIX="${XDG_DATA_HOME:-$HOME/.local}" >/dev/null 2>&1 && \
           cmake --build "$tmp_dir/build" >/dev/null 2>&1 && \
           cmake --install "$tmp_dir/build" >/dev/null 2>&1; then
            rm -rf "$tmp_dir"
            return 0
        fi
        if cmake -B "$tmp_dir/build-sys" -S "$tmp_dir" -DCMAKE_INSTALL_PREFIX=/usr >/dev/null 2>&1 && \
           cmake --build "$tmp_dir/build-sys" >/dev/null 2>&1 && \
           caelestia_sudo cmake --install "$tmp_dir/build-sys" >/dev/null 2>&1; then
            rm -rf "$tmp_dir"
            return 0
        fi
    fi
    rm -rf "$tmp_dir"
    return 1
}

install_skwd_wall_source() {
    info "Attempting to build skwd-wall from source..."
    local src_dir="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/wallpaper-selector"
    local built=false

    if [[ -d "$src_dir" ]] && command -v cargo >/dev/null 2>&1; then
        if cargo install --path "$src_dir" --bin skwd-wall 2>/dev/null || \
           cargo build --release --manifest-path "$src_dir/Cargo.toml" 2>/dev/null; then
            if [[ -f "$src_dir/target/release/skwd-wall" ]]; then
                caelestia_sudo install -m 755 "$src_dir/target/release/skwd-wall" /usr/local/bin/skwd-wall-v2 2>/dev/null || {
                    mkdir -p "$HOME/.local/bin"
                    install -m 755 "$src_dir/target/release/skwd-wall" "$HOME/.local/bin/skwd-wall-v2"
                }
            fi
            built=true
        fi
    fi

    # Also build the required KDE Plasma integration plugin if needed
    install_skwd_paper_plasma_source || true

    if [[ "$built" == "true" ]] || skwd_wall_binary_present; then
        enable_skwd_walld_service
        apply_skwd_wall_config
        ok "skwd-wall built and installed successfully from source."
        return 0
    fi

    return 1
}

install_skwd_wall_arch() {
    # Priority 1: Prebuilt AUR packages (-bin) as recommended in README to avoid heavy Rust compilation
    info "Installing skwd-wall on Arch (Priority 1: Prebuilt AUR packages)..."
    local aur_helper=""
    if command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    elif command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    fi

    if [[ -n "$aur_helper" ]]; then
        if "$aur_helper" -S --needed --noconfirm skwd-wall-v2-bin skwd-lens-bin skwd-paper-plasma 2>/dev/null || \
           "$aur_helper" -S --needed --noconfirm skwd-wall-v2-bin skwd-paper-plasma 2>/dev/null; then
            enable_skwd_walld_service
            if skwd_wall_present; then
                apply_skwd_wall_config
                ok "skwd-wall installed successfully via AUR (prebuilt)."
                return 0
            fi
        fi

        # Priority 2: Source AUR packages (compile Rust via AUR helper)
        warn "Prebuilt AUR install failed; attempting source AUR packages (Priority 2)..."
        if "$aur_helper" -S --needed --noconfirm skwd-wall-v2 skwd-lens skwd-paper-plasma 2>/dev/null || \
           "$aur_helper" -S --needed --noconfirm skwd-wall-v2 skwd-paper-plasma 2>/dev/null; then
            enable_skwd_walld_service
            if skwd_wall_present; then
                apply_skwd_wall_config
                ok "skwd-wall installed successfully via AUR (source build)."
                return 0
            fi
        fi
    fi

    if caelestia_sudo pacman -S --needed --noconfirm skwd-wall-v2 2>/dev/null; then
        enable_skwd_walld_service
        install_skwd_paper_plasma_source || true
        if skwd_wall_present; then
            apply_skwd_wall_config
            ok "skwd-wall installed successfully via pacman."
            return 0
        fi
    fi

    # Priority 3: Local source compilation fallback
    warn "AUR installation failed or helper unavailable; falling back to source build for Arch (Priority 3)..."
    caelestia_sudo pacman -S --needed --noconfirm rust cargo cmake extra-cmake-modules libplasma 2>/dev/null || true
    install_skwd_wall_source
}

install_skwd_wall_fedora() {
    # Priority 1: COPR packages (piixini/skwd-wall-v2) as documented in README
    info "Installing skwd-wall on Fedora (Priority 1: COPR piixini/skwd-wall-v2)..."

    # Support immutable / ostree systems (Bazzite, Silverblue) if rpm-ostree is present
    if command -v rpm-ostree >/dev/null 2>&1; then
        if caelestia_sudo dnf5 copr enable -y piixini/skwd-wall-v2 2>/dev/null || \
           caelestia_sudo dnf copr enable -y piixini/skwd-wall-v2 2>/dev/null; then
            if caelestia_sudo rpm-ostree install --apply-live -y skwd-wall-v2 skwd-deck skwd-paper skwd-lens skwd-lens-model skwd-paper-plasma 2>/dev/null || \
               caelestia_sudo rpm-ostree install -y skwd-wall-v2 skwd-paper-plasma 2>/dev/null; then
                enable_skwd_walld_service
                apply_skwd_wall_config
                ok "skwd-wall installed successfully via rpm-ostree."
                return 0
            fi
        fi
    fi

    if caelestia_sudo dnf copr enable -y piixini/skwd-wall-v2 2>/dev/null; then
        if caelestia_sudo dnf install -y skwd-wall-v2 skwd-lens skwd-paper-plasma 2>/dev/null || \
           (caelestia_sudo dnf install -y skwd-wall-v2 2>/dev/null && caelestia_sudo dnf install -y skwd-paper-plasma 2>/dev/null); then
            enable_skwd_walld_service
            if skwd_wall_present; then
                apply_skwd_wall_config
                ok "skwd-wall is installed via dnf (piixini/skwd-wall-v2)."
                return 0
            fi
        fi
    fi

    # Priority 2: Local source compilation fallback
    warn "COPR installation failed; falling back to source build for Fedora (Priority 2)..."
    caelestia_sudo dnf install -y cargo rust cmake extra-cmake-modules libplasma-devel 2>/dev/null || true
    install_skwd_wall_source
}

install_skwd_wall_debian() {
    # Priority 1: Source compilation (Debian packaging is WIP upstream)
    info "Installing skwd-wall on Debian (Priority 1: Source build)..."
    caelestia_sudo apt-get update 2>/dev/null || true
    caelestia_sudo apt-get install -y cargo rustc cmake extra-cmake-modules libplasma-dev build-essential 2>/dev/null || true
    if install_skwd_wall_source; then
        return 0
    fi

    warn "skwd-wall Debian packaging is WIP upstream and local build did not complete."
    return 1
}

apply_skwd_wall_config() {
    local repo_root="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    local export_script="$repo_root/shell/scripts/export-plasma-config.sh"
    if [[ -x "$export_script" ]]; then
        info "Applying skwd-wall configuration..."
        "$export_script" skwd 2>/dev/null || true
    fi
}

ensure_skwd_wall() {
    if skwd_wall_present; then
        enable_skwd_walld_service
        apply_skwd_wall_config
        ok "skwd-wall (picker + Plasma integration + daemon) is installed."
        return 0
    fi

    local status=1
    case "${BASE_DISTRO:-unknown}" in
        fedora)
            install_skwd_wall_fedora && status=0
            ;;
        arch)
            install_skwd_wall_arch && status=0
            ;;
        debian)
            install_skwd_wall_debian && status=0
            ;;
        *)
            if install_skwd_wall_arch || install_skwd_wall_fedora || install_skwd_wall_debian; then
                status=0
            fi
            ;;
    esac

    if [[ "$status" -eq 0 ]] && skwd_wall_present; then
        enable_skwd_walld_service
        apply_skwd_wall_config
        return 0
    fi

    warn "skwd-wall is not installed."
    record_failed_package "skwd-wall" 2>/dev/null || true
    return 1
}

fi
