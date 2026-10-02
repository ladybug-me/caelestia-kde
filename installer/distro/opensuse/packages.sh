#!/usr/bin/env bash
# openSUSE (Tumbleweed, Slowroll, Leap) package installation.
#
# Modelled on the Fedora script: both are RPM systems, but the package names differ
# (qt6-qtbase-devel is qt6-base-devel here, and so on) and openSUSE has no COPR. So the
# shape is the same - repo packages first, then a fallback for what the repos lack - but
# the names come from openSUSE, and the fallbacks are source builds rather than COPRs.
#
# Environment knobs:
#   PACKAGE_GROUP=core|shell|themes|utils|all   which group to install (default all)
#   CAELESTIA_OBS_REPOS=yes                     allow adding the third-party OBS repo
#                                               home:AvengeMedia:danklinux, which carries
#                                               a prebuilt quickshell. Default is "no":
#                                               quickshell is then built from source, which
#                                               also guarantees it matches your Qt exactly.
#   CAELESTIA_QUICKSHELL_REF=<git ref>          quickshell revision to build (default master)

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

info "Installing openSUSE packages..."

INSTALL_FISH="${INSTALL_FISH:-true}"
INSTALL_PAPIRUS="${INSTALL_PAPIRUS:-true}"
INSTALL_DARKLY="${INSTALL_DARKLY:-true}"
PACKAGE_GROUP="${PACKAGE_GROUP:-all}"
CAELESTIA_OBS_REPOS="${CAELESTIA_OBS_REPOS:-no}"
CAELESTIA_QUICKSHELL_REF="${CAELESTIA_QUICKSHELL_REF:-master}"

FAILED_PKGS=()

# --- helpers -------------------------------------------------------------------------

# Non-zero when no enabled repository provides $1. Matches the name or anything that
# provides it, so "qt6-base-devel" and a virtual capability both work. --no-refresh:
# 00-refresh-mirrors.sh already refreshed, and asking again per package would take minutes.
zypper_available() {
    zypper --non-interactive --no-refresh search --match-exact --provides "$1" >/dev/null 2>&1
}

# resolve_candidate "a|b|c" - prints the first alternative that is installed or
# installable and returns 0; returns 1 when none is. openSUSE renames a package between
# Tumbleweed and Leap often enough that a single hardcoded name is a lottery ticket.
resolve_candidate() {
    local IFS='|' cand
    for cand in $1; do
        if package_present "$cand" || zypper_available "$cand"; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    return 1
}

zyp_install() {
    caelestia_sudo zypper --non-interactive install "$@"
}

# ensure_deps <candidate-spec>... - installs whichever alternatives resolve. Used for
# build dependencies of the source-build fallbacks: an unavailable one is a warning,
# not a stop, because the build itself is the authority on whether it was needed.
ensure_deps() {
    local -a want=()
    local entry name
    for entry in "$@"; do
        if name="$(resolve_candidate "$entry")"; then
            package_present "$name" || want+=("$name")
        else
            warn "Build dependency [${entry//|/, }] is not available in your repositories."
        fi
    done
    (( ${#want[@]} == 0 )) && return 0
    zyp_install "${want[@]}"
}

obs_distro_dir() {
    local id ver
    id="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")"
    ver="$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_ID:-}")"
    case "$id" in
        opensuse-tumbleweed) printf 'openSUSE_Tumbleweed\n' ;;
        opensuse-slowroll)   printf 'openSUSE_Slowroll\n' ;;
        opensuse-leap)       printf 'openSUSE_Leap_%s\n' "$ver" ;;
        *) return 1 ;;
    esac
}

# add_obs_repo <alias> <project-path, e.g. home:/AvengeMedia:/danklinux>
# A personal OBS project is a third party: its packages replace nothing by default, but
# adding it also imports its signing key, so this only ever runs behind
# CAELESTIA_OBS_REPOS=yes.
add_obs_repo() {
    local alias="$1" project="$2" dir url
    dir="$(obs_distro_dir)" || { warn "No OBS repository path for this openSUSE flavour."; return 1; }
    # home:/A:/b is the directory form; the .repo file name drops the slashes.
    url="https://download.opensuse.org/repositories/${project}/${dir}/${project//\//}.repo"

    if zypper --non-interactive repos "$alias" >/dev/null 2>&1; then
        return 0
    fi
    warn "Adding third-party OBS repository '$alias' ($url)."
    caelestia_sudo zypper --non-interactive addrepo --refresh "$url" "$alias" &&
        caelestia_sudo zypper --non-interactive --gpg-auto-import-keys refresh "$alias"
}

# --- package groups ------------------------------------------------------------------
# "a|b" lists alternatives, first available wins (see resolve_candidate).

CORE_PACKAGES=(
    cmake ninja ccache "qt6-tools-devel|qt6-tools" qt6-linguist-devel extra-cmake-modules

    wl-clipboard inotify-tools wireplumber trash-cli jq

    aubio-devel "libsensors4-devel|sensors-devel|lm_sensors-devel" pipewire-devel
    "pulseaudio-qt6-devel|pulseaudio-qt-devel" libpulse-devel fftw3-devel

    qt6-base-devel qt6-base-private-devel qt6-declarative-devel qt6-declarative-private-devel
    qt6-wayland qt6-wayland-devel qt6-svg-devel qt6-shadertools-devel
    qt6-multimedia-devel qt6-qt5compat-devel qt6-imageformats
    "qt6-qt5compat-imports|qt6-qt5compat" "qt6-multimedia-imports|qt6-multimedia"

    kf6-kglobalaccel-devel kf6-kwindowsystem-devel kf6-kguiaddons-devel
    kf6-kcoreaddons-devel kwin6-devel kf6-kconfig-devel kf6-networkmanager-qt-devel
    "kpipewire6-devel" "kpipewire6-imports"
    libepoxy-devel libdrm-devel

    libqalculate-devel "libsecret-tools|libsecret-1-0" vulkan-headers
    "ksshaskpass6|ksshaskpass" libX11-devel
)

SHELL_PACKAGES=(
    foot eza fastfetch btop bash
)

THEME_PACKAGES=(
    "google-noto-sans-fonts|noto-sans-fonts" "google-noto-sans-cjk-fonts|noto-sans-cjk-fonts"
    "google-noto-coloremoji-fonts|noto-coloremoji-fonts|google-noto-emoji-fonts"
    "google-rubik-fonts|rubik-fonts"
)

UTILITY_PACKAGES=(
    fuzzel swappy ddcutil NetworkManager ImageMagick
    tesseract-ocr tesseract-ocr-traineddata-english spectacle
    slurp grim brightnessctl power-profiles-daemon
    xdg-utils sassc bat ripgrep xdg-user-dirs
)

# Packages openSUSE's repositories do not carry: each has a dedicated handler below.
SPECIAL_CORE=(cliphist wl-clip-persist app2unit libcava)
SPECIAL_SHELL=(quickshell starship)
SPECIAL_THEMES=(adw-gtk3)
SPECIAL_UTILS=(gpu-screen-recorder)

PACKAGES=()
SPECIAL=()
case "$PACKAGE_GROUP" in
    core)   PACKAGES=("${CORE_PACKAGES[@]}");    SPECIAL=("${SPECIAL_CORE[@]}") ;;
    shell)  PACKAGES=("${SHELL_PACKAGES[@]}");   SPECIAL=("${SPECIAL_SHELL[@]}") ;;
    themes) PACKAGES=("${THEME_PACKAGES[@]}");   SPECIAL=("${SPECIAL_THEMES[@]}") ;;
    utils)  PACKAGES=("${UTILITY_PACKAGES[@]}"); SPECIAL=("${SPECIAL_UTILS[@]}") ;;
    all|*)  PACKAGES=("${CORE_PACKAGES[@]}" "${SHELL_PACKAGES[@]}" "${THEME_PACKAGES[@]}" "${UTILITY_PACKAGES[@]}")
            SPECIAL=("${SPECIAL_CORE[@]}" "${SPECIAL_SHELL[@]}" "${SPECIAL_THEMES[@]}" "${SPECIAL_UTILS[@]}") ;;
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

# --- resolve, then install what the repositories have --------------------------------

RESOLVED=()
for entry in "${PACKAGES[@]}"; do
    if name="$(resolve_candidate "$entry")"; then
        RESOLVED+=("$name")
    else
        warn "No package matching [${entry//|/, }] is available in your repositories."
        FAILED_PKGS+=("${entry%%|*}")
    fi
done

mapfile -t MISSING_PKGS < <(filter_missing "${RESOLVED[@]}")

if (( ${#MISSING_PKGS[@]} > 0 )); then
    info "Installing packages via zypper (batch mode)..."
    if ! zyp_install "${MISSING_PKGS[@]}"; then
        info "Batch install had failures. Retrying standard packages individually..."
        for pkg in "${MISSING_PKGS[@]}"; do
            if ! package_present "$pkg"; then
                if ! zyp_install "$pkg"; then
                    err "zypper failed to install $pkg."
                    FAILED_PKGS+=("$pkg")
                fi
            fi
        done
    fi
else
    info "All standard packages for group $PACKAGE_GROUP are already installed."
fi

# --- packages the repositories do not carry ------------------------------------------

build_quickshell_from_source() {
    info "Building quickshell ($CAELESTIA_QUICKSHELL_REF) from source. This takes a while..."

    # The dependency list is the one openSUSE's own quickshell build recipe uses.
    ensure_deps cmake ninja gcc-c++ git \
        qt6-base-devel qt6-base-private-devel qt6-declarative-devel qt6-declarative-private-devel \
        qt6-wayland-devel qt6-waylandclient-private-devel qt6-linguist-devel qt6-tools-private-devel \
        qt6-svg-devel qt6-shadertools-devel cli11-devel wayland-protocols-devel wayland-devel \
        pam-devel pipewire-devel libdrm-devel libgbm-devel Mesa-libEGL-devel Mesa-libGLESv3-devel \
        polkit-devel jemalloc-devel libxkbcommon-devel libwebp-devel libavif-devel dbus-1-devel \
        libX11-devel libXcomposite-devel libXfixes-devel libXrandr-devel || return 1

    local tmpdir rc=0
    tmpdir="$(mktemp -d)"
    (
        set -e
        cd "$tmpdir"
        git clone --depth 1 --branch "$CAELESTIA_QUICKSHELL_REF" \
            https://github.com/quickshell-mirror/quickshell.git quickshell 2>/dev/null ||
            git clone https://github.com/quickshell-mirror/quickshell.git quickshell
        cd quickshell
        [[ "$CAELESTIA_QUICKSHELL_REF" == "master" ]] || git checkout "$CAELESTIA_QUICKSHELL_REF"
        # /usr/local, not /usr: nothing here is tracked by rpm, and /usr belongs to zypper.
        cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCRASH_REPORTER=off \
            -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=/usr/local
        cmake --build build
        caelestia_sudo cmake --install build
    ) || rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

install_quickshell() {
    command -v quickshell >/dev/null 2>&1 && return 0

    # The git build is what every other distro here uses; the release is the fallback.
    local cand
    for cand in quickshell-git quickshell; do
        if zypper_available "$cand" && zyp_install "$cand"; then
            return 0
        fi
    done

    if [[ "$CAELESTIA_OBS_REPOS" == "yes" ]]; then
        if add_obs_repo danklinux "home:/AvengeMedia:/danklinux"; then
            for cand in quickshell-git quickshell; do
                if zypper_available "$cand" && zyp_install "$cand"; then
                    return 0
                fi
            done
        fi
        warn "The OBS repository did not provide quickshell; building from source instead."
    else
        info "quickshell is not in your repositories; building it from source."
        info "  (To use the prebuilt OBS package instead: CAELESTIA_OBS_REPOS=yes)"
    fi

    build_quickshell_from_source && command -v quickshell >/dev/null 2>&1
}

install_app2unit() {
    command -v app2unit >/dev/null 2>&1 && return 0
    if zypper_available app2unit && zyp_install app2unit; then
        return 0
    fi

    local tmpdir rc=0
    tmpdir="$(mktemp -d)"
    if git clone --depth 1 https://github.com/Vladimir-csp/app2unit "$tmpdir"; then
        ( cd "$tmpdir" && caelestia_sudo make install ) || rc=$?
    else
        err "Failed to clone app2unit."
        rc=1
    fi
    rm -rf "$tmpdir"
    return "$rc"
}

install_libcava() {
    cava_sdk_installed && return 0
    install_cava_sdk opensuse
}

install_cliphist() {
    command -v cliphist >/dev/null 2>&1 && return 0
    if zypper_available cliphist && zyp_install cliphist; then
        return 0
    fi
    if [[ "$CAELESTIA_OBS_REPOS" == "yes" ]] && add_obs_repo danklinux "home:/AvengeMedia:/danklinux" &&
       zypper_available cliphist && zyp_install cliphist; then
        return 0
    fi

    # Written in Go and published as a module: build it, then install the one binary.
    ensure_deps "go|go1.24|go1.25" || return 1
    local tmpdir rc=0
    tmpdir="$(mktemp -d)"
    GOBIN="$tmpdir" go install go.senan.xyz/cliphist@latest &&
        caelestia_sudo install -m 0755 "$tmpdir/cliphist" /usr/local/bin/cliphist || rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

install_wl_clip_persist() {
    command -v wl-clip-persist >/dev/null 2>&1 && return 0
    if zypper_available wl-clip-persist && zyp_install wl-clip-persist; then
        return 0
    fi

    ensure_deps cargo rust gcc-c++ || return 1
    cargo install --locked --git https://github.com/Linus789/wl-clip-persist || return 1
    [[ -x "$HOME/.cargo/bin/wl-clip-persist" ]] || return 1
    caelestia_sudo install -m 0755 "$HOME/.cargo/bin/wl-clip-persist" /usr/local/bin/wl-clip-persist
}

install_starship() {
    command -v starship >/dev/null 2>&1 && return 0
    if zypper_available starship && zyp_install starship; then
        return 0
    fi
    curl -sS https://starship.rs/install.sh | sh -s -- -y  # ci:allow-curl-pipe
}

# Packman carries it for many; the manual build needs ffmpeg development files that the
# stock repositories only ship without codecs, so it is optional here rather than fragile.
install_gpu_screen_recorder() {
    command -v gpu-screen-recorder >/dev/null 2>&1 && return 0
    if zypper_available gpu-screen-recorder && zyp_install gpu-screen-recorder; then
        return 0
    fi
    warn "gpu-screen-recorder is not in your repositories (Packman carries it)."
    warn "Screen recording will be unavailable until it is installed."
    return 1
}

# adw-gtk3: the GTK3 theme the shell's GTK colours are built on.
install_adw_gtk3() {
    local cand
    if cand="$(resolve_candidate "adw-gtk3|adw-gtk3-theme|gtk3-theme-adw-gtk3")" &&
       { package_present "$cand" || zyp_install "$cand"; }; then
        return 0
    fi
    [[ -d "$HOME/.local/share/themes/adw-gtk3" ]] && return 0

    local release_json url tmpdir rc=0
    release_json="$(curl -fsSL https://api.github.com/repos/lassekongo83/adw-gtk3/releases/latest 2>/dev/null || true)"
    url="$(printf '%s' "$release_json" | grep -oE 'https://[^"]*adw-gtk3v[0-9.]+\.tar\.xz' | head -n1)"
    [[ -n "$url" ]] || return 1

    tmpdir="$(mktemp -d)"
    mkdir -p "$HOME/.local/share/themes"
    { curl -fsSL "$url" -o "$tmpdir/adw.tar.xz" &&
      tar -xJf "$tmpdir/adw.tar.xz" -C "$HOME/.local/share/themes"; } || rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

for pkg in "${SPECIAL[@]}"; do
    handler="install_${pkg//-/_}"
    if ! declare -F "$handler" >/dev/null; then
        err "No installer defined for $pkg."
        FAILED_PKGS+=("$pkg")
        continue
    fi
    info "Installing $pkg..."
    if "$handler"; then
        ok "$pkg ready."
    else
        err "Could not install $pkg."
        FAILED_PKGS+=("$pkg")
    fi
done

# --- themes: fonts and Darkly --------------------------------------------------------

build_darkly_from_source() {
    # The Qt6-only subset of the dependency list Darkly's own README gives for Tumbleweed.
    ensure_deps git ninja cmake extra-cmake-modules gcc-c++ \
        kf6-kconfig-devel kf6-frameworkintegration-devel kf6-kconfigwidgets-devel \
        kf6-kguiaddons-devel kf6-ki18n-devel kf6-kiconthemes-devel kf6-kwindowsystem-devel \
        kf6-kcolorscheme-devel kf6-kcoreaddons-devel kf6-kcmutils-devel kf6-kirigami-devel \
        qt6-base-devel qt6-quick-devel qt6-widgets-devel qt6-quickwidgets-devel \
        "kdecoration6-devel|kdecoration-devel|libkdecoration3-devel" libepoxy-devel \
        xcb-util-devel xcb-util-cursor-devel xcb-util-wm-devel xcb-util-keysyms-devel || return 1

    local tmpdir rc=0
    tmpdir="$(mktemp -d)"
    (
        set -e
        git clone --single-branch --depth 1 https://github.com/Bali10050/Darkly.git "$tmpdir/Darkly"
        cd "$tmpdir/Darkly"
        cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_QT5=OFF \
            -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib64
        cmake --build build
        caelestia_sudo cmake --install build
    ) || rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "themes" ]]; then

    info "Downloading and installing required custom fonts (parallel)..."
    mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

    curl -sL "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" -o "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf" &
    _pid_ms=$!
    curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip" -o "/tmp/CascadiaCode.zip" &
    _pid_cc=$!
    curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip" -o "/tmp/JetBrainsMono.zip" &
    _pid_jb=$!
    wait $_pid_ms $_pid_cc $_pid_jb

    unzip -qo "/tmp/CascadiaCode.zip" -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" 2>/dev/null && rm -f "/tmp/CascadiaCode.zip" || { err "Failed to extract CascadiaCode font."; FAILED_PKGS+=("CascadiaCode font"); }
    unzip -qo "/tmp/JetBrainsMono.zip" -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" 2>/dev/null && rm -f "/tmp/JetBrainsMono.zip" || { err "Failed to extract JetBrains Mono Nerd Font."; FAILED_PKGS+=("JetBrains Mono Nerd Font"); }
    [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf" ]] || { err "Failed to download Material Symbols font."; FAILED_PKGS+=("Material Symbols font"); }

    # Rubik is the shell's UI font; when no repository carries it, take it from Google's.
    if ! fc-list 2>/dev/null | grep -qi "rubik"; then
        info "Rubik is not installed; fetching it from Google Fonts..."
        curl -fsSL "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf" \
            -o "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/Rubik[wght].ttf" ||
            { err "Failed to download the Rubik font."; FAILED_PKGS+=("Rubik font"); }
    fi

    fc-cache -f

    if [[ "$INSTALL_DARKLY" == "true" ]]; then
        info "Installing the Darkly KDE theme..."
        if ! command -v darkly >/dev/null 2>&1 && ! package_present darkly; then
            if ! { zypper_available darkly && zyp_install darkly; }; then
                info "darkly is not in your repositories; building it from source..."
                if ! build_darkly_from_source; then
                    err "Failed to build Darkly."
                    FAILED_PKGS+=("darkly")
                fi
            fi
        fi

        if ! darkly_gtk_installed; then
            info "Installing Darkly GTK theme..."
            zyp_install sassc || true
            install_darkly_gtk_theme || FAILED_PKGS+=("darkly-gtk")
        fi
    else
        info "Skipping Darkly package installation by user choice."
    fi
fi

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update || true
fi

# --- the Caelestia CLI wrapper -------------------------------------------------------

if [[ "$PACKAGE_GROUP" == "all" || "$PACKAGE_GROUP" == "shell" ]]; then

    info "Installing Caelestia CLI wrapper..."
    if ! command -v caelestia >/dev/null 2>&1; then
        ensure_deps "python3-pip|python313-pip" "python3-build|python313-build" \
            "python3-installer|python313-installer" "python3-hatchling|python313-hatchling" \
            "python3-hatch-vcs|python313-hatch-vcs" || true
        tmpdir="$(mktemp -d)"
        (
            cd "$tmpdir" || exit 1
            curl -sL "https://github.com/caelestia-dots/cli/releases/download/v1.0.8/caelestia-1.0.8.tar.gz" -o caelestia.tar.gz
            tar -xzf caelestia.tar.gz
            cd caelestia-1.0.8 || exit 1
            # Prefer the offline build against the system's hatchling; if it is not
            # installed, the isolated build fetches its own.
            python3 -m build --wheel --no-isolation || python3 -m build --wheel

            # A per-user install: the system Python belongs to rpm. The symlink is what
            # puts it on the PATH of processes that never read ~/.local/bin.
            pip3 install dist/*.whl --user --break-system-packages
            if [[ -f "$HOME/.local/bin/caelestia" ]]; then
                caelestia_sudo ln -sf "$HOME/.local/bin/caelestia" /usr/local/bin/caelestia || true
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
        fi
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

info "openSUSE package installation complete."
