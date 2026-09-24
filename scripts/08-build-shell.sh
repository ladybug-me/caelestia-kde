#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/install-fs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/download.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/toolchain.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/update-state.sh"

export BUNDLE_DIR="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SHELL_DIR="$BUNDLE_DIR/shell"

# Fork identity: the owner publishing release artifacts (the prebuilt shell
# archive below). Upstream default stays ladybug-me; a fork that does not
# publish binaries points this at the owner whose releases it ships.
: "${CAELESTIA_PREBUILT_OWNER:=ladybug-me}"

write_shell_environment() {
    local env_d="$HOME/.config/environment.d"
    local plasma_env_d="$HOME/.config/plasma-workspace/env"
    local rc

    info "Writing the shell environment to $env_d/caelestia.conf"
    mkdir -p "$env_d"
    cat > "$env_d/caelestia.conf" << EOF
# Written by Caelestia. Read by systemd for every session process and by the
# user manager the shell's unit runs under.
QML2_IMPORT_PATH=$(install_qml_import_path)
CAELESTIA_LIB_DIR=$(install_lib_dir)
CAELESTIA_BIN_DIR=$(install_bin_dir)
CAELESTIA_SHELL_CONFIG=$(install_shell_config)
EOF
    ok "Shell environment written."

    info "Writing the Plasma session environment to $plasma_env_d/caelestia.sh"
    mkdir -p "$plasma_env_d"
    cat > "$plasma_env_d/caelestia.sh" << EOF
#!/bin/sh
# Written by Caelestia. Sourced by KDE Plasma during session startup for KWin,
# kscreenlocker_greet, and graphical session processes.
export QML2_IMPORT_PATH="$(install_qml_import_path)\${QML2_IMPORT_PATH:+:\$QML2_IMPORT_PATH}"
export CAELESTIA_LIB_DIR="$(install_lib_dir)"
export CAELESTIA_BIN_DIR="$(install_bin_dir)"
export CAELESTIA_SHELL_CONFIG="$(install_shell_config)"
EOF
    chmod +x "$plasma_env_d/caelestia.sh"
    ok "Plasma session environment written."

    for rc in "$HOME/.bashrc" "$HOME/.config/fish/config.fish" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -q 'CAELESTIA_LIB_DIR\|QML2_IMPORT_PATH.*caelestia' "$rc"; then
            sed -i '/CAELESTIA_LIB_DIR/d; /QML2_IMPORT_PATH.*caelestia/d' "$rc"
            info "Removed the Caelestia environment lines from ${rc##*/}"
        fi
    done
}

packaged_shell_setup() {
    write_shell_environment

    skip "Nothing to build: the shell tree is the package's."
}

if install_is_packaged; then
    packaged_shell_setup
    exit 0
fi


if command -v ninja >/dev/null 2>&1; then
    CMAKE_GENERATOR="Ninja"
else
    warn "ninja not found; falling back to Unix Makefiles (builds will be slower)."
    CMAKE_GENERATOR="Unix Makefiles"
fi

caelestia_toolchain_stamp() {
    local cmake_ver qt_ver cava
    cmake_ver="$(cmake --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
    qt_ver="$(pkg-config --modversion Qt6Core 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' || true)"
    cava="$(cava_state)"
    printf 'bundle:%s cmake:%s qt6core:%s gen:%s cava:%s\n' "$BUNDLE_DIR" "$cmake_ver" "$qt_ver" "$CMAKE_GENERATOR" "$cava"
}

caelestia_normalise_stamp() {
    sed -E -e 's/cmake version //' -e 's/([0-9]+\.[0-9]+)\.[0-9]+/\1/g'
}

prepare_build_dir() {
    local dir="$1"
    if [[ -f "$dir/CMakeCache.txt" && -f "$dir/.caelestia_toolchain_stamp" ]] \
        && [[ "$(caelestia_normalise_stamp < "$dir/.caelestia_toolchain_stamp")" \
            == "$(caelestia_toolchain_stamp | caelestia_normalise_stamp)" ]]; then
        return 0
    fi
    rm -rf "$dir"
    mkdir -p "$dir"
    caelestia_toolchain_stamp > "$dir/.caelestia_toolchain_stamp"
}

show_build_errors() {
    local log="$1"
    grep -E 'error:|FAILED:|ninja: build stopped|CMake Error|make(\[[0-9]+\])?: \*\*\*|undefined reference|ld: ' "$log" || true
    echo "----- last 20 lines of $log -----"
    tail -n 20 "$log"
}

BUILD_JOBS="${CAELESTIA_BUILD_JOBS:-}"
if [[ -z "$BUILD_JOBS" ]]; then
    BUILD_JOBS=$(( $(nproc 2>/dev/null || echo 2) - 1 ))
    if [[ $BUILD_JOBS -lt 1 ]]; then
        BUILD_JOBS=1
    fi
fi

BUILD_LOAD="$(nproc 2>/dev/null || echo 2)"

caelestia_build() {
    if command -v nice >/dev/null 2>&1; then
        nice -n 10 "$@"
    else
        "$@"
    fi
}

cleanup_legacy_lockscreen() {
    if command -v kpackagetool6 >/dev/null 2>&1; then
        kpackagetool6 -t Plasma/Wallpaper -r net.dosowisko.PlasmaApplicationWallpaper >/dev/null 2>&1 || true
    fi
    rm -rf "$HOME/.local/share/plasma/wallpapers/net.dosowisko.PlasmaApplicationWallpaper" 2>/dev/null || true
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/wallpaper-plugin-installed" 2>/dev/null || true

    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image" 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group net.dosowisko.PlasmaApplicationWallpaper --group General --key command --delete 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group net.dosowisko.PlasmaApplicationWallpaper --group General --key fps --delete 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key alwaysShowClock --delete 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key showMediaControls --delete 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" --delete 2>/dev/null || true
    fi
}

install_lockscreen_greeter() {
    local src="$BUNDLE_DIR/src/kde/shells/caelestia.desktop"
    local dest="$HOME/.local/share/plasma/shells/caelestia.desktop"

    if [[ ! -d "$src" ]]; then
        warn "Caelestia lock screen greeter source not found: $src"
        return 1
    fi

    info "Installing Caelestia lock screen greeter."
    if ! atomic_replace_tree "$src" "$dest" metadata.json; then
        warn "Failed to install Caelestia lock screen greeter to $dest"
        return 1
    fi

    ok "Caelestia lock screen greeter installed."
}

configure_lockscreen_greeter() {
    if ! command -v kwriteconfig6 >/dev/null 2>&1; then
        warn "KDE config tools (kwriteconfig6) not found. Skipping KDE Lock Screen configuration."
        return 1
    fi

    local shell_pkg="$HOME/.local/share/plasma/shells/caelestia.desktop"
    if [[ ! -d "$shell_pkg" || ! -f "$shell_pkg/metadata.json" ]]; then
        warn "Caelestia lock screen shell package not found at $shell_pkg. Skipping lock screen configuration to prevent session lockout."
        return 1
    fi

    if kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop" 2>/dev/null; then
        ok "KDE Lock Screen configured to use Caelestia greeter."
    else
        warn "Failed to apply KDE Lock Screen configuration."
        return 1
    fi
}

install_visualiser_plasmoid() {
    local src="$BUNDLE_DIR/src/kde/plasmoids/org.caelestia.visualiser"
    local dest="$HOME/.local/share/plasma/plasmoids/org.caelestia.visualiser"

    if [[ ! -d "$src" ]]; then
        warn "Caelestia visualiser plasmoid source not found: $src"
        return 1
    fi

    info "Installing the Caelestia visualiser plasmoid."
    if ! atomic_replace_tree "$src" "$dest" metadata.json; then
        warn "Failed to install the Caelestia visualiser plasmoid to $dest"
        return 1
    fi

    ok "Caelestia visualiser plasmoid installed. Add it to the desktop from the widget toolbox."
}

CCACHE_DIR="${CCACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/ccache}"
export CCACHE_DIR
mkdir -p "$CCACHE_DIR"
if command -v ccache >/dev/null 2>&1; then
    ccache --max-size 8G >/dev/null 2>&1 || true
fi


if [[ "${CAELESTIA_SETUP_RUNNING:-0}" == "0" ]]; then
    info "Running standalone update mode... ensuring prerequisites."

    if [[ -f "$BUNDLE_DIR/scripts/02a-submodules.sh" ]]; then
        bash "$BUNDLE_DIR/scripts/02a-submodules.sh" || die "Failed to initialize submodules"
    fi

    # A checkout that predates `installer/` being in the sparse-checkout rules needs
    # the path adding before anything can read it. src/bin/caelestia-update owns that
    # list and writes it before it checks the tree out; this is the fallback for the
    # copies it already deployed. Run from the tree so the path git prints resolves
    # there, and ask git for it: in a linked worktree .git is a file and the rules
    # live in the main repository instead.
    if [[ ! -d "$BUNDLE_DIR/installer" ]]; then
        (
            cd "$BUNDLE_DIR" || exit 0
            sparse_file="$(git rev-parse --git-path info/sparse-checkout 2>/dev/null || true)"
            [[ -n "$sparse_file" && -f "$sparse_file" ]] || exit 0

            grep -q '^installer/' "$sparse_file" 2>/dev/null || echo "installer/" >> "$sparse_file"
            git read-tree -mu HEAD 2>/dev/null ||
                git checkout HEAD -- installer 2>/dev/null || true
        )
    fi

    if [[ -f "$BUNDLE_DIR/scripts/02-all-packages.sh" && -d "$BUNDLE_DIR/installer" ]]; then
        info "Checking core, shell, theme, and utility dependencies..."
        bash "$BUNDLE_DIR/scripts/02-all-packages.sh" || warn "02-all-packages.sh reported warnings"
    else
        warn "Skipping the dependency check: scripts/02-all-packages.sh or installer/ is missing."
    fi

    info "Deleting yet-another-monochrome-icon-set for lag free update..."
    if [ -z "${SHELL_DIR-}" ]; then
        warn "SHELL_DIR is not set. Aborting deletion to prevent system damage."
        return 1 2>/dev/null || exit 1
    fi
    TARGET_DIR="$SHELL_DIR/assets/icons/yet-another-monochrome-icon-set"
    if [ -d "$TARGET_DIR" ]; then
        if ! rm -rf "$TARGET_DIR"; then
            warn "Failed to delete yet-another-monochrome-icon-set."
            return 1 2>/dev/null || exit 1
        fi
    fi

    info "Installing Caelestia Services..."
    if [[ -f "$BUNDLE_DIR/scripts/06-services.sh" ]]; then
        bash "$BUNDLE_DIR/scripts/06-services.sh" || warn "06-services.sh failed"
    fi

    info "Updating autostart environment variables"
    if [[ -f "$BUNDLE_DIR/scripts/10-autostart.sh" ]]; then
        bash "$BUNDLE_DIR/scripts/10-autostart.sh" || warn "10-autostart.sh failed"
    fi
fi

info "Building the Caelestia shell..."

if [ ! -d "$SHELL_DIR" ]; then
    err "Shell directory not found at $SHELL_DIR!"
    exit 1
fi

if command -v python3 >/dev/null 2>&1 && [[ -f "$BUNDLE_DIR/.github/scripts/check_qml_deployment.py" ]]; then
    python3 "$BUNDLE_DIR/.github/scripts/check_qml_deployment.py" --source-root "$SHELL_DIR" || {
        err "QML source compatibility validation failed."
        exit 1
    }
fi

cd "$SHELL_DIR" || exit 1

shell_qt_abi() {
    pkg-config --modversion Qt6Core 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' || true
}

shell_release_tag() {
    sed -nE 's/^[[:space:]]*VERSION=//p' "$BUNDLE_DIR/.github/version.env" 2>/dev/null | tr -d '[:space:]'
}

# The prebuilt archive holds one released revision, so it may only stand in for a
# tree that is that revision: the released tag itself (an update pinned to a
# version) or main sitting on its remote tip. A branch, a stale main, or a
# checkout carrying commits of its own builds locally instead of letting the
# archive replace them. Main that has moved on since its last release cannot be
# told apart from that release here - version.env still names it - so such a tree
# is replaced by the release the archive was built from.
checkout_may_use_prebuilt() {
    local head revision
    revision="$(shell_release_tag)"
    [[ -n "$revision" ]] || return 1

    head="$(git -C "$BUNDLE_DIR" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$head" ]] || return 1

    if [[ "$(git -C "$BUNDLE_DIR" describe --tags --exact-match "$head" 2>/dev/null || true)" == "$revision" ]]; then
        return 0
    fi

    [[ "$(git -C "$BUNDLE_DIR" branch --show-current 2>/dev/null || true)" == "main" ]] || return 1
    [[ "$head" == "$(git -C "$BUNDLE_DIR" rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null || true)" ]]
}

try_download_prebuilt_shell() {
    local arch qt_abi tag tmp_archive url checksum_status asset candidate
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] || return 1
    [[ -f /etc/arch-release ]] || return 1
    qt_abi="$(shell_qt_abi)"
    tag="$(shell_release_tag)"
    [[ -n "$qt_abi" && -n "$tag" ]] || return 1

    tmp_archive="$(mktemp --suffix=.tar.gz)"
    url=""
    info "Downloading prebuilt shell artifacts (${tag}, Qt ${qt_abi})..."
    for asset in "caelestia-kde-${arch}-qt${qt_abi}.tar.gz" "caelestia-shell-${arch}-qt${qt_abi}.tar.gz"; do
        candidate="https://github.com/${CAELESTIA_PREBUILT_OWNER}/caelestia-kde/releases/download/${tag}/${asset}"
        if fetch_asset "$candidate" "$tmp_archive" --progress-bar; then
            url="$candidate"
            break
        fi
        rm -f "$tmp_archive"
    done
    if [[ -z "$url" ]]; then
        warn "No prebuilt shell artifacts published for ${tag} (Qt ${qt_abi}) - falling back to a local build."
        return 1
    fi

    # Both checksum failures refuse the archive, exactly like the prebuilt
    # installer binary in setup.sh: a sidecar that is missing (2) is not a
    # license to extract code into $HOME unverified - it means falling back to
    # a local build instead.
    checksum_status=0
    verify_download "$url" "$tmp_archive" || checksum_status=$?
    if [[ "$checksum_status" -eq 1 ]]; then
        warn "Checksum mismatch for $url - falling back to a local build."
        rm -f "$tmp_archive"
        return 1
    elif [[ "$checksum_status" -eq 2 ]]; then
        warn "No published checksum for $url - falling back to a local build."
        rm -f "$tmp_archive"
        return 1
    fi
    ok "Prebuilt shell artifacts match the published checksum."

    # The archive is unpacked straight into $HOME, so its listing is audited
    # before tar runs: a member with an absolute path, a ".." component or a
    # link pointing outside would write outside ~/.local and ~/.config.
    if ! archive_is_safe "$tmp_archive"; then
        warn "Prebuilt shell archive failed the safety audit - falling back to a local build."
        rm -f "$tmp_archive"
        return 1
    fi

    info "Extracting prebuilt shell artifacts..."
    mkdir -p "$HOME/.local" "$HOME/.config"
    if ! tar -C "$HOME/.local" -xzf "$tmp_archive" lib; then
        warn "Failed to extract lib from prebuilt shell archive"
        rm -f "$tmp_archive"
        return 1
    fi
    if ! tar -C "$HOME/.config" -xzf "$tmp_archive" quickshell; then
        warn "Failed to extract quickshell from prebuilt shell archive"
        rm -f "$tmp_archive"
        return 1
    fi
    rm -f "$tmp_archive"
    return 0
}

backup_shell_config() {
    local src="$HOME/.config/quickshell/caelestia"
    local root="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/backups"

    if [[ ! -d "$src" ]]; then
        return 0
    fi

    local dest
    if ! dest="$(snapshot_dir "$src" "$root" "quickshell-caelestia" 3)"; then
        err "Could not back up shell configuration into: $root"
        return 1
    fi

    info "Backed up shell configuration to $dest"
    return 0
}

backup_shell_config || exit 1

SHELL_PREBUILT=0
if [[ -z "${CAELESTIA_FORCE_BUILD_SHELL:-}" ]] \
    && checkout_may_use_prebuilt \
    && command -v curl >/dev/null 2>&1; then
    if try_download_prebuilt_shell; then
        SHELL_PREBUILT=1
        ok "Using prebuilt shell artifacts from the release."
    fi
fi


if [[ "$SHELL_PREBUILT" -eq 1 ]]; then
    info "Skipping local shell build; prebuilt artifacts installed."
else
    if ! linguist_tools_available; then
        info "Installing Qt Linguist tools for UI translations..."
        install_linguist_tools "$BASE_DISTRO" || warn "Linguist tools install failed; the shell will stay in English."
    fi

    info "Configuring CMake..."
    prepare_build_dir build
    cmake -G "$CMAKE_GENERATOR" -B build -DCMAKE_BUILD_TYPE=Release -DCAELESTIA_CACHE_DEPS=ON -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DINSTALL_QSCONFDIR="$HOME/.config/quickshell/caelestia" -DINSTALL_LIBDIR="lib/caelestia" -DINSTALL_QMLDIR="lib/qt6/qml" || {
        err "CMake configuration failed."
        exit 1
    }

    info "Building with $BUILD_JOBS parallel jobs..."
    BUILD_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/shell-build.log"
    mkdir -p "$(dirname "$BUILD_LOG")"
    set +e
    caelestia_build cmake --build build -j"$BUILD_JOBS" -- -l "$BUILD_LOAD" 2>&1 | tee "$BUILD_LOG" | grep -vE --line-buffered 'warning:|note:'
    _build_rc=${PIPESTATUS[0]}
    set -e
    if [[ $_build_rc -ne 0 ]]; then
        err "Build failed. Full log: $BUILD_LOG"
        show_build_errors "$BUILD_LOG"
        exit 1
    fi

    info "Installing to user local dir..."
    if ! cmake --install build 2>&1 | tee -a "$BUILD_LOG"; then
        err "Installation failed. Full log: $BUILD_LOG"
        exit 1
    fi
fi

WS_STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/workspace-tracker.installed"

ws_built_effect() {
    local built
    shopt -s nullglob globstar
    for built in kwin-effects/workspace-tracker/build/**/*.so; do
        shopt -u nullglob globstar
        printf '%s\n' "$built"
        return 0
    done
    shopt -u nullglob globstar
    return 1
}

ws_signature() {
    local built="$1" installed="$2"
    printf '%s %s\n' \
        "$(file_sha256 "$built")" \
        "$(stat -c '%s:%Y' "$installed" 2>/dev/null || echo missing)"
}

ws_installed_path() {
    local base="$1" dir
    for dir in /usr/lib/qt6/plugins/kwin/effects/plugins /usr/lib64/qt6/plugins/kwin/effects/plugins; do
        [[ -f "$dir/$base" ]] && { printf '%s\n' "$dir/$base"; return 0; }
    done
    return 1
}

ws_effect_up_to_date() {
    local built installed
    built="$(ws_built_effect)" || return 1
    installed="$(ws_installed_path "$(basename "$built")")" || return 1
    [[ -f "$WS_STAMP" ]] || return 1
    [[ "$(cat "$WS_STAMP")" == "$(ws_signature "$built" "$installed")" ]]
}

ws_record_install() {
    local built installed
    built="$(ws_built_effect)" || return 0
    installed="$(ws_installed_path "$(basename "$built")")" || return 0
    mkdir -p "$(dirname "$WS_STAMP")"
    ws_signature "$built" "$installed" > "$WS_STAMP"
}

info "Building and installing workspace-tracker KWin Effect..."
prepare_build_dir kwin-effects/workspace-tracker/build
WS_INSTALLED=0
WS_RECONFIGURE=1
if cmake -G "$CMAKE_GENERATOR" -B kwin-effects/workspace-tracker/build -S kwin-effects/workspace-tracker -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >/dev/null; then
    WS_BUILD_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/workspace-tracker-build.log"
    if ! caelestia_build cmake --build kwin-effects/workspace-tracker/build -j"$BUILD_JOBS" -- -l "$BUILD_LOAD" >"$WS_BUILD_LOG" 2>&1; then
        warn "Workspace tracker build failed. Full log: $WS_BUILD_LOG"
        show_build_errors "$WS_BUILD_LOG"
    elif ws_effect_up_to_date; then
        info "Workspace tracker already up to date; skipping system install."
        WS_INSTALLED=1
        WS_RECONFIGURE=0
    elif ! caelestia_sudo cmake --install "$PWD/kwin-effects/workspace-tracker/build" >/dev/null; then
        warn "Workspace tracker system installation failed."
    else
        WS_INSTALLED=1
        ws_record_install
    fi
else
    warn "Workspace tracker configuration failed; skipping KWin effect build."
fi

if [[ $WS_INSTALLED -eq 1 ]]; then
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kwinrc --group Plugins --key kwin_workspace_trackerEnabled true
    fi
    if [[ $WS_RECONFIGURE -eq 1 ]]; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
        ok "Installed workspace-tracker to KDE."
    fi
fi

QML_BASE="$HOME/.local/lib/qt6/qml"
QML_MODULES=(
    Caelestia
    Caelestia/Components
    Caelestia/Config
    Caelestia/Settings
    Caelestia/Models
    Caelestia/Services
    Caelestia/Blobs
    Caelestia/Images
    Caelestia/Layouts
    M3Shapes
)

for module in "${QML_MODULES[@]}"; do
    module_dir="$QML_BASE/$module"
    if [[ ! -f "$module_dir/qmldir" ]]; then
        err "Missing QML module metadata: $module_dir/qmldir"
        exit 1
    fi

    shopt -s nullglob
    plugin_files=("$module_dir"/*.so)
    shopt -u nullglob
    if [[ ${#plugin_files[@]} -eq 0 ]]; then
        err "Missing QML plugin library in $module_dir"
        exit 1
    fi
done

export QML2_IMPORT_PATH="$QML_BASE${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

write_shell_environment

mkdir -p ~/.local/bin ~/.config/systemd/user

info "Installing Caelestia bin wrappers..."
install -m 755 "$BUNDLE_DIR/src/bin/caelestia-record" ~/.local/bin/caelestia-record
install -m 755 "$BUNDLE_DIR/src/bin/caelestia-screenshot" ~/.local/bin/caelestia-screenshot
install -m 755 "$BUNDLE_DIR/src/bin/caelestia-shell-ipc" ~/.local/bin/caelestia-shell-ipc
install -m 755 "$BUNDLE_DIR/src/bin/caelestia" ~/.local/bin/caelestia
install -m 755 "$BUNDLE_DIR/src/bin/caelestia-color" ~/.local/bin/caelestia-color
install -m 755 "$BUNDLE_DIR/src/bin/caelestia-update" ~/.local/bin/caelestia-update
install -m 755 "$BUNDLE_DIR/src/bin/caelestia-check-updates" ~/.local/bin/caelestia-check-updates
ok "Caelestia bin wrappers installed to ~/.local/bin"

CAELESTIA_SHARE="$HOME/.local/lib/caelestia"
if [[ -d "$BUNDLE_DIR/src/matugen" && -d "$BUNDLE_DIR/src/schemes" ]]; then
    info "Installing the color pipeline data..."
    rm -rf "$CAELESTIA_SHARE/matugen.old"
    [[ -d "$CAELESTIA_SHARE/matugen" ]] && mv "$CAELESTIA_SHARE/matugen" "$CAELESTIA_SHARE/matugen.old"
    mkdir -p "$CAELESTIA_SHARE"
    cp -r "$BUNDLE_DIR/src/matugen" "$CAELESTIA_SHARE/matugen"
    rm -rf "$CAELESTIA_SHARE/schemes"
    cp -r "$BUNDLE_DIR/src/schemes" "$CAELESTIA_SHARE/schemes"
    rm -rf "$CAELESTIA_SHARE/matugen.old"
    find "$CAELESTIA_SHARE/matugen" "$CAELESTIA_SHARE/schemes" -type d -exec chmod 755 {} +
    find "$CAELESTIA_SHARE/matugen" "$CAELESTIA_SHARE/schemes" -type f -exec chmod 644 {} +
    ok "Color pipeline data installed to $CAELESTIA_SHARE"
    if ! command -v matugen >/dev/null 2>&1; then
        warn "matugen binary is missing from PATH; dynamic wallpaper color schemes require matugen."
    fi
else
    warn "Color pipeline data missing from the checkout; wallpaper and scheme will not work."
fi


DEST_DIR="$HOME/.config/quickshell/caelestia/assets/icons/yet-another-monochrome-icon-set"
TMP_DIR="${DEST_DIR}.tmp"

mkdir -p "$(dirname "$DEST_DIR")"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

if rsync -a --chmod=u+w --exclude='.git' "$BUNDLE_DIR/src/yet-another-monochrome-icon-set/" "$TMP_DIR/"; then
    rm -rf "$DEST_DIR"
    mv "$TMP_DIR" "$DEST_DIR"
    info "Yet another monochrome icon set copied successfully."
else
    rm -rf "$TMP_DIR"
    warn "Failed to copy yet-another-monochrome-icon-set."
fi

record_installed_revision "$BUNDLE_DIR" "$HOME/.config/quickshell/caelestia" || true

if [[ "${CAELESTIA_SKIP_DEPLOY:-0}" == "0" && "${APPLY_LOCKSCREEN:-true}" != "false" ]]; then
    cleanup_legacy_lockscreen
    if install_lockscreen_greeter; then
        configure_lockscreen_greeter || true
    fi
elif [[ "${APPLY_LOCKSCREEN:-true}" == "false" ]]; then
    skip "Lock screen greeter disabled by user choice."
else
    info "KDE Lock Screen installation and configuration skipped."
fi

if [[ "${CAELESTIA_SKIP_DEPLOY:-0}" == "0" && "${APPLY_VISUALISER_PLASMOID:-true}" != "false" ]]; then
    install_visualiser_plasmoid || true
elif [[ "${APPLY_VISUALISER_PLASMOID:-true}" == "false" ]]; then
    skip "Visualiser plasmoid disabled by user choice."
else
    info "Visualiser plasmoid installation skipped."
fi

ok "Caelestia Shell and KDE Bridges built and installed successfully to user directory."
