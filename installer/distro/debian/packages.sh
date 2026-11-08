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
# shellcheck source=scripts/lib/matugen.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/matugen.sh"
# shellcheck source=scripts/lib/skwd-wall.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/skwd-wall.sh"
# shellcheck source=scripts/lib/plasma-audio-visualizer.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/plasma-audio-visualizer.sh"
# shellcheck source=scripts/lib/fonts.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/fonts.sh"
# shellcheck source=scripts/lib/install-fs.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/install-fs.sh"
# shellcheck source=scripts/lib/download.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/scripts/lib/download.sh"

# Where the Darkly package comes from. A release page named `latest` moves, and what it
# points at is handed to apt as root, so the version this installer ships is fixed here and
# the asset is resolved from that tag alone.
DARKLY_VERSION="0.5.43"

# The pinned release, as "<url>\t<digest>" for the asset this distro uses. GitHub reports a
# sha256 for each asset in the same response that names it, so the download can be checked
# against the release it came from without the project publishing a sidecar beside it.
# Printed as one line: callers split on the tab.
darkly_deb_asset_url() {
    local release_json id ver needle asset
    release_json="$(curl -fsSL "https://api.github.com/repos/Bali10050/Darkly/releases/tags/v${DARKLY_VERSION}" 2>/dev/null || true)"
    [[ -n "$release_json" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
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

    # The needles are tried in order, so the most specific asset this distro has wins.
    for needle in "${needles[@]}"; do
        asset="$(printf '%s' "$release_json" | jq -r --arg needle "$needle" '
            first(.assets[]
                | select((.browser_download_url // "") | test("_amd64\\.deb$") and contains($needle)))
            | "\(.browser_download_url // "")\t\(.digest // "")"
        ' 2>/dev/null)"
        if [[ -n "$asset" && "$asset" != $'\t' ]]; then
            printf '%s\n' "$asset"
            return 0
        fi
    done
    return 1
}

# gpu-screen-recorder records a monitor without a password prompt by giving its KMS server
# a capability from a post-install script; that script runs unprivileged now, so the
# capability is applied here, to the binary root just put in place.
gsr_set_kms_capability() {
    local binary="$1"
    if ! caelestia_sudo setcap cap_sys_admin+ep "$binary" 2>/dev/null; then
        warn "Could not grant $binary the capability that skips the password prompt."
    fi
    return 0
}

info "Installing Debian packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"

PACKAGE_GROUP="${PACKAGE_GROUP:-all}"

# gpu-screen-recorder has no apt package, so the fallback below builds upstream at a
# pinned revision. Never point this at master: the value is a release tag, and the build
# is what the installer runs, so it has to be a tree this project looked at. A tag can be
# moved, so what the clone is checked against afterwards is the commit it pointed at when
# this was pinned. To update, list the upstream tags with
#   git ls-remote --tags https://repo.dec05eba.com/gpu-screen-recorder
# bump the tag, set the commit from that listing, and test the build before shipping it.
GPU_SCREEN_RECORDER_REF="6.1.3"
GPU_SCREEN_RECORDER_COMMIT="396526a908f8f1b9cb826a9187a2c9150f44d94d"

# The rest of the fallback builds come from clones as well, and the installer runs each
# clone's own build and install as root, so which tree that is has to be this project's
# decision rather than whatever a branch holds on the day it runs. These are upstream tags,
# which `git clone --depth 1 --branch` accepts; the commit beside each one is what the
# checkout has to be, so a tag that was moved fails closed instead of building something
# else. Updating one means looking at the diff and building it before shipping the bump.
APP2UNIT_REF="v1.4.4"
APP2UNIT_COMMIT="47e23ec6ab9e97bbe335c32fb640744a29bf32f7"
WL_CLIP_PERSIST_REF="v0.5.0"
WL_CLIP_PERSIST_COMMIT="e26fde01c13922e3a65049dafb7d5adfbc52626e"

# cliphist ships one binary per architecture rather than a package, so it is taken from this
# release instead of whichever one happens to be newest when the installer runs.
CLIPHIST_VERSION="0.7.0"

# The pinned release, as "<url>\t<digest>" for the binary this machine needs. The release
# reports a sha256 for each asset in the same response that names it, so the download can be
# checked against the release it came from. Printed as one line: callers split on the tab.
cliphist_asset_url() {
    local carch="$1" release_json asset
    release_json="$(curl -fsSL "https://api.github.com/repos/sentriz/cliphist/releases/tags/v${CLIPHIST_VERSION}" 2>/dev/null || true)"
    [[ -n "$release_json" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    asset="$(printf '%s' "$release_json" | jq -r --arg suffix "-${carch}" '
        first(.assets[] | select((.name // "") | endswith($suffix)))
        | "\(.browser_download_url // "")\t\(.digest // "")"
    ' 2>/dev/null)"
    [[ -n "$asset" && "$asset" != $'\t' ]] || return 1
    printf '%s\n' "$asset"
}

# The two Nerd Font archives are version-pinned, so what the login screen ends up with can be
# tied to the release it came from: the project publishes no checksum beside them, and these
# are the SHA-256 of the v3.0.2 assets. To bump the version, take the hash of the new archive
# with
#   curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v<version>/<asset>.zip | sha256sum
NERD_FONTS_VERSION="3.0.2"
CASCADIA_CODE_SHA256="e68cf12cc3c14a18b9ddce0e77f66a78e3ebec4a5224423674fdd9303c5c9272"
JETBRAINS_MONO_SHA256="1fa397478bfca4917dba796eeeb5a428c0834e760b1d96caffff633d6238fdce"

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

    libkf6runner-dev baloo6

    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
    libqalculate-dev qalc libvulkan-dev libsecret-1-dev ksshaskpass libx11-dev
    libsecret-tools

    libprotobuf-dev protobuf-compiler libssl-dev avahi-daemon
)

SHELL_PACKAGES=(
    foot eza fastfetch btop bash
    pciutils
)

THEME_PACKAGES=(
    adw-gtk3
)

UTILITY_PACKAGES=(
    fuzzel swappy ddcutil network-manager iw imagemagick
    tesseract-ocr tesseract-ocr-eng kde-spectacle slurp grim
    brightnessctl power-profiles-daemon
    xdg-utils sassc python3-venv uv konsave
    print-manager plasma-keyboard
)

FALLBACK_PKGS=(
    quickshell starship libcava app2unit gpu-screen-recorder cliphist wl-clip-persist satty adw-gtk3 uv konsave matugen skwd-wall plasma-audio-visualizer
)

PACKAGES=()
FALLBACK_TARGETS=()
case "$PACKAGE_GROUP" in
    core)   PACKAGES=("${CORE_PACKAGES[@]}");   FALLBACK_TARGETS=("libcava" "app2unit" "cliphist" "matugen") ;;
    shell)  PACKAGES=("${SHELL_PACKAGES[@]}");  FALLBACK_TARGETS=("quickshell" "starship" "skwd-wall" "plasma-audio-visualizer") ;;
    themes) PACKAGES=("${THEME_PACKAGES[@]}");  FALLBACK_TARGETS=("adw-gtk3") ;;
    utils)  PACKAGES=("${UTILITY_PACKAGES[@]}"); FALLBACK_TARGETS=("gpu-screen-recorder" "cliphist" "wl-clip-persist" "satty" "uv" "konsave") ;;
    all|*)  PACKAGES=("${CORE_PACKAGES[@]}" "${SHELL_PACKAGES[@]}" "${THEME_PACKAGES[@]}" "${UTILITY_PACKAGES[@]}")
            FALLBACK_TARGETS=("quickshell" "starship" "libcava" "app2unit" "gpu-screen-recorder" "cliphist" "wl-clip-persist" "satty" "adw-gtk3" "uv" "konsave" "matugen" "skwd-wall" "plasma-audio-visualizer") ;;
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
            if git clone --depth 1 --branch "$APP2UNIT_REF" https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
                if [[ "$(git -C "$tmpdir" rev-parse HEAD)" != "$APP2UNIT_COMMIT" ]]; then
                    err "$pkg: $APP2UNIT_REF no longer points at $APP2UNIT_COMMIT; refusing to build it."
                    FAILED_PKGS+=("$pkg")
                else
                    (
                        cd "$tmpdir" || exit 1
                        install_staged_tree / make install || install_staged_tree / make install-bin
                    ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
                fi
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        gpu-screen-recorder)
            tmpdir="$(mktemp -d)"
            caelestia_sudo apt-get install -y build-essential git ffmpeg meson libxi-dev libdrm-dev libavcodec-dev libavformat-dev libx11-dev libxcomposite-dev libxdamage-dev libxrender-dev libxrandr-dev libpulse-dev libva-dev libcap-dev libdbus-1-dev libpipewire-0.3-dev libavfilter-dev libvulkan-dev || true
            info "Building gpu-screen-recorder $GPU_SCREEN_RECORDER_REF from repo.dec05eba.com (pinned ref)."
            if git clone --depth 1 --branch "$GPU_SCREEN_RECORDER_REF" https://repo.dec05eba.com/gpu-screen-recorder "$tmpdir"; then
                if [[ "$(git -C "$tmpdir" rev-parse HEAD)" != "$GPU_SCREEN_RECORDER_COMMIT" ]]; then
                    err "$pkg: $GPU_SCREEN_RECORDER_REF no longer points at $GPU_SCREEN_RECORDER_COMMIT; refusing to build it."
                    FAILED_PKGS+=("$pkg")
                else
                    (
                        cd "$tmpdir" || exit 1
                        meson setup build --prefix=/usr --buildtype=release -Dsystemd=true -Dstrip=true -Dcapabilities=false &&
                            ninja -C build &&
                            install_staged_tree / meson install -C build &&
                            gsr_set_kms_capability /usr/bin/gsr-kms-server
                    ) || { err "Manual build for $pkg failed."; FAILED_PKGS+=("$pkg"); }
                fi
            else
                err "Failed to clone $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            rm -rf "$tmpdir"
            ;;
        starship)
            _installer="$(mktemp)"
            if fetch_asset https://starship.rs/install.sh "$_installer" 2>/dev/null; then
                info "starship installer SHA-256: $(file_sha256 "$_installer")"
                if sh -s -- -y < "$_installer"; then
                    info "starship installed successfully."
                else
                    err "Failed to install starship; install it yourself with the script from https://starship.rs/install.sh and re-run the installer."
                    FAILED_PKGS+=("$pkg")
                fi
            else
                err "Could not download the starship installer; install it yourself from https://starship.rs/install.sh and re-run the installer."
                FAILED_PKGS+=("$pkg")
            fi
            rm -f "$_installer"
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
            _cliphist_asset="$(cliphist_asset_url "$CARCH" || true)"
            CLIPHIST_URL=""
            _cliphist_digest=""
            IFS=$'\t' read -r CLIPHIST_URL _cliphist_digest <<< "$_cliphist_asset"
            if [ -n "$CLIPHIST_URL" ]; then
                tmpbin="$(mktemp)"
                # The binary is installed as root, so it is only taken once it is the one the
                # pinned release published.
                if fetch_verified_asset "$CLIPHIST_URL" "$tmpbin" "$_cliphist_digest" install; then
                    caelestia_sudo install -m 755 "$tmpbin" /usr/local/bin/cliphist
                    info "cliphist installed successfully to /usr/local/bin."
                else
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
                _installer="$(mktemp)"
                if fetch_asset https://sh.rustup.rs "$_installer" --proto '=https' --tlsv1.2 2>/dev/null; then
                    info "rustup installer SHA-256: $(file_sha256 "$_installer")"
                    sh -s -- -y --default-toolchain stable --profile minimal < "$_installer" || true
                else
                    warn "Could not download the rustup installer; install Rust yourself from https://rustup.rs and re-run the installer."
                fi
                rm -f "$_installer"
                export PATH="$HOME/.cargo/bin:$PATH"
            fi
            if command -v cargo >/dev/null 2>&1; then
                tmpdir="$(mktemp -d)"
                if git clone --depth 1 --branch "$WL_CLIP_PERSIST_REF" https://github.com/Linus789/wl-clip-persist "$tmpdir"; then
                    if [[ "$(git -C "$tmpdir" rev-parse HEAD)" != "$WL_CLIP_PERSIST_COMMIT" ]]; then
                        err "$pkg: $WL_CLIP_PERSIST_REF no longer points at $WL_CLIP_PERSIST_COMMIT; refusing to build it."
                        FAILED_PKGS+=("$pkg")
                    else
                        (
                            cd "$tmpdir" || exit 1
                            cargo build --release
                            # The target directory is the clone's own, and `cp` carries a
                            # symlink to wherever it points; only a file cargo wrote is
                            # promoted.
                            privileged_copy_file target/release/wl-clip-persist /usr/local/bin/wl-clip-persist 0755
                        ) || { err "cargo build $pkg failed."; FAILED_PKGS+=("$pkg"); }
                    fi
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
                _installer="$(mktemp)"
                if fetch_asset https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh "$_installer" --proto '=https' --tlsv1.2 2>/dev/null; then
                    info "cargo-binstall installer SHA-256: $(file_sha256 "$_installer")"
                    bash < "$_installer" || true
                else
                    warn "Could not download the cargo-binstall installer; install it yourself from https://github.com/cargo-bins/cargo-binstall and re-run the installer."
                fi
                rm -f "$_installer"
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
                # cargo-binstall lives in this user's ~/.cargo/bin, and it downloads and
                # unpacks the archive: elevating it would run a file this user can rewrite
                # as root, so a failed install is reported instead of escalated.
                cargo-binstall -y satty || {
                    err "cargo-binstall could not install $pkg; install it yourself with 'cargo-binstall -y $pkg' and re-run the installer."
                    FAILED_PKGS+=("$pkg")
                }
            else
                err "cargo-binstall not available to install $pkg."
                FAILED_PKGS+=("$pkg")
            fi
            ;;
        uv)
            _installer="$(mktemp)"
            if fetch_asset https://astral.sh/uv/install.sh "$_installer" 2>/dev/null; then
                info "uv installer SHA-256: $(file_sha256 "$_installer")"
                if sh < "$_installer"; then
                    info "uv installed successfully."
                    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
                else
                    err "Failed to install uv; install it yourself with the script from https://astral.sh/uv/install.sh and re-run the installer."
                    FAILED_PKGS+=("$pkg")
                fi
            else
                err "Could not download the uv installer; install it yourself from https://astral.sh/uv/install.sh and re-run the installer."
                FAILED_PKGS+=("$pkg")
            fi
            rm -f "$_installer"
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
            install_matugen_debian || FAILED_PKGS+=("$pkg")
            ;;
        skwd-wall|skwd-wall-v2)
            install_skwd_wall_debian || FAILED_PKGS+=("$pkg")
            ;;
        plasma-audio-visualizer)
            install_plasma_audio_visualizer_debian || FAILED_PKGS+=("$pkg")
            ;;
        *)
            FAILED_PKGS+=("$pkg")
            ;;
    esac
done

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then

info "Downloading and installing required custom fonts (parallel)..."
font_dir="$(user_font_dir)"
mkdir -p "$font_dir"
# Every archive goes into a directory only this user can name: a predictable name in /tmp
# is a file someone else can leave behind, and the unzip would take whatever is there.
# Nothing reaches the font directory until the transfer it came from has been checked.
font_tmp="$(mktemp -d)"

fetch_asset "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" "$font_tmp/MaterialSymbolsRounded.ttf" &
_pid_ms=$!

fetch_asset "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/CascadiaCode.zip" "$font_tmp/CascadiaCode.zip" &
_pid_cc=$!

fetch_asset "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/JetBrainsMono.zip" "$font_tmp/JetBrainsMono.zip" &
_pid_jb=$!

# Upstream renamed the file to Rubik[wght].ttf; it is stored under the name the font mirror
# looks for, which is why the URL and the destination do not match.
fetch_asset "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf" "$font_tmp/Rubik-VariableFont_wght.ttf" &
_pid_ru=$!

_ms_status=0
_cc_status=0
_jb_status=0
_ru_status=0
wait "$_pid_ms" || _ms_status=$?
wait "$_pid_cc" || _cc_status=$?
wait "$_pid_jb" || _jb_status=$?
wait "$_pid_ru" || _ru_status=$?

if [[ "$_ms_status" -ne 0 ]]; then
    err "Failed to download Material Symbols font."
    FAILED_PKGS+=("Material Symbols font")
elif ! install_checked_font "$font_tmp/MaterialSymbolsRounded.ttf" MaterialSymbolsRounded.ttf; then
    FAILED_PKGS+=("Material Symbols font")
fi

if [[ "$_ru_status" -ne 0 ]]; then
    err "Failed to download Rubik font."
    FAILED_PKGS+=("Rubik font")
elif ! install_checked_font "$font_tmp/Rubik-VariableFont_wght.ttf" Rubik-VariableFont_wght.ttf; then
    FAILED_PKGS+=("Rubik font")
fi

if [[ "$_cc_status" -ne 0 ]]; then
    err "Failed to download CascadiaCode font."
    FAILED_PKGS+=("CascadiaCode font")
elif ! nerd_font_archive_matches "$font_tmp/CascadiaCode.zip" "$CASCADIA_CODE_SHA256" "CascadiaCode.zip"; then
    FAILED_PKGS+=("CascadiaCode font")
elif ! unzip -qo "$font_tmp/CascadiaCode.zip" -d "$font_dir" 2>/dev/null; then
    err "Failed to extract CascadiaCode font."
    FAILED_PKGS+=("CascadiaCode font")
fi

if [[ "$_jb_status" -ne 0 ]]; then
    err "Failed to download JetBrains Mono Nerd Font."
    FAILED_PKGS+=("JetBrains Mono Nerd Font")
elif ! nerd_font_archive_matches "$font_tmp/JetBrainsMono.zip" "$JETBRAINS_MONO_SHA256" "JetBrainsMono.zip"; then
    FAILED_PKGS+=("JetBrains Mono Nerd Font")
elif ! unzip -qo "$font_tmp/JetBrainsMono.zip" -d "$font_dir" 2>/dev/null; then
    err "Failed to extract JetBrains Mono Nerd Font."
    FAILED_PKGS+=("JetBrains Mono Nerd Font")
fi
rm -rf "$font_tmp"

fc-cache -f

# SDDM runs as its own user and never reads the user's font directory, so the
# fonts above are mirrored system-wide.
mirror_login_fonts || FAILED_PKGS+=("Login screen fonts")

info "Installing Darkly KDE Theme from prebuilt package..."
if [[ "$INSTALL_DARKLY" == "true" ]]; then
    if ! command -v darkly >/dev/null 2>&1 && ! package_present darkly; then
        # apt runs a package's maintainer scripts as root, so the bytes are only handed over
        # once they are the ones the pinned release published.
        _darkly_dir="$(mktemp -d)" || _darkly_dir=""
        if [[ -n "$_darkly_dir" ]] && fetch_darkly_package darkly_deb_asset_url deb "$_darkly_dir"; then
            if ! caelestia_sudo apt-get install -y "$_darkly_dir/darkly.deb" && ! caelestia_sudo dpkg -i "$_darkly_dir/darkly.deb"; then
                err "Failed to install Darkly .deb."
                FAILED_PKGS+=("darkly")
            fi
        else
            err "No usable prebuilt Darkly .deb for this distro."
            FAILED_PKGS+=("darkly")
        fi
        if [[ -n "$_darkly_dir" ]]; then
            rm -rf "$_darkly_dir"
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

fi

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then

if command -v sassc >/dev/null 2>&1 && ! command -v sass >/dev/null 2>&1; then
    caelestia_sudo ln -sf /usr/bin/sassc /usr/local/bin/sass || true
fi

if ! command -v qdbus6 >/dev/null 2>&1; then
    # PATH also holds this user's own directories, and /usr/local/bin/qdbus6 outlives the
    # file it points at: only a path root owns is linked.
    _qdbus_qt6="$(command -v qdbus-qt6 2>/dev/null || true)"
    case "$_qdbus_qt6" in
        /usr/bin/*|/usr/lib/*|/usr/lib64/*)
            caelestia_sudo ln -sf "$_qdbus_qt6" /usr/local/bin/qdbus6 || true
            ;;
        *)
            if [[ -x "/usr/lib/qt6/bin/qdbus" ]]; then
                caelestia_sudo ln -sf /usr/lib/qt6/bin/qdbus /usr/local/bin/qdbus6 || true
            fi
            ;;
    esac
fi

fi

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
    err "The following packages could not be installed:"
    for pkg in "${FAILED_PKGS[@]}"; do
        err "  - $pkg"
        echo "$pkg" >> "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/failed_packages.txt"
    done
fi

info "Debian package installation complete."
