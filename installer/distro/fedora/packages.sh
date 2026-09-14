#!/usr/bin/env bash

set -uo pipefail

# shellcheck source=scripts/lib/toolchain.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/toolchain.sh"


log()  { printf '  [INFO]  %s\n' "$*"; }
err()  { printf '  [ERR]   %s\n' "$*" >&2; }

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

log "Installing Fedora packages..."

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

    kf6-kglobalaccel-devel kf6-kwindowsystem-devel kf6-kguiaddons-devel
    kf6-kcoreaddons-devel kwin-devel kf6-kconfig-devel
    kf6-networkmanager-qt-devel kf6-kpipewire kf6-kpipewire-devel
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
    slurp grim xdg-utils sassc bat ripgrep lazygit xdg-user-dirs
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

log "Installing packages (group: $PACKAGE_GROUP)..."

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

log "Enabling RPM Fusion for H264 hardware codecs..."
sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || true

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "core" ]]; then
    PACKAGES+=(ffmpeg)
fi

log "Installing packages via dnf (batch mode)..."
sudo dnf upgrade -y || true

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

if [[ ${#BATCH_PKGS[@]} -gt 0 ]]; then
    if ! sudo dnf install -y "${BATCH_PKGS[@]}"; then
        log "Batch install had failures. Retrying standard packages individually..."
        for pkg in "${BATCH_PKGS[@]}"; do
            if ! rpm -q "$pkg" >/dev/null 2>&1; then
                sudo dnf install -y "$pkg" || true
            fi
        done
    fi
fi

for pkg in "${COPR_PKGS[@]}"; do
    _needed="no"
    for op in "${PACKAGES[@]}"; do
        if [[ "$op" == "$pkg" ]]; then _needed="yes"; break; fi
    done
    if [[ "$_needed" == "no" ]]; then continue; fi

    if sudo dnf install -y "$pkg" 2>/dev/null; then
        continue
    fi

    log "dnf failed to install $pkg. Attempting copr fallback..."
    COPR_FAILED="yes"
    case "$pkg" in
        quickshell-git|quickshell)
            if sudo dnf copr enable -y errornointernet/quickshell && sudo dnf install -y quickshell-git; then
                COPR_FAILED="no"
            fi
            ;;
        gpu-screen-recorder)
            if sudo dnf copr enable -y brycensranch/gpu-screen-recorder-git && sudo dnf install -y gpu-screen-recorder-ui; then
                COPR_FAILED="no"
            fi
            ;;
        app2unit)
            if sudo dnf copr enable -y celestelove/app2unit && sudo dnf install -y app2unit; then
                COPR_FAILED="no"
            fi
            ;;
        starship)
            if sudo dnf copr enable -y atim/starship && sudo dnf install -y starship; then
                COPR_FAILED="no"
            fi
            ;;
        libcava)
            if install_cava_sdk fedora; then
                log "Installed prebuilt CAVA SDK from release."
                COPR_FAILED="no"
            elif sudo dnf copr enable -y celestelove/libcava && sudo dnf install -y libcava-devel; then
                COPR_FAILED="no"
            fi
            ;;
        wl-clip-persist)
            if sudo dnf copr enable -y leloubil/wl-clip-persist && sudo dnf install -y wl-clip-persist; then
                COPR_FAILED="no"
            fi
            ;;
    esac

    if [ "$COPR_FAILED" = "no" ]; then
        continue
    fi

    log "Copr fallback failed or not defined for $pkg. Attempting manual build..."
    case "$pkg" in
        app2unit)
            tmpdir="$(mktemp -d)"
            sudo dnf install -y make
            if git clone --depth 1 https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    sudo make install
                ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        gpu-screen-recorder)
            tmpdir="$(mktemp -d)"
            sudo dnf install -y meson ninja-build pkgconf libXcomposite-devel libXrandr-devel libXfixes-devel libdrm-devel wayland-devel pipewire-devel libcap-devel ffmpeg-devel
            if git clone --depth 1 https://git.dec05eba.com/gpu-screen-recorder "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    meson setup build && ninja -C build && sudo meson install -C build
                ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        starship)
            if curl -sS https://starship.rs/install.sh | sh -s -- -y; then  # ci:allow-curl-pipe
                log "starship installed successfully."
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

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
    err "The following packages could not be installed:"
    for pkg in "${FAILED_PKGS[@]}"; do
        err "  - $pkg"
        echo "$pkg" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"
    done
fi


if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then

log "Downloading and installing required custom fonts (parallel)..."
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

curl -sL "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" -o "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf" &
_pid_ms=$!

curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip" -o "/tmp/CascadiaCode.zip" &
_pid_cc=$!

curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip" -o "/tmp/JetBrainsMono.zip" &
_pid_jb=$!

wait $_pid_ms $_pid_cc $_pid_jb

unzip -qo "/tmp/CascadiaCode.zip" -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" 2>/dev/null && rm -f "/tmp/CascadiaCode.zip" || { err "Failed to extract CascadiaCode font."; echo "CascadiaCode font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }
unzip -qo "/tmp/JetBrainsMono.zip" -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" 2>/dev/null && rm -f "/tmp/JetBrainsMono.zip" || { err "Failed to extract JetBrains Mono Nerd Font."; echo "JetBrains Mono Nerd Font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }
[[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf" ]] || { err "Failed to download Material Symbols font."; echo "Material Symbols font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }

fc-cache -f

log "Installing Darkly KDE Theme from COPR..."
if [[ "$INSTALL_DARKLY" == "true" ]]; then
    if ! command -v darkly >/dev/null 2>&1 && ! rpm -q darkly >/dev/null 2>&1; then
        if ! sudo dnf install -y darkly 2>/dev/null; then
            log "Enabling Darkly COPR (deltacopy/darkly)..."
            if ! (sudo dnf copr enable -y deltacopy/darkly && sudo dnf install -y darkly); then
                log "COPR install failed; falling back to prebuilt RPM from GitHub releases..."
                _darkly_rpm="$(darkly_rpm_asset_url || true)"
                if [[ -n "$_darkly_rpm" ]]; then
                    sudo dnf install -y "$_darkly_rpm" || err "Failed to install Darkly RPM."
                else
                    err "No prebuilt Darkly RPM found for this Fedora version."
                fi
            fi
        fi
    fi

    log "Installing Darkly GTK theme..."
    sudo dnf install -y sassc || true
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
    log "Skipping Darkly package installation by user choice."
fi

fi  # end of PACKAGE_GROUP themes/all block

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update || true
fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then

log "Installing Caelestia CLI wrapper..."
if ! command -v caelestia >/dev/null 2>&1; then
    sudo dnf install -y python3-pip python3-build python3-installer python3-hatchling python3-hatch-vcs || true
    tmpdir="$(mktemp -d)"
    (
        cd "$tmpdir" || exit 1
        curl -sL "https://github.com/caelestia-dots/cli/releases/download/v1.0.8/caelestia-1.0.8.tar.gz" -o caelestia.tar.gz
        tar -xzf caelestia.tar.gz
        cd caelestia-1.0.8 || exit 1
        python3 -m build --wheel --no-isolation
        if ! sudo pip3 install dist/*.whl --break-system-packages; then
            pip3 install dist/*.whl --user --break-system-packages
            if [[ -f "$HOME/.local/bin/caelestia" ]]; then
                sudo ln -sf "$HOME/.local/bin/caelestia" /usr/local/bin/caelestia || true
            fi
        fi

        mkdir -p ~/.config/fish/completions/
        cp ./completions/caelestia.fish ~/.config/fish/completions/ 2>/dev/null || true
    )
    rm -rf "$tmpdir"
fi

if command -v sassc >/dev/null 2>&1 && ! command -v sass >/dev/null 2>&1; then
    sudo ln -sf /usr/bin/sassc /usr/local/bin/sass || true
fi

fi  # end of PACKAGE_GROUP shell/all block

log "Fedora package installation complete."
