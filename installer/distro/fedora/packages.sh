#!/usr/bin/env bash

set -uo pipefail

# shellcheck source=scripts/lib/log.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/log.sh"
# shellcheck source=scripts/lib/toolchain.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/toolchain.sh"
# shellcheck source=scripts/lib/privileges.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/packages.sh"
# shellcheck source=scripts/lib/darkly.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/darkly.sh"

darkly_rpm_asset_url() {
    local release_json ver url
    release_json="$(curl -fsSL "https://api.github.com/repos/Bali10050/Darkly/releases/latest" 2>/dev/null || true)"
    [[ -n "$release_json" ]] || return 1
    ver="$(rpm -E %fedora 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$ver" ]]; then
        url="$(printf '%s' "$release_json" | grep -oE "https://[^\"]*\.fc${ver}\.x86_64\.rpm" | head -n1)"
        [[ -n "$url" ]] && { echo "$url"; return 0; }
    fi
    url="$(printf '%s' "$release_json" | grep -oE 'https://[^"]*\.fc[0-9]+\.x86_64\.rpm' | head -n1)"
    [[ -n "$url" ]] && { echo "$url"; return 0; }
    return 1
}

info "Installing Fedora packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"

PACKAGE_GROUP="${PACKAGE_GROUP:-all}"

CORE_PACKAGES=(
    cmake ninja-build ccache qt6-qttools-devel extra-cmake-modules libgcc glibc

    wl-clipboard cliphist wl-clip-persist inotify-tools wireplumber trash-cli jq

    aubio aubio-devel lm_sensors lm_sensors-devel pipewire-devel
    pulseaudio-qt-qt6-devel pulseaudio-libs-devel fftw-devel

    qt6-qtbase qt6-qtbase-private-devel qt6-qtdeclarative qt6-qtdeclarative-devel
    qt6-qtwayland qt6-qtwayland-devel qt6-qtsvg qt6-qtsvg-devel qt6-qtshadertools-devel
    qt6-qtmultimedia-devel qt6-qt5compat-devel qt6-qtimageformats

    kf6-kglobalaccel-devel kf6-kwindowsystem-devel kf6-kguiaddons-devel
    kf6-kcoreaddons-devel kwin-devel kf6-kconfig-devel
    kf6-networkmanager-qt-devel kpipewire kpipewire-devel
    libepoxy-devel libdrm-devel

    libqalculate libqalculate-devel libsecret vulkan-headers ksshaskpass libX11-devel
)

SHELL_PACKAGES=(
    foot eza fastfetch starship btop bash
)

THEME_PACKAGES=(
    adw-gtk3-theme google-rubik-fonts google-noto-sans-fonts
    google-noto-sans-cjk-fonts google-noto-emoji-fonts
)

UTILITY_PACKAGES=(
    fuzzel swappy ddcutil NetworkManager ImageMagick
    tesseract tesseract-langpack-eng spectacle gpu-screen-recorder
    slurp grim brightnessctl power-profiles-daemon
    xdg-utils sassc bat ripgrep xdg-user-dirs
)

COPR_CORE=(app2unit libcava)
COPR_SHELL=(quickshell-git)
COPR_UTILS=()

PACKAGES=()
COPR_PKGS=()
case "$PACKAGE_GROUP" in
    core)   PACKAGES=("${CORE_PACKAGES[@]}");   COPR_PKGS=("${COPR_CORE[@]}") ;;
    shell)  PACKAGES=("${SHELL_PACKAGES[@]}");  COPR_PKGS=("${COPR_SHELL[@]}") ;;
    themes) PACKAGES=("${THEME_PACKAGES[@]}");  COPR_PKGS=() ;;
    utils)  PACKAGES=("${UTILITY_PACKAGES[@]}"); COPR_PKGS=("${COPR_UTILS[@]}") ;;
    all|*)  PACKAGES=("${CORE_PACKAGES[@]}" "${SHELL_PACKAGES[@]}" "${THEME_PACKAGES[@]}" "${UTILITY_PACKAGES[@]}")
            COPR_PKGS=("quickshell-git" "gpu-screen-recorder" "app2unit" "starship" "libcava" "wl-clip-persist") ;;
esac

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "core" ]]; then
    PACKAGES+=("${COPR_CORE[@]}")
fi
if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then
    PACKAGES+=("${COPR_SHELL[@]}")
fi

info "Installing packages (group: $PACKAGE_GROUP)..."

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then
    if [[ "$INSTALL_FISH" == "true" ]]; then
        PACKAGES+=(fish)
    else
        info "Skipping Fish installation by user choice."
    fi
fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then
    if [[ "$INSTALL_PAPIRUS" == "true" ]]; then
        PACKAGES+=(papirus-icon-theme)
    else
        info "Skipping Papirus icon theme installation by user choice."
    fi
fi

if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    info "Enabling RPM Fusion for H264 hardware codecs..."
    caelestia_sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true
    caelestia_sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || true
fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "core" ]]; then
    PACKAGES+=(ffmpeg)
fi

BATCH_PKGS=()
for pkg in "${PACKAGES[@]}"; do
    _is_copr="no"
    for cp in "${COPR_PKGS[@]}"; do
        if [[ "$pkg" == "$cp" ]]; then _is_copr="yes"; break; fi
    done
    if [[ "$_is_copr" == "no" ]]; then
        BATCH_PKGS+=("$pkg")
    fi
done

FAILED_PKGS=()

mapfile -t MISSING_PKGS < <(filter_missing "${BATCH_PKGS[@]}")

if (( ${#MISSING_PKGS[@]} > 0 )); then
    info "Installing packages via dnf (batch mode)..."
    if ! caelestia_sudo dnf install -y "${MISSING_PKGS[@]}"; then
        info "Batch install had failures. Retrying standard packages individually..."
        for pkg in "${MISSING_PKGS[@]}"; do
            if ! package_present "$pkg"; then
                if ! caelestia_sudo dnf install -y "$pkg"; then
                    err "dnf failed to install $pkg."
                    FAILED_PKGS+=("$pkg")
                fi
            fi
        done
    fi
else
    info "All standard packages for group $PACKAGE_GROUP are already installed."
fi

for pkg in "${COPR_PKGS[@]}"; do
    _needed="no"
    for op in "${PACKAGES[@]}"; do
        if [[ "$op" == "$pkg" ]]; then _needed="yes"; break; fi
    done
    if [[ "$_needed" == "no" ]]; then continue; fi

    if package_present "$pkg" || command -v "$pkg" >/dev/null 2>&1; then
        continue
    fi

    # libcava is the one target the package manager cannot report: the prebuilt SDK
    # provides it without being a package, and asking dnf for it just fails.
    if [[ "$pkg" == "libcava" ]] && cava_sdk_installed; then
        continue
    fi

    if caelestia_sudo dnf install -y "$pkg" 2>/dev/null; then
        continue
    fi

    info "dnf failed to install $pkg. Attempting copr fallback..."
    COPR_FAILED="yes"
    case "$pkg" in
        quickshell-git|quickshell)
            if caelestia_sudo dnf copr enable -y errornointernet/quickshell && caelestia_sudo dnf install -y quickshell-git; then
                COPR_FAILED="no"
            fi
            ;;
        gpu-screen-recorder)
            if caelestia_sudo dnf copr enable -y brycensranch/gpu-screen-recorder-git && caelestia_sudo dnf install -y gpu-screen-recorder-ui; then
                COPR_FAILED="no"
            fi
            ;;
        app2unit)
            if caelestia_sudo dnf copr enable -y celestelove/app2unit && caelestia_sudo dnf install -y app2unit; then
                COPR_FAILED="no"
            fi
            ;;
        starship)
            if caelestia_sudo dnf copr enable -y atim/starship && caelestia_sudo dnf install -y starship; then
                COPR_FAILED="no"
            fi
            ;;
        libcava)
            if cava_sdk_installed || install_cava_sdk fedora; then
                info "CAVA SDK ready."
                COPR_FAILED="no"
            elif caelestia_sudo dnf copr enable -y celestelove/libcava && caelestia_sudo dnf install -y libcava-devel; then
                COPR_FAILED="no"
            fi
            ;;
        wl-clip-persist)
            if caelestia_sudo dnf copr enable -y leloubil/wl-clip-persist && caelestia_sudo dnf install -y wl-clip-persist; then
                COPR_FAILED="no"
            fi
            ;;
    esac

    if [ "$COPR_FAILED" = "no" ]; then
        continue
    fi

    info "Copr fallback failed or not defined for $pkg. Attempting manual build..."
    case "$pkg" in
        app2unit)
            tmpdir="$(mktemp -d)"
            caelestia_sudo dnf install -y make
            if git clone --depth 1 https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    caelestia_sudo make install
                ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        gpu-screen-recorder)
            tmpdir="$(mktemp -d)"
            caelestia_sudo dnf install -y meson ninja-build pkgconf libXcomposite-devel libXrandr-devel libXfixes-devel libdrm-devel wayland-devel pipewire-devel libcap-devel ffmpeg-devel
            if git clone --depth 1 https://git.dec05eba.com/gpu-screen-recorder "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    meson setup build && ninja -C build && caelestia_sudo meson install -C build
                ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        starship)
            if curl -sS https://starship.rs/install.sh | sh -s -- -y; then  # ci:allow-curl-pipe
                info "starship installed successfully."
            else
                err "Manual build for $pkg failed."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        *)
            err "No manual fallback defined for $pkg."
            FAILED_PKGS+=("$pkg")
            ;;
    esac
done

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then

info "Downloading and installing required custom fonts (parallel)..."
FONTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
mkdir -p "$FONTS_DIR"

# mktemp, not a fixed /tmp name: a predictable path in a world-writable
# directory is a symlink-clobber target. curl -f fails on HTTP errors, so a
# 404 page can never be saved as a font.
_cascadia_zip="$(mktemp "${TMPDIR:-/tmp}/caelestia-cascadia.XXXXXX")"
_jetbrains_zip="$(mktemp "${TMPDIR:-/tmp}/caelestia-jetbrains.XXXXXX")"

curl -fsL "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" -o "$FONTS_DIR/MaterialSymbolsRounded.ttf" &
_pid_ms=$!

curl -fsL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip" -o "$_cascadia_zip" &
_pid_cc=$!

curl -fsL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip" -o "$_jetbrains_zip" &
_pid_jb=$!

wait $_pid_ms $_pid_cc $_pid_jb

unzip -qo "$_cascadia_zip" -d "$FONTS_DIR" 2>/dev/null && rm -f "$_cascadia_zip" || { rm -f "$_cascadia_zip"; err "Failed to extract CascadiaCode font."; FAILED_PKGS+=("CascadiaCode font"); }
unzip -qo "$_jetbrains_zip" -d "$FONTS_DIR" 2>/dev/null && rm -f "$_jetbrains_zip" || { rm -f "$_jetbrains_zip"; err "Failed to extract JetBrains Mono Nerd Font."; FAILED_PKGS+=("JetBrains Mono Nerd Font"); }
[[ -s "$FONTS_DIR/MaterialSymbolsRounded.ttf" ]] || { err "Failed to download Material Symbols font."; FAILED_PKGS+=("Material Symbols font"); }

fc-cache -f

info "Installing Darkly KDE Theme from COPR..."
if [[ "$INSTALL_DARKLY" == "true" ]]; then
    if ! command -v darkly >/dev/null 2>&1 && ! package_present darkly; then
        if ! caelestia_sudo dnf install -y darkly 2>/dev/null; then
            info "Enabling Darkly COPR (deltacopy/darkly)..."
            if ! (caelestia_sudo dnf copr enable -y deltacopy/darkly && caelestia_sudo dnf install -y darkly); then
                info "COPR install failed; falling back to prebuilt RPM from GitHub releases..."
                _darkly_rpm="$(darkly_rpm_asset_url || true)"
                if [[ -n "$_darkly_rpm" ]]; then
                    if ! caelestia_sudo dnf install -y "$_darkly_rpm"; then
                        err "Failed to install Darkly RPM."
                        FAILED_PKGS+=("darkly")
                    fi
                else
                    err "No prebuilt Darkly RPM found for this Fedora version."
                    FAILED_PKGS+=("darkly")
                fi
            fi
        fi
    fi

    if ! darkly_gtk_installed; then
        info "Installing Darkly GTK theme..."
        caelestia_sudo dnf install -y sassc || true
        install_darkly_gtk_theme || FAILED_PKGS+=("darkly-gtk")
    fi
else
    info "Skipping Darkly package installation by user choice."
fi

fi  # end of PACKAGE_GROUP themes/all block

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update || true
fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then

# matugen generates the color palette but Fedora has no package for it. The crates.io
# release cargo builds by default predates --source-color-index, which the color
# pipeline needs, so the fallback builds it from the repository (issue #814).
matugen_usable() {
    command -v matugen >/dev/null 2>&1 || return 1
    matugen image --help 2>&1 | grep -q -- '--source-color-index'
}

if ! matugen_usable; then
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    if ! command -v cargo >/dev/null 2>&1; then
        info "Installing a Rust toolchain to build matugen..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || true # ci:allow-curl-pipe
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    if command -v cargo >/dev/null 2>&1; then
        cargo install --git https://github.com/InioX/matugen || { err "cargo install matugen failed."; FAILED_PKGS+=("matugen"); }
    else
        err "matugen generates the color palette but has no Fedora package; install a Rust toolchain and run 'cargo install --git https://github.com/InioX/matugen'."
        FAILED_PKGS+=("matugen")
    fi
fi

info "Installing Caelestia CLI wrapper..."
if ! command -v caelestia >/dev/null 2>&1; then
    caelestia_sudo dnf install -y python3-pip python3-build python3-installer python3-hatchling python3-hatch-vcs || true
    tmpdir="$(mktemp -d)"
    (
        cd "$tmpdir" || exit 1
        curl -fsL "https://github.com/caelestia-dots/cli/releases/download/v1.0.8/caelestia-1.0.8.tar.gz" -o caelestia.tar.gz
        tar -xzf caelestia.tar.gz
        cd caelestia-1.0.8 || exit 1
        python3 -m build --wheel --no-isolation
        if ! caelestia_sudo pip3 install dist/*.whl --break-system-packages; then
            pip3 install dist/*.whl --user --break-system-packages
            if [[ -f "$HOME/.local/bin/caelestia" ]]; then
                caelestia_sudo ln -sf "$HOME/.local/bin/caelestia" /usr/local/bin/caelestia || true
            fi
        fi

        mkdir -p ~/.config/fish/completions/
        cp ./completions/caelestia.fish ~/.config/fish/completions/ 2>/dev/null || true
    )
    rm -rf "$tmpdir"
fi

if ! command -v caelestia >/dev/null 2>&1 && [[ ! -f "$HOME/.local/bin/caelestia" ]]; then
    err "Failed to install Caelestia CLI wrapper."
    FAILED_PKGS+=("caelestia")
fi

if command -v sassc >/dev/null 2>&1 && ! command -v sass >/dev/null 2>&1; then
    caelestia_sudo ln -sf /usr/bin/sassc /usr/local/bin/sass || true
fi

if ! command -v qdbus6 >/dev/null 2>&1; then
    if command -v qdbus-qt6 >/dev/null 2>&1; then
        caelestia_sudo ln -sf "$(command -v qdbus-qt6)" /usr/local/bin/qdbus6 || true
    elif [[ -x "/usr/lib64/qt6/bin/qdbus" ]]; then
        caelestia_sudo ln -sf /usr/lib64/qt6/bin/qdbus /usr/local/bin/qdbus6 || true
    elif [[ -x "/usr/lib/qt6/bin/qdbus" ]]; then
        caelestia_sudo ln -sf /usr/lib/qt6/bin/qdbus /usr/local/bin/qdbus6 || true
    fi
fi

fi  # end of PACKAGE_GROUP shell/all block

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
    err "The following packages could not be installed:"
    for pkg in "${FAILED_PKGS[@]}"; do
        err "  - $pkg"
        echo "$pkg" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"
    done
fi

info "Fedora package installation complete."
