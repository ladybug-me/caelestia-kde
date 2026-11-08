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
# points at is handed to dnf as root, so the version this installer ships is fixed here and
# the asset is resolved from that tag alone.
DARKLY_VERSION="0.5.43"

# The pinned release, as "<url>\t<digest>" for the asset this Fedora uses. GitHub reports a
# sha256 for each asset in the same response that names it, so the download can be checked
# against the release it came from without the project publishing a sidecar beside it.
# Printed as one line: callers split on the tab.
darkly_rpm_asset_url() {
    local release_json ver asset
    release_json="$(curl -fsSL "https://api.github.com/repos/Bali10050/Darkly/releases/tags/v${DARKLY_VERSION}" 2>/dev/null || true)"
    [[ -n "$release_json" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    ver="$(rpm -E %fedora 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$ver" ]]; then
        asset="$(printf '%s' "$release_json" | jq -r --arg needle ".fc${ver}.x86_64.rpm" '
            first(.assets[]
                | select((.browser_download_url // "") | test("\\.rpm$") and contains($needle)))
            | "\(.browser_download_url // "")\t\(.digest // "")"
        ' 2>/dev/null)"
        [[ -n "$asset" && "$asset" != $'\t' ]] && { printf '%s\n' "$asset"; return 0; }
    fi
    # No RPM built for this Fedora: the newest one there is still installs, and dnf says so
    # if it does not.
    asset="$(printf '%s' "$release_json" | jq -r '
        first(.assets[] | select((.browser_download_url // "") | test("\\.fc[0-9]+\\.x86_64\\.rpm$")))
        | "\(.browser_download_url // "")\t\(.digest // "")"
    ' 2>/dev/null)"
    [[ -n "$asset" && "$asset" != $'\t' ]] && { printf '%s\n' "$asset"; return 0; }
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

# Copies a font this user downloaded into "$font_dir", once the transfer is known to have
# produced a font. The branch URL the Material Symbols font comes from publishes no hash, so
# the file's type is what says the bytes are the font that was asked for rather than an
# error page saved under a font's name, and the hash is printed so a run records what it
# installed.
install_checked_font() {
    local source="$1" name="$2" kind hash
    if [[ ! -s "$source" ]]; then
        err "Refusing to install $name: the download is empty."
        return 1
    fi
    if command -v file >/dev/null 2>&1; then
        kind="$(file -b "$source" 2>/dev/null || true)"
        case "$kind" in
            *TrueType*|*OpenType*) ;;
            *)
                err "Refusing to install $name: it is not a TrueType or OpenType font ($kind)."
                return 1
                ;;
        esac
    fi
    hash="$(file_sha256 "$source")"
    if ! mv -f "$source" "$font_dir/$name" 2>/dev/null; then
        err "Failed to install $name into $font_dir."
        return 1
    fi
    info "$name installed (SHA-256 $hash)."
}

# A version-pinned archive is only unpacked once its bytes are the ones the version above
# names. The project publishes no checksum beside the archive, so the hash is a constant.
nerd_font_archive_matches() {
    local archive="$1" expected="$2" name="$3" actual
    actual="$(file_sha256 "$archive")"
    if [[ "$actual" != "$expected" ]]; then
        err "Checksum mismatch for $name - not extracting it (got $actual, expected $expected)."
        return 1
    fi
    return 0
}

info "Installing Fedora packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"

PACKAGE_GROUP="${PACKAGE_GROUP:-all}"

# gpu-screen-recorder has no dnf package, so the fallback below builds upstream at a pinned
# revision. Never point this at master: the value is a release tag, and the build is what
# the installer runs, so it has to be a tree this project looked at. A tag can be moved, so
# what the clone is checked against afterwards is the commit it pointed at when this was
# pinned. To update, list the upstream tags with
#   git ls-remote --tags https://repo.dec05eba.com/gpu-screen-recorder
# bump the tag, set the commit from that listing, and test the build before shipping it. The
# Debian script carries the same pair for the same build.
GPU_SCREEN_RECORDER_REF="6.1.3"
GPU_SCREEN_RECORDER_COMMIT="396526a908f8f1b9cb826a9187a2c9150f44d94d"

# The other fallback builds come from clones too, and the installer runs each clone's own
# build and install as root, so which tree that is has to be this project's decision rather
# than whatever a branch holds on the day it runs. The value is an upstream tag, which
# `git clone --depth 1 --branch` accepts; the commit beside it is what the checkout has to
# be, so a tag that was moved fails closed instead of building something else.
APP2UNIT_REF="v1.4.4"
APP2UNIT_COMMIT="47e23ec6ab9e97bbe335c32fb640744a29bf32f7"

# The two Nerd Font archives are version-pinned, so what the login screen ends up with can be
# tied to the release it came from: the project publishes no checksum beside them, and these
# are the SHA-256 of the v3.0.2 assets. To bump the version, take the hash of the new archive
# with
#   curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v<version>/<asset>.zip | sha256sum
NERD_FONTS_VERSION="3.0.2"
CASCADIA_CODE_SHA256="e68cf12cc3c14a18b9ddce0e77f66a78e3ebec4a5224423674fdd9303c5c9272"
JETBRAINS_MONO_SHA256="1fa397478bfca4917dba796eeeb5a428c0834e760b1d96caffff633d6238fdce"

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

    kf6-krunner-devel kf6-baloo

    libqalculate libqalculate-devel libsecret vulkan-headers ksshaskpass libX11-devel

    protobuf-devel protobuf-compiler openssl-devel avahi
)

SHELL_PACKAGES=(
    foot eza fastfetch starship btop bash
    pciutils
)

THEME_PACKAGES=(
    adw-gtk3-theme google-rubik-fonts google-noto-sans-fonts
    google-noto-sans-cjk-ttc-fonts google-noto-emoji-fonts
)

UTILITY_PACKAGES=(
    fuzzel swappy ddcutil NetworkManager iw ImageMagick
    tesseract tesseract-langpack-eng spectacle gpu-screen-recorder
    slurp grim brightnessctl power-profiles-daemon
    xdg-utils sassc bat ripgrep xdg-user-dirs
    plasma-print-manager plasma-keyboard
)

COPR_CORE=(app2unit libcava)
COPR_SHELL=(quickshell-git matugen skwd-wall-v2 skwd-lens skwd-paper-plasma plasma-audio-visualizer)
COPR_UTILS=()

PACKAGES=()
COPR_PKGS=()
case "$PACKAGE_GROUP" in
    core)   PACKAGES=("${CORE_PACKAGES[@]}");   COPR_PKGS=("${COPR_CORE[@]}") ;;
    shell)  PACKAGES=("${SHELL_PACKAGES[@]}");  COPR_PKGS=("${COPR_SHELL[@]}") ;;
    themes) PACKAGES=("${THEME_PACKAGES[@]}");  COPR_PKGS=() ;;
    utils)  PACKAGES=("${UTILITY_PACKAGES[@]}"); COPR_PKGS=("${COPR_UTILS[@]}") ;;
    all|*)  PACKAGES=("${CORE_PACKAGES[@]}" "${SHELL_PACKAGES[@]}" "${THEME_PACKAGES[@]}" "${UTILITY_PACKAGES[@]}")
            COPR_PKGS=("quickshell-git" "gpu-screen-recorder" "app2unit" "starship" "libcava" "wl-clip-persist" "matugen" "skwd-wall-v2" "plasma-audio-visualizer") ;;
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

    if [[ "$pkg" == "matugen" ]]; then
        if package_present matugen; then
            cleanup_legacy_cargo_matugen
            continue
        fi
    elif package_present "$pkg" || command -v "$pkg" >/dev/null 2>&1; then
        continue
    fi

    # libcava is the one target the package manager cannot report: the prebuilt SDK
    # provides it without being a package, and asking dnf for it just fails.
    if [[ "$pkg" == "libcava" ]] && cava_sdk_installed; then
        continue
    fi

    if caelestia_sudo dnf install -y "$pkg" 2>/dev/null; then
        if [[ "$pkg" == "matugen" ]] && package_present matugen; then
            cleanup_legacy_cargo_matugen
        fi
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
        matugen)
            if install_matugen_fedora; then
                COPR_FAILED="no"
            fi
            ;;
        skwd-wall-v2|skwd-wall|skwd-lens|skwd-paper-plasma)
            if install_skwd_wall_fedora; then
                COPR_FAILED="no"
            fi
            ;;
        plasma-audio-visualizer)
            if install_plasma_audio_visualizer_fedora; then
                COPR_FAILED="no"
            fi
            ;;
        gpu-screen-recorder)
            # Install the package that was asked for: the COPR also ships -ui, and
            # reporting success for it would leave gpu-screen-recorder itself missing.
            if caelestia_sudo dnf copr enable -y brycensranch/gpu-screen-recorder-git && caelestia_sudo dnf install -y gpu-screen-recorder; then
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
            if git clone --depth 1 --branch "$APP2UNIT_REF" https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
                if [[ "$(git -C "$tmpdir" rev-parse HEAD)" != "$APP2UNIT_COMMIT" ]]; then
                    err "$pkg: $APP2UNIT_REF no longer points at $APP2UNIT_COMMIT; refusing to build it."
                    FAILED_PKGS+=("$pkg")
                else
                    (
                        cd "$tmpdir" || exit 1
                        install_staged_tree / make install
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
            caelestia_sudo dnf install -y meson ninja-build pkgconf libXcomposite-devel libXrandr-devel libXfixes-devel libdrm-devel wayland-devel pipewire-devel libcap-devel ffmpeg-devel
            info "Building gpu-screen-recorder $GPU_SCREEN_RECORDER_REF from repo.dec05eba.com (pinned ref)."
            if git clone --depth 1 --branch "$GPU_SCREEN_RECORDER_REF" https://repo.dec05eba.com/gpu-screen-recorder "$tmpdir"; then
                if [[ "$(git -C "$tmpdir" rev-parse HEAD)" != "$GPU_SCREEN_RECORDER_COMMIT" ]]; then
                    err "$pkg: $GPU_SCREEN_RECORDER_REF no longer points at $GPU_SCREEN_RECORDER_COMMIT; refusing to build it."
                    FAILED_PKGS+=("$pkg")
                else
                    (
                        cd "$tmpdir" || exit 1
                        meson setup build -Dcapabilities=false && ninja -C build &&
                            install_staged_tree / meson install -C build &&
                            gsr_set_kms_capability /usr/local/bin/gsr-kms-server
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
        *)
            err "No manual fallback defined for $pkg."
            FAILED_PKGS+=("$pkg")
            ;;
    esac
done

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then

info "Downloading and installing required custom fonts (parallel)..."
font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
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

_ms_status=0
_cc_status=0
_jb_status=0
wait "$_pid_ms" || _ms_status=$?
wait "$_pid_cc" || _cc_status=$?
wait "$_pid_jb" || _jb_status=$?

if [[ "$_ms_status" -ne 0 ]]; then
    err "Failed to download Material Symbols font."
    FAILED_PKGS+=("Material Symbols font")
elif ! install_checked_font "$font_tmp/MaterialSymbolsRounded.ttf" MaterialSymbolsRounded.ttf; then
    FAILED_PKGS+=("Material Symbols font")
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

info "Installing Darkly KDE Theme from COPR..."
if [[ "$INSTALL_DARKLY" == "true" ]]; then
    if ! command -v darkly >/dev/null 2>&1 && ! package_present darkly; then
        if ! caelestia_sudo dnf install -y darkly 2>/dev/null; then
            info "Enabling Darkly COPR (deltacopy/darkly)..."
            if ! (caelestia_sudo dnf copr enable -y deltacopy/darkly && caelestia_sudo dnf install -y darkly); then
                info "COPR install failed; falling back to prebuilt RPM from GitHub releases..."
                _darkly_asset="$(darkly_rpm_asset_url || true)"
                _darkly_rpm="${_darkly_asset%%$'\t'*}"
                _darkly_digest="${_darkly_asset#*$'\t'}"
                # No tab means the release reported no digest for the asset at all.
                [[ "$_darkly_digest" == "$_darkly_asset" ]] && _darkly_digest=""
                if [[ -n "$_darkly_rpm" ]]; then
                    # dnf runs the package's maintainer scripts as root, so the bytes are
                    # only handed over once a checksum agrees with them: the digest the
                    # release reports for this asset, or a sidecar if it published one.
                    tmpdir="$(mktemp -d)"
                    info "Downloading Darkly ${DARKLY_VERSION} RPM from GitHub releases..."
                    if ! fetch_asset "$_darkly_rpm" "$tmpdir/darkly.rpm" 2>/dev/null; then
                        err "Failed to download Darkly RPM."
                        FAILED_PKGS+=("darkly")
                    else
                        _darkly_status=0
                        asset_matches_digest "$tmpdir/darkly.rpm" "$_darkly_digest" || _darkly_status=$?
                        if [[ "$_darkly_status" -eq 2 ]]; then
                            verify_download "$_darkly_rpm" "$tmpdir/darkly.rpm" || _darkly_status=$?
                        fi

                        _darkly_install=0
                        case "$_darkly_status" in
                            0) _darkly_install=1 ;;
                            1) err "Checksum mismatch for $_darkly_rpm - not installing it." ;;
                            *)
                                if unverified_download_allowed; then
                                    warn "Installing $_darkly_rpm unverified because CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1 is set."
                                    _darkly_install=1
                                else
                                    warn "No published checksum for $_darkly_rpm (SHA-256 $(file_sha256 "$tmpdir/darkly.rpm"))."
                                    err "Refusing to install $_darkly_rpm unverified; set CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1 to accept it."
                                fi
                                ;;
                        esac

                        if [[ "$_darkly_install" -eq 1 ]]; then
                            if ! caelestia_sudo dnf install -y "$tmpdir/darkly.rpm"; then
                                err "Failed to install Darkly RPM."
                                FAILED_PKGS+=("darkly")
                            fi
                        else
                            FAILED_PKGS+=("darkly")
                        fi
                    fi
                    rm -rf "$tmpdir"
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

fi

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update || true
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
            if [[ -x "/usr/lib64/qt6/bin/qdbus" ]]; then
                caelestia_sudo ln -sf /usr/lib64/qt6/bin/qdbus /usr/local/bin/qdbus6 || true
            elif [[ -x "/usr/lib/qt6/bin/qdbus" ]]; then
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

info "Fedora package installation complete."
