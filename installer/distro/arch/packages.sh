#!/usr/bin/env bash
# packages.sh - Arch package installation for Caelestia

set -uo pipefail

# shellcheck source=scripts/lib/toolchain.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/toolchain.sh"


log()  { printf '  [INFO]  %s\n' "$*"; }
err()  { printf '  [ERR]   %s\n' "$*" >&2; }

log "Installing Arch packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"

# Ensure yay
if ! command -v yay >/dev/null 2>&1; then
    log "yay not found - installing..."
    sudo pacman -S --needed --noconfirm base-devel git || true
    tmpdir="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmpdir"
    (
        cd "$tmpdir" || exit 1
        makepkg -si --noconfirm
    )
    rm -rf "$tmpdir"
fi

# Package groups, selected by PACKAGE_GROUP.
PACKAGE_GROUP="${PACKAGE_GROUP:-all}"

CORE_PACKAGES=(
    # Build tools & compilers
    cmake ninja ccache qt6-tools extra-cmake-modules gcc-libs glibc

    # CLI & System utilities
    wl-clipboard cliphist wl-clip-persist inotify-tools app2unit wireplumber trash-cli jq

    # Audio, Sensors & Hardware
    aubio lm_sensors libpipewire pulseaudio-qt libpulse fftw

    # Qt6 Framework & Tools
    qt6-base qt6-declarative qt6-wayland qt6-shadertools

    # KDE 6 Frameworks & KWin
    kglobalaccel kglobalacceld kguiaddons kwindowsystem
    kcoreaddons kconfig networkmanager-qt kpipewire kwin

    # Media, Calculation & Security
    ffmpeg libqalculate libsecret ksshaskpass libx11 vulkan-headers
)

SHELL_PACKAGES=(
    quickshell matugen python
    foot eza fastfetch starship btop bash
)

THEME_PACKAGES=(
    adw-gtk-theme ttf-jetbrains-mono-nerd ttf-material-symbols-variable
    ttf-rubik-vf ttf-cascadia-code-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji
)

UTILITY_PACKAGES=(
    swappy ddcutil networkmanager imagemagick tesseract tesseract-data-eng
    satty spectacle xdg-utils sassc bat ripgrep lazygit xdg-user-dirs
)

PACKAGES=()
case "$PACKAGE_GROUP" in
    core)   PACKAGES=("${CORE_PACKAGES[@]}") ;;
    shell)  PACKAGES=("${SHELL_PACKAGES[@]}") ;;
    themes) PACKAGES=("${THEME_PACKAGES[@]}") ;;
    utils)  PACKAGES=("${UTILITY_PACKAGES[@]}") ;;
    all|*)  PACKAGES=("${CORE_PACKAGES[@]}" "${SHELL_PACKAGES[@]}" "${THEME_PACKAGES[@]}" "${UTILITY_PACKAGES[@]}") ;;
esac

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then
    if [[ "$INSTALL_FISH" == "true" ]]; then
        PACKAGES+=(fish)
    else
        log "Skipping Fish installation by user choice."
    fi
fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then
    if [[ "$INSTALL_PAPIRUS" == "true" ]]; then
        PACKAGES+=(papirus-icon-theme)
    else
        log "Skipping Papirus icon theme installation by user choice."
    fi
fi

# Developer SDK (libcava) extracted from prebuilt release assets.
if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "core" ]]; then
    if install_cava_sdk arch; then
        log "Installed prebuilt CAVA SDK from release."
    else
        PACKAGES+=(libcava)
    fi
fi
if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then
    if [[ "$INSTALL_DARKLY" == "true" ]]; then
        PACKAGES+=(darkly-bin)
    else
        log "Skipping Darkly package installation by user choice."
    fi
fi

# An older install may have registered the caelestia-bin repo, which pointed at a
# now-deleted GitHub release; a stale entry makes `pacman -Sy` fail.
if grep -q '^\[caelestia-bin\]' /etc/pacman.conf 2>/dev/null; then
    log "Removing stale caelestia-bin repo entry from pacman.conf..."
    sudo sed -i '/^\[caelestia-bin\]/,/^$/d' /etc/pacman.conf
fi

log "Installing packages (group: $PACKAGE_GROUP)..."
FAILED_PKGS=()

# Fallbacks for AUR packages with no reliable binary: build from upstream source when
# yay cannot fetch the package or its source. Keyed by AUR name -> repo URL.
SOURCE_BUILD_REPOS=(
    # package            repo
    "ttf-rubik-vf        https://github.com/googlefonts/rubik"
    "app2unit            https://github.com/Vladimir-csp/app2unit"
)

# Resolve a package name to its source repo URL (empty if not a source-build target)
source_repo_for() {
    local name="$1" entry pkg url
    for entry in "${SOURCE_BUILD_REPOS[@]}"; do
        read -r pkg url <<<"$entry"
        if [[ "$pkg" == "$name" ]]; then
            echo "$url"
            return 0
        fi
    done
    echo ""
    return 1
}

# Build with whatever backend the project ships (meson, CMake, autotools, makefile).
build_from_source() {
    local pkg="$1" repo="$2" tmpdir
    tmpdir="$(mktemp -d)"
    if ! git clone --depth 1 "$repo" "$tmpdir"; then
        err "Failed to clone source for $pkg from $repo."
        rm -rf "$tmpdir"
        return 1
    fi
    (
        cd "$tmpdir" || exit 1
        if [ -f "meson.build" ]; then
            meson setup build && meson compile -C build && sudo meson install -C build
        elif [ -f "CMakeLists.txt" ]; then
            cmake -B build && cmake --build build && sudo cmake --install build
        elif [ -x "autogen.sh" ] || [ -f "configure.ac" ] || [ -f "configure" ]; then
            if [ -x "autogen.sh" ]; then ./autogen.sh; fi
            ./configure && make && sudo make install
        elif [ -f "Makefile" ] || [ -f "makefile" ] || [ -f "GNUmakefile" ]; then
            make && sudo make install
        else
            err "No recognized build system for $pkg; skipping source build."
            exit 1
        fi
    ) || {
        err "Manual build for $pkg failed."
        rm -rf "$tmpdir"
        return 1
    }
    rm -rf "$tmpdir"
    return 0
}

# One batch install; failures are retried individually below.
if ! yay -S --needed --noconfirm "${PACKAGES[@]}"; then
    log "Batch install had failures. Retrying individually..."
    for pkg in "${PACKAGES[@]}"; do
        # Skip packages already installed by the batch attempt
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            continue
        fi
        if ! yay -S --needed --noconfirm "$pkg"; then
            log "yay failed to install $pkg. Attempting manual build from AUR..."
            _built=no
            tmpdir="$(mktemp -d)"
            if git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    makepkg -si --noconfirm
                ) && _built=yes || {
                    err "Manual build from AUR for $pkg failed."
                }
            else
                err "Could not fetch AUR repository for $pkg."
            fi
            rm -rf "$tmpdir"

            # Last resort: build from upstream source when the AUR path failed.
            if [[ "$_built" != "yes" ]]; then
                repo="$(source_repo_for "$pkg")"
                if [[ -n "$repo" ]]; then
                    log "Compiling $pkg from source ($repo)..."
                    if build_from_source "$pkg" "$repo"; then
                        log "Built $pkg from source."
                    else
                        FAILED_PKGS+=("$pkg")
                    fi
                else
                    err "No source repository mapping for $pkg."
                    FAILED_PKGS+=("$pkg")
                fi
            fi
        fi
    done
fi

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
    err "The following packages could not be installed:"
    for pkg in "${FAILED_PKGS[@]}"; do
        err "  - $pkg"
        echo "$pkg" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"
    done
fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then
    if [[ "$INSTALL_DARKLY" == "true" ]]; then
        log "Installing Darkly GTK theme..."
        yay -S --needed --noconfirm sassc >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm sassc >/dev/null 2>&1 || true
        tmpdir="$(mktemp -d)"
        if git clone --depth 1 https://github.com/wrymt/darkly-gtk "$tmpdir"; then
            (
                cd "$tmpdir" || exit 1
                ./install.sh -l || err "Failed to install Darkly GTK theme."
            )
        else
            err "Failed to clone Darkly GTK theme."
        fi
        rm -rf "$tmpdir"
    else
        log "Skipping Darkly GTK theme by user choice."
    fi
fi

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update || true
fi

if command -v sassc >/dev/null 2>&1 && ! command -v sass >/dev/null 2>&1; then
    sudo ln -sf /usr/bin/sassc /usr/local/bin/sass || true
fi

log "Arch package installation complete."
