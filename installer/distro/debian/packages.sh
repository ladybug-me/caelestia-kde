#!/usr/bin/env bash
# packages.sh - Debian/Ubuntu package installation for Caelestia

set -uo pipefail

# shellcheck source=scripts/lib/toolchain.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/toolchain.sh"


log()  { printf '  [INFO]  %s\n' "$*"; }
err()  { printf '  [ERR]   %s\n' "$*" >&2; }

# Return the download URL of the Darkly prebuilt .deb that matches this distro
# from the latest GitHub release (https://github.com/Bali10050/Darkly/releases).
darkly_deb_asset_url() {
    local release_json id ver needle url
    release_json="$(curl -fsSL "https://api.github.com/repos/Bali10050/Darkly/releases/latest" 2>/dev/null || true)"
    [[ -n "$release_json" ]] || return 1
    id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
    ver="$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"

    local needles=()
    case "$id" in
        neon|kdeneon) needles=("kdeneon") ;;
        ubuntu|kubuntu|linuxmint|pop) needles=("kubuntu-${ver}" "kubuntu") ;;
        debian)
            case "$ver" in
                14*|15*) needles=("debian14" "debian13" "debian") ;;
                *)        needles=("debian13" "debian14" "debian") ;;
            esac
            ;;
        *) needles=("debian13" "debian14" "kubuntu" "kdeneon" "debian") ;;
    esac

    for needle in "${needles[@]}"; do
        url="$(printf '%s' "$release_json" | grep -oE 'https://[^"]*_amd64\.deb' | grep -F "$needle" | head -n1)"
        if [[ -n "$url" ]]; then
            echo "$url"
            return 0
        fi
    done
    return 1
}

log "Installing Debian packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"

# Package groups, selected by PACKAGE_GROUP.
PACKAGE_GROUP="${PACKAGE_GROUP:-all}"

CORE_PACKAGES=(
    # Build tools & compilers
    cmake ninja-build ccache g++ build-essential qt6-l10n-tools qt6-tools-dev extra-cmake-modules

    # CLI & System utilities
    wl-clipboard cliphist inotify-tools wireplumber trash-cli jq yq libc6

    # Audio, Sensors & Hardware
    libaubio-dev aubio-tools lm-sensors libsensors-dev libpipewire-0.3-dev pipewire libfftw3-dev

    # Qt6 Framework & Tools
    qt6-base-dev qt6-base-private-dev qt6-declarative-dev qml6-module-qtquick qt6-wayland qt6-wayland-dev
    qt6-svg-dev qt6-shadertools-dev

    # KDE 6 Frameworks & KWin
    libkf6globalaccel-dev libkf6windowsystem-dev libkf6guiaddons-dev
    libkf6coreaddons-dev kwin-dev libkf6pulseaudioqt-dev libpulse-dev
    libkf6config-dev libkf6networkmanagerqt-dev libkpipewire-dev
    libepoxy-dev libdrm-dev

    # Media, Calculation & Security
    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
    libqalculate-dev qalc libvulkan-dev libsecret-1-dev ksshaskpass libx11-dev
    # secret-tool is in libsecret-tools here, not in the -dev package; the AI API key
    # fields shell out to it at runtime.
    libsecret-tools
)

SHELL_PACKAGES=(
    foot eza fastfetch btop bash
)

THEME_PACKAGES=(
    adw-gtk3
)

UTILITY_PACKAGES=(
    fuzzel swappy ddcutil network-manager imagemagick
    tesseract-ocr tesseract-ocr-eng kde-spectacle slurp grim
    xdg-utils sassc python3-venv uv konsave
)

# Targets with no apt package, built or fetched by the fallback below.
FALLBACK_PKGS=(
    quickshell starship libcava app2unit gpu-screen-recorder cliphist wl-clip-persist satty adw-gtk3 uv konsave matugen
)

# Build final package list based on selected group
PACKAGES=()
FALLBACK_TARGETS=()
case "$PACKAGE_GROUP" in
    core)   PACKAGES=("${CORE_PACKAGES[@]}");   FALLBACK_TARGETS=("libcava" "app2unit" "cliphist" "matugen") ;;
    shell)  PACKAGES=("${SHELL_PACKAGES[@]}");  FALLBACK_TARGETS=("quickshell" "starship") ;;
    themes) PACKAGES=("${THEME_PACKAGES[@]}");  FALLBACK_TARGETS=("adw-gtk3") ;;
    utils)  PACKAGES=("${UTILITY_PACKAGES[@]}"); FALLBACK_TARGETS=("gpu-screen-recorder" "cliphist" "wl-clip-persist" "satty" "uv" "konsave") ;;
    all|*)  PACKAGES=("${CORE_PACKAGES[@]}" "${SHELL_PACKAGES[@]}" "${THEME_PACKAGES[@]}" "${UTILITY_PACKAGES[@]}")
            FALLBACK_TARGETS=("quickshell" "starship" "libcava" "app2unit" "gpu-screen-recorder" "cliphist" "wl-clip-persist" "satty" "adw-gtk3" "uv" "konsave" "matugen") ;;
esac

log "Installing packages (group: $PACKAGE_GROUP)..."

# Optional, and only for the groups that want them.
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

log "Updating apt package index..."
sudo apt-get update || true

FAILED_PKGS=()

# Everything apt can provide, in one call; the fallback targets are handled after.
BATCH_PKGS=()
for pkg in "${PACKAGES[@]}"; do
    _is_fallback="no"
    for fb in "${FALLBACK_TARGETS[@]}"; do
        if [[ "$pkg" == "$fb" ]]; then _is_fallback="yes"; break; fi
    done
    if [[ "$_is_fallback" == "no" ]]; then
        BATCH_PKGS+=("$pkg")
    fi
done

if [[ ${#BATCH_PKGS[@]} -gt 0 ]]; then
    log "Batch installing standard Debian packages..."
    if ! sudo apt-get install -y --no-install-recommends "${BATCH_PKGS[@]}"; then
        log "Batch install had failures. Retrying standard packages individually..."
        for pkg in "${BATCH_PKGS[@]}"; do
            if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                sudo apt-get install -y --no-install-recommends "$pkg" || {
                    err "apt failed to install $pkg"
                    FAILED_PKGS+=("$pkg")
                }
            fi
        done
    fi
fi

for pkg in "${FALLBACK_TARGETS[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1 || command -v "$pkg" >/dev/null 2>&1; then
        continue
    fi

    if sudo apt-get install -y "$pkg" 2>/dev/null; then
        continue
    fi

    log "apt failed or package missing for $pkg. Attempting manual fallback..."
    case "$pkg" in
        quickshell)
            log "Attempting to install quickshell from PPA..."
            sudo apt-get install -y software-properties-common || true
            sudo add-apt-repository -y ppa:avengemedia/danklinux || true
            sudo apt-get update || true
            sudo apt-get install -y quickshell || { err "Failed to install quickshell from PPA."; FAILED_PKGS+=("$pkg"); }
            ;;
        libcava)
            if install_cava_sdk debian; then
                log "Installed prebuilt CAVA SDK from release."
            else
                log "Attempting to install cava from PPA..."
                sudo apt-get install -y software-properties-common || true
                sudo add-apt-repository -y ppa:hsheth2/ppa || true
                sudo apt-get update || true
                if sudo apt-get install -y cava; then
                    log "cava installed via PPA."
                else
                    err "Failed to install libcava SDK / cava."
                    FAILED_PKGS+=("$pkg")
                fi
            fi
            ;;
        app2unit)
            tmpdir="$(mktemp -d)"
            sudo apt-get install -y make scdoc || true
            if git clone --depth 1 https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    sudo make install 2>/dev/null || sudo make install-bin
                ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        gpu-screen-recorder)
            tmpdir="$(mktemp -d)"
            sudo apt-get install -y build-essential git ffmpeg meson libxi-dev libdrm-dev libavcodec-dev libavformat-dev libx11-dev libxcomposite-dev libxdamage-dev libxrender-dev libxrandr-dev libpulse-dev libva-dev libcap-dev libdbus-1-dev libpipewire-0.3-dev libavfilter-dev libvulkan-dev || true
            if git clone --depth 1 https://repo.dec05eba.com/gpu-screen-recorder "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    sudo ./install.sh
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
        cliphist)
            log "Downloading cliphist binary from GitHub releases..."
            ARCH="$(uname -m)"
            case "$ARCH" in
                x86_64)    CARCH="linux-amd64" ;;
                aarch64)   CARCH="linux-arm64" ;;
                armv7l)    CARCH="linux-arm" ;;
                i386|i686) CARCH="linux-386" ;;
                *)         CARCH="linux-amd64" ;;
            esac
            LATEST_URL="$(curl -fsSL https://api.github.com/repos/sentriz/cliphist/releases/latest | grep -o "\"https://[^\"]*${CARCH}\"" | tr -d "\"" | head -n1)"
            if [ -n "$LATEST_URL" ]; then
                tmpbin="$(mktemp)"
                if curl -fsSL "$LATEST_URL" -o "$tmpbin"; then
                    sudo install -m 755 "$tmpbin" /usr/local/bin/cliphist
                    log "cliphist installed successfully to /usr/local/bin."
                else
                    err "Failed to download cliphist."
                    FAILED_PKGS+=("$pkg")
                fi
                rm -f "$tmpbin"
            else
                err "Could not resolve cliphist release URL."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        wl-clip-persist)
            sudo apt-get install -y build-essential curl git libwayland-dev || true
            # Rust >= 1.85 for edition 2024.
            if ! command -v cargo >/dev/null 2>&1 || [ "$(rustc --version 2>/dev/null | awk '{print $2}' | cut -d. -f2 || echo 0)" -lt 85 ]; then
                log "Modern Rust toolchain (>= 1.85) required. Installing via rustup..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || true # ci:allow-curl-pipe
                export PATH="$HOME/.cargo/bin:$PATH"
            fi
            if command -v cargo >/dev/null 2>&1; then
                tmpdir="$(mktemp -d)"
                if git clone --depth 1 https://github.com/Linus789/wl-clip-persist "$tmpdir"; then
                    (
                        cd "$tmpdir" || exit 1
                        cargo build --release
                        sudo cp target/release/wl-clip-persist /usr/local/bin/
                    ) || { err "cargo build $pkg failed."; FAILED_PKGS+=("$pkg"); }
                else
                    err "Failed to clone $pkg."
                    FAILED_PKGS+=("$pkg")
                fi
                rm -rf "$tmpdir"
            else
                err "Cargo not available to build $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        satty)
            if ! command -v cargo-binstall >/dev/null 2>&1; then
                curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash || true # ci:allow-curl-pipe
                export PATH="$PATH:$HOME/.cargo/bin"
                # Persist for future sessions.
                for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
                    touch "$rc" 2>/dev/null || true
                    grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' "$rc" 2>/dev/null || echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc" 2>/dev/null || true
                done
                if command -v fish >/dev/null 2>&1; then
                    fish -c 'fish_add_path ~/.cargo/bin' >/dev/null 2>&1 || true
                fi
            fi
            if command -v cargo-binstall >/dev/null 2>&1; then
                cargo-binstall -y satty || {
                    log "Normal cargo-binstall failed. Trying with sudo..."
                    sudo "$(command -v cargo-binstall)" -y satty || { err "sudo cargo-binstall $pkg failed."; FAILED_PKGS+=("$pkg"); }
                }
            else
                err "cargo-binstall not available to install $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        uv)
            if curl -LsSf https://astral.sh/uv/install.sh | sh; then # ci:allow-curl-pipe
                log "uv installed successfully."
                export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
            else
                err "Failed to install uv."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        konsave)
            export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
            if command -v uv >/dev/null 2>&1; then
                uv tool install konsave || { err "uv tool install $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "uv is required to install $pkg, but it is not available."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        adw-gtk3)
            tmpdir="$(mktemp -d)"
            log "Downloading adw-gtk3 theme..."
            if curl -sL "https://github.com/lassekongo83/adw-gtk3/releases/download/v5.3/adw-gtk3v5.3.tar.xz" | tar -xJ -C "$tmpdir"; then
                mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/themes"
                cp -r "$tmpdir/adw-gtk3" "$tmpdir/adw-gtk3-dark" "${XDG_DATA_HOME:-$HOME/.local/share}/themes/" || { err "Failed to install adw-gtk3"; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to download adw-gtk3 theme."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        matugen)
            # matugen is not packaged for Debian and its toolchain is not in the package
            # list either, so both are built here.
            export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
            if ! command -v cargo >/dev/null 2>&1; then
                log "Installing a Rust toolchain to build matugen..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || true # ci:allow-curl-pipe
                export PATH="$HOME/.cargo/bin:$PATH"
            fi
            if command -v cargo >/dev/null 2>&1; then
                cargo install matugen || { err "cargo install $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "matugen generates the color palette but has no Debian package; install a Rust toolchain and run 'cargo install matugen'."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        *)
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

# Download all fonts in parallel
curl -sL "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" -o "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf" &
_pid_ms=$!

curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip" -o "/tmp/CascadiaCode.zip" &
_pid_cc=$!

curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip" -o "/tmp/JetBrainsMono.zip" &
_pid_jb=$!

curl -sL "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik-VariableFont_wght.ttf" -o "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/Rubik-VariableFont_wght.ttf" &
_pid_ru=$!

# Wait for all downloads to finish
wait $_pid_ms $_pid_cc $_pid_jb $_pid_ru

# Extract zip files
unzip -qo "/tmp/CascadiaCode.zip" -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" 2>/dev/null && rm -f "/tmp/CascadiaCode.zip" || { err "Failed to extract CascadiaCode font."; echo "CascadiaCode font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }
unzip -qo "/tmp/JetBrainsMono.zip" -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" 2>/dev/null && rm -f "/tmp/JetBrainsMono.zip" || { err "Failed to extract JetBrains Mono Nerd Font."; echo "JetBrains Mono Nerd Font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }
# Material Symbols and Rubik are single .ttf files, no extraction needed
[[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf" ]] || { err "Failed to download Material Symbols font."; echo "Material Symbols font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }
[[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/Rubik-VariableFont_wght.ttf" ]] || { err "Failed to download Rubik font."; echo "Rubik font" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"; }

fc-cache -f

log "Installing Darkly KDE Theme from prebuilt package..."
if [[ "$INSTALL_DARKLY" == "true" ]]; then
    if ! command -v darkly >/dev/null 2>&1 && ! dpkg -s darkly >/dev/null 2>&1; then
        _darkly_deb="$(darkly_deb_asset_url || true)"
        if [[ -n "$_darkly_deb" ]]; then
            tmpdir="$(mktemp -d)"
            log "Downloading Darkly .deb from GitHub releases..."
            if curl -fsSL "$_darkly_deb" -o "$tmpdir/darkly.deb"; then
                sudo apt-get install -y "$tmpdir/darkly.deb" || sudo dpkg -i "$tmpdir/darkly.deb" || err "Failed to install Darkly .deb."
            else
                err "Failed to download Darkly .deb from GitHub releases."
            fi
            rm -rf "$tmpdir"
        else
            err "No prebuilt Darkly .deb found for this distro."
        fi
    fi

    log "Installing Darkly GTK theme..."
    sudo apt-get install -y sassc || true
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

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then

log "Installing Caelestia CLI wrapper..."
if ! command -v caelestia >/dev/null 2>&1; then
    sudo apt-get install -y python3-pip python3-build python3-installer python3-hatchling python3-hatch-vcs || true
    tmpdir="$(mktemp -d)"
    (
        cd "$tmpdir" || exit 1
        curl -sL "https://github.com/caelestia-dots/cli/releases/download/v1.0.8/caelestia-1.0.8.tar.gz" -o caelestia.tar.gz
        tar -xzf caelestia.tar.gz
        cd caelestia-1.0.8 || exit 1
        python3 -m build --wheel --no-isolation
        if ! sudo pip3 install dist/*.whl --break-system-packages 2>/dev/null; then
            pip3 install dist/*.whl --user --break-system-packages 2>/dev/null || pip3 install dist/*.whl --user
            if [[ -f "$HOME/.local/bin/caelestia" ]]; then
                sudo ln -sf "$HOME/.local/bin/caelestia" /usr/local/bin/caelestia || true
            fi
        fi

        # Install fish completions if fish is present
        mkdir -p ~/.config/fish/completions/
        cp ./completions/caelestia.fish ~/.config/fish/completions/ 2>/dev/null || true
    )
    rm -rf "$tmpdir"
fi

if command -v sassc >/dev/null 2>&1 && ! command -v sass >/dev/null 2>&1; then
    sudo ln -sf /usr/bin/sassc /usr/local/bin/sass || true
fi

fi  # end of PACKAGE_GROUP shell/all block

log "Debian package installation complete."
