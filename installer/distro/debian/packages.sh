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

info "Installing Debian packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"

PACKAGE_GROUP="${PACKAGE_GROUP:-all}"

CORE_PACKAGES=(
    cmake ninja-build ccache g++ build-essential qt6-l10n-tools qt6-tools-dev extra-cmake-modules

    wl-clipboard cliphist inotify-tools wireplumber trash-cli jq yq libc6

    libaubio-dev aubio-tools lm-sensors libsensors-dev libpipewire-0.3-dev pipewire libfftw3-dev

    qt6-base-dev qt6-base-private-dev qt6-declarative-dev qml6-module-qtquick qt6-wayland qt6-wayland-dev
    qt6-svg-dev qt6-shadertools-dev qt6-multimedia-dev qt6-5compat-dev qt6-image-formats-plugins

    libkf6globalaccel-dev libkf6windowsystem-dev libkf6guiaddons-dev
    libkf6coreaddons-dev kwin-dev libkf6pulseaudioqt-dev libpulse-dev
    libkf6config-dev libkf6networkmanagerqt-dev libkpipewire-dev
    libepoxy-dev libdrm-dev

    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
    libqalculate-dev qalc libvulkan-dev libsecret-1-dev ksshaskpass libx11-dev
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
    brightnessctl power-profiles-daemon
    xdg-utils sassc python3-venv uv konsave
)

FALLBACK_PKGS=(
    quickshell starship libcava app2unit gpu-screen-recorder cliphist wl-clip-persist satty adw-gtk3 uv konsave matugen
)

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

FAILED_PKGS=()

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

mapfile -t MISSING_PKGS < <(filter_missing "${BATCH_PKGS[@]}")

if (( ${#MISSING_PKGS[@]} > 0 )); then
    info "Updating apt package index..."
    caelestia_sudo apt-get update || true
    info "Batch installing missing Debian packages: ${MISSING_PKGS[*]}"
    if ! caelestia_sudo apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}"; then
        info "Batch install had failures. Retrying standard packages individually..."
        for pkg in "${MISSING_PKGS[@]}"; do
            if ! package_present "$pkg"; then
                caelestia_sudo apt-get install -y --no-install-recommends "$pkg" || {
                    err "apt failed to install $pkg"
                    FAILED_PKGS+=("$pkg")
                }
            fi
        done
    fi
else
    info "All standard Debian packages already installed."
fi

for pkg in "${FALLBACK_TARGETS[@]}"; do
    if package_present "$pkg" || command -v "$pkg" >/dev/null 2>&1; then
        continue
    fi

    # libcava is the one target the package manager cannot report: the prebuilt SDK
    # provides it without being a package, and asking apt for it just fails.
    if [[ "$pkg" == "libcava" ]] && cava_sdk_installed; then
        continue
    fi

    if caelestia_sudo apt-get install -y "$pkg" 2>/dev/null; then
        continue
    fi

    info "apt failed or package missing for $pkg. Attempting manual fallback..."
    case "$pkg" in
        quickshell)
            info "Attempting to install quickshell from PPA..."
            caelestia_sudo apt-get install -y software-properties-common || true
            caelestia_sudo add-apt-repository -y ppa:avengemedia/danklinux || true
            caelestia_sudo apt-get update || true
            caelestia_sudo apt-get install -y quickshell || { err "Failed to install quickshell from PPA."; FAILED_PKGS+=("$pkg"); }
            ;;
        libcava)
            if cava_sdk_installed || install_cava_sdk debian; then
                info "CAVA SDK ready."
            else
                info "Attempting to install cava from PPA..."
                caelestia_sudo apt-get install -y software-properties-common || true
                caelestia_sudo add-apt-repository -y ppa:hsheth2/ppa || true
                caelestia_sudo apt-get update || true
                if caelestia_sudo apt-get install -y cava; then
                    info "cava installed via PPA."
                else
                    err "Failed to install libcava SDK / cava."
                    FAILED_PKGS+=("$pkg")
                fi
            fi
            ;;
        app2unit)
            tmpdir="$(mktemp -d)"
            caelestia_sudo apt-get install -y make scdoc || true
            if git clone --depth 1 https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    caelestia_sudo make install 2>/dev/null || caelestia_sudo make install-bin
                ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        gpu-screen-recorder)
            tmpdir="$(mktemp -d)"
            caelestia_sudo apt-get install -y build-essential git ffmpeg meson libxi-dev libdrm-dev libavcodec-dev libavformat-dev libx11-dev libxcomposite-dev libxdamage-dev libxrender-dev libxrandr-dev libpulse-dev libva-dev libcap-dev libdbus-1-dev libpipewire-0.3-dev libavfilter-dev libvulkan-dev || true
            if git clone --depth 1 https://repo.dec05eba.com/gpu-screen-recorder "$tmpdir"; then
                (
                    cd "$tmpdir" || exit 1
                    caelestia_sudo ./install.sh
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
        cliphist)
            info "Downloading cliphist binary from GitHub releases..."
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
                    caelestia_sudo install -m 755 "$tmpbin" /usr/local/bin/cliphist
                    info "cliphist installed successfully to /usr/local/bin."
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
            caelestia_sudo apt-get install -y build-essential curl git libwayland-dev || true
            if ! command -v cargo >/dev/null 2>&1 || [ "$(rustc --version 2>/dev/null | awk '{print $2}' | cut -d. -f2 || echo 0)" -lt 85 ]; then
                info "Modern Rust toolchain (>= 1.85) required. Installing via rustup..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || true # ci:allow-curl-pipe
                export PATH="$HOME/.cargo/bin:$PATH"
            fi
            if command -v cargo >/dev/null 2>&1; then
                tmpdir="$(mktemp -d)"
                if git clone --depth 1 https://github.com/Linus789/wl-clip-persist "$tmpdir"; then
                    (
                        cd "$tmpdir" || exit 1
                        cargo build --release
                        caelestia_sudo cp target/release/wl-clip-persist /usr/local/bin/
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
                    info "Normal cargo-binstall failed. Trying with sudo..."
                    caelestia_sudo "$(command -v cargo-binstall)" -y satty || { err "sudo cargo-binstall $pkg failed."; FAILED_PKGS+=("$pkg"); }
                }
            else
                err "cargo-binstall not available to install $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        uv)
            if curl -LsSf https://astral.sh/uv/install.sh | sh; then # ci:allow-curl-pipe
                info "uv installed successfully."
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
            info "Downloading adw-gtk3 theme..."
            if curl -fsL "https://github.com/lassekongo83/adw-gtk3/releases/download/v5.3/adw-gtk3v5.3.tar.xz" | tar -xJ -C "$tmpdir"; then
                mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/themes"
                cp -r "$tmpdir/adw-gtk3" "$tmpdir/adw-gtk3-dark" "${XDG_DATA_HOME:-$HOME/.local/share}/themes/" || { err "Failed to install adw-gtk3"; FAILED_PKGS+=("$pkg"); }
            else
                err "Failed to download adw-gtk3 theme."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        matugen)
            export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
            if ! command -v cargo >/dev/null 2>&1; then
                info "Installing a Rust toolchain to build matugen..."
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

curl -fsL "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik-VariableFont_wght.ttf" -o "$FONTS_DIR/Rubik-VariableFont_wght.ttf" &
_pid_ru=$!

wait $_pid_ms $_pid_cc $_pid_jb $_pid_ru

unzip -qo "$_cascadia_zip" -d "$FONTS_DIR" 2>/dev/null && rm -f "$_cascadia_zip" || { rm -f "$_cascadia_zip"; err "Failed to extract CascadiaCode font."; FAILED_PKGS+=("CascadiaCode font"); }
unzip -qo "$_jetbrains_zip" -d "$FONTS_DIR" 2>/dev/null && rm -f "$_jetbrains_zip" || { rm -f "$_jetbrains_zip"; err "Failed to extract JetBrains Mono Nerd Font."; FAILED_PKGS+=("JetBrains Mono Nerd Font"); }
[[ -s "$FONTS_DIR/MaterialSymbolsRounded.ttf" ]] || { err "Failed to download Material Symbols font."; FAILED_PKGS+=("Material Symbols font"); }
[[ -s "$FONTS_DIR/Rubik-VariableFont_wght.ttf" ]] || { err "Failed to download Rubik font."; FAILED_PKGS+=("Rubik font"); }

fc-cache -f

info "Installing Darkly KDE Theme from prebuilt package..."
if [[ "$INSTALL_DARKLY" == "true" ]]; then
    if ! command -v darkly >/dev/null 2>&1 && ! package_present darkly; then
        _darkly_deb="$(darkly_deb_asset_url || true)"
        if [[ -n "$_darkly_deb" ]]; then
            tmpdir="$(mktemp -d)"
            info "Downloading Darkly .deb from GitHub releases..."
            if curl -fsSL "$_darkly_deb" -o "$tmpdir/darkly.deb"; then
                if ! caelestia_sudo apt-get install -y "$tmpdir/darkly.deb" && ! caelestia_sudo dpkg -i "$tmpdir/darkly.deb"; then
                    err "Failed to install Darkly .deb."
                    FAILED_PKGS+=("darkly")
                fi
            else
                err "Failed to download Darkly .deb from GitHub releases."
                FAILED_PKGS+=("darkly")
            fi
            rm -rf "$tmpdir"
        else
            err "No prebuilt Darkly .deb found for this distro."
            FAILED_PKGS+=("darkly")
        fi
    fi

    if ! darkly_gtk_installed; then
        info "Installing Darkly GTK theme..."
        caelestia_sudo apt-get install -y sassc || true
        install_darkly_gtk_theme || FAILED_PKGS+=("darkly-gtk")
    fi
else
    info "Skipping Darkly package installation by user choice."
fi

fi  # end of PACKAGE_GROUP themes/all block

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then

info "Installing Caelestia CLI wrapper..."
if ! command -v caelestia >/dev/null 2>&1; then
    caelestia_sudo apt-get install -y python3-pip python3-build python3-installer python3-hatchling python3-hatch-vcs || true
    tmpdir="$(mktemp -d)"
    (
        cd "$tmpdir" || exit 1
        curl -fsL "https://github.com/caelestia-dots/cli/releases/download/v1.0.8/caelestia-1.0.8.tar.gz" -o caelestia.tar.gz
        tar -xzf caelestia.tar.gz
        cd caelestia-1.0.8 || exit 1
        python3 -m build --wheel --no-isolation
        if ! caelestia_sudo pip3 install dist/*.whl --break-system-packages 2>/dev/null; then
            pip3 install dist/*.whl --user --break-system-packages 2>/dev/null || pip3 install dist/*.whl --user
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

info "Debian package installation complete."
