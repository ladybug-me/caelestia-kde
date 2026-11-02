#!/usr/bin/env bash
# Helper for ensuring plasma-audio-visualizer (plasmoid + C++ plugin) is installed
# across different distributions and visible in KDE Plasma's widget list.
if [[ -z "${CAELESTIA_PLASMA_AUDIO_VISUALIZER_SOURCED:-}" ]]; then
CAELESTIA_PLASMA_AUDIO_VISUALIZER_SOURCED=1

# shellcheck source=scripts/lib/log.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/log.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/privileges.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/privileges.sh" 2>/dev/null || true
# shellcheck source=scripts/lib/packages.sh
source "${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/lib/packages.sh" 2>/dev/null || true

refresh_plasma_widget_cache() {
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi
}

ensure_plasma_audio_visualizer_permissions() {
    local user_monitor="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/luisbocanegra.audio.visualizer/contents/ui/tools/commandMonitor"
    if [[ -f "$user_monitor" ]]; then
        chmod 700 "$user_monitor" 2>/dev/null || true
    fi
    refresh_plasma_widget_cache
}

plasma_audio_visualizer_cpp_plugin_present() {
    [[ -f "${PLASMA_SYSTEM_QML_DIR:-/usr/lib/qt6/qml}/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so" ]] || \
    [[ -f "${PLASMA_SYSTEM_QML64_DIR:-/usr/lib64/qt6/qml}/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so" ]] || \
    [[ -f "$HOME/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so" ]] || \
    [[ -f "$HOME/.local/lib64/qml/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so" ]] || \
    [[ -f "${PLASMA_QML_DIR:-}/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so" ]]
}

plasma_audio_visualizer_plasmoid_present() {
    package_present "plasma6-applets-audio-visualizer" 2>/dev/null || \
    package_present "plasma-audio-visualizer" 2>/dev/null || \
    [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/luisbocanegra.audio.visualizer" ]] || \
    [[ -d "${PLASMA_DATA_DIR:-/usr/share}/plasma/plasmoids/luisbocanegra.audio.visualizer" ]] || \
    (command -v kpackagetool6 >/dev/null 2>&1 && kpackagetool6 -t Plasma/Applet -s luisbocanegra.audio.visualizer >/dev/null 2>&1)
}

plasma_audio_visualizer_present() {
    plasma_audio_visualizer_plasmoid_present && plasma_audio_visualizer_cpp_plugin_present
}

install_plasma_audio_visualizer_source() {
    info "Compiling and installing plasma-audio-visualizer with C++ plugin from source..."
    local src_dir="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/plasma-audio-visualizer"
    local tmp_dir="" cleanup_tmp=false

    if [[ ! -d "$src_dir" || ! -f "$src_dir/CMakeLists.txt" ]]; then
        tmp_dir="$(mktemp -d)"
        cleanup_tmp=true
        if ! git clone --depth 1 "https://github.com/luisbocanegra/plasma-audio-visualizer.git" "$tmp_dir"; then
            err "Failed to clone plasma-audio-visualizer repository."
            rm -rf "$tmp_dir"
            return 1
        fi
        src_dir="$tmp_dir"
    fi

    # Compile translations if kpac is available
    if [[ -x "$src_dir/kpac" ]] && command -v python3 >/dev/null 2>&1; then
        (cd "$src_dir" && python3 ./kpac i18n --no-merge >/dev/null 2>&1 || true)
    fi

    local build_dir="$src_dir/build"
    rm -rf "$build_dir"
    mkdir -p "$build_dir/plasmoid" "$build_dir/plugin"

    local plasmoid_ok=false plugin_ok=false

    # 1. Build and install plasmoid for user
    if cmake -B "$build_dir/plasmoid" -S "$src_dir" -DINSTALL_PLASMOID=ON -DCMAKE_INSTALL_PREFIX="${XDG_DATA_HOME:-$HOME/.local}" >/dev/null 2>&1 && \
       cmake --build "$build_dir/plasmoid" >/dev/null 2>&1 && \
       cmake --install "$build_dir/plasmoid" >/dev/null 2>&1; then
        plasmoid_ok=true
    elif command -v kpackagetool6 >/dev/null 2>&1 && [[ -d "$src_dir/package" ]]; then
        if kpackagetool6 -t Plasma/Applet -u "$src_dir/package" >/dev/null 2>&1 || \
           kpackagetool6 -t Plasma/Applet -i "$src_dir/package" >/dev/null 2>&1; then
            plasmoid_ok=true
        fi
    fi

    # 2. Build and install C++ plugin system-wide (preferred)
    if cmake -B "$build_dir/plugin" -S "$src_dir" -DBUILD_PLUGIN=ON -DCMAKE_INSTALL_PREFIX=/usr >/dev/null 2>&1 && \
       cmake --build "$build_dir/plugin" >/dev/null 2>&1; then
        if caelestia_sudo cmake --install "$build_dir/plugin" >/dev/null 2>&1; then
            plugin_ok=true
        fi
    fi

    # Fallback: install C++ plugin to user prefix and configure QML_IMPORT_PATH if system install failed
    if [[ "$plugin_ok" != "true" ]]; then
        local user_prefix="$HOME/.local"
        if cmake -B "$build_dir/plugin-user" -S "$src_dir" -DBUILD_PLUGIN=ON -DCMAKE_INSTALL_PREFIX="$user_prefix" >/dev/null 2>&1 && \
           cmake --build "$build_dir/plugin-user" >/dev/null 2>&1 && \
           cmake --install "$build_dir/plugin-user" >/dev/null 2>&1; then
            local env_dir="$HOME/.config/plasma-workspace/env"
            mkdir -p "$env_dir"
            local path_sh="$env_dir/path.sh"
            local import_export='export QML_IMPORT_PATH="$HOME/.local/lib64/qml:$HOME/.local/lib/qml:$QML_IMPORT_PATH"'
            if ! grep -qs "QML_IMPORT_PATH" "$path_sh" 2>/dev/null; then
                echo "$import_export" >> "$path_sh"
            fi
            export QML_IMPORT_PATH="$HOME/.local/lib64/qml:$HOME/.local/lib/qml:${QML_IMPORT_PATH:-}"
            plugin_ok=true
        fi
    fi

    if [[ "$cleanup_tmp" == "true" ]]; then
        rm -rf "$tmp_dir"
    fi

    ensure_plasma_audio_visualizer_permissions

    if [[ "$plasmoid_ok" == "true" && "$plugin_ok" == "true" ]] || plasma_audio_visualizer_present; then
        apply_plasma_audio_visualizer_config
        ok "plasma-audio-visualizer (plasmoid + C++ plugin) built and installed successfully."
        return 0
    fi

    err "Failed to build and install plasma-audio-visualizer with C++ plugin."
    return 1
}

install_plasma_audio_visualizer_arch() {
    info "Installing plasma-audio-visualizer on Arch (Priority 1: AUR package)..."
    if command -v yay >/dev/null 2>&1; then
        if yay -S --needed --noconfirm plasma6-applets-audio-visualizer 2>/dev/null; then
            ensure_plasma_audio_visualizer_permissions
            if plasma_audio_visualizer_present; then
                apply_plasma_audio_visualizer_config
                ok "plasma-audio-visualizer installed successfully via AUR."
                return 0
            fi
        fi
    fi

    warn "AUR installation failed or unavailable; falling back to source build for Arch (Priority 2)..."
    caelestia_sudo pacman -S --needed --noconfirm git gcc cmake extra-cmake-modules libplasma cava qt6-websockets python-websockets 2>/dev/null || true
    install_plasma_audio_visualizer_source
}

install_plasma_audio_visualizer_fedora() {
    info "Installing plasma-audio-visualizer on Fedora (Priority 1: OBS RPM package)..."
    local fedora_ver repo_url
    fedora_ver="$(rpm -E %fedora 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$fedora_ver" ]] || fedora_ver="41"
    repo_url="https://download.opensuse.org/repositories/home:/luisbocanegra/Fedora_${fedora_ver}/home:luisbocanegra.repo"

    local tmp_repo
    tmp_repo="$(mktemp)"
    if curl -fsSL "$repo_url" -o "$tmp_repo" 2>/dev/null; then
        if caelestia_sudo cp "$tmp_repo" /etc/yum.repos.d/home:luisbocanegra.repo 2>/dev/null; then
            rm -f "$tmp_repo"
            if caelestia_sudo dnf install -y plasma-audio-visualizer 2>/dev/null; then
                ensure_plasma_audio_visualizer_permissions
                if plasma_audio_visualizer_present; then
                    apply_plasma_audio_visualizer_config
                    ok "plasma-audio-visualizer installed successfully via dnf (OBS)."
                    return 0
                fi
            fi
        fi
    fi
    rm -f "$tmp_repo"

    warn "OBS RPM installation failed; falling back to source build for Fedora (Priority 2)..."
    caelestia_sudo dnf install -y git gcc-c++ cmake extra-cmake-modules libplasma-devel cava qt6-qtwebsockets-devel python3-websockets 2>/dev/null || true
    install_plasma_audio_visualizer_source
}

install_plasma_audio_visualizer_debian() {
    info "Installing plasma-audio-visualizer on Debian (Priority 1: Source build with C++ plugin)..."
    caelestia_sudo apt-get update 2>/dev/null || true
    caelestia_sudo apt-get install -y git build-essential cmake extra-cmake-modules libplasma-dev cava qt6-websockets-dev python3-websockets 2>/dev/null || true
    install_plasma_audio_visualizer_source
}

apply_plasma_audio_visualizer_config() {
    local repo_root="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    local export_script="$repo_root/shell/scripts/export-plasma-config.sh"
    if [[ -x "$export_script" ]]; then
        info "Applying plasma-audio-visualizer configuration..."
        "$export_script" visualizer 2>/dev/null || true
    fi
}

ensure_plasma_audio_visualizer() {
    if plasma_audio_visualizer_present; then
        ensure_plasma_audio_visualizer_permissions
        apply_plasma_audio_visualizer_config
        ok "plasma-audio-visualizer (plasmoid + C++ plugin) is installed."
        return 0
    fi

    local status=1
    case "${BASE_DISTRO:-unknown}" in
        fedora)
            install_plasma_audio_visualizer_fedora && status=0
            ;;
        arch)
            install_plasma_audio_visualizer_arch && status=0
            ;;
        debian)
            install_plasma_audio_visualizer_debian && status=0
            ;;
        *)
            if install_plasma_audio_visualizer_arch || install_plasma_audio_visualizer_fedora || install_plasma_audio_visualizer_debian; then
                status=0
            fi
            ;;
    esac

    if [[ "$status" -eq 0 ]] && plasma_audio_visualizer_present; then
        ensure_plasma_audio_visualizer_permissions
        apply_plasma_audio_visualizer_config
        return 0
    fi

    warn "plasma-audio-visualizer is not installed."
    record_failed_package "plasma-audio-visualizer" 2>/dev/null || true
    return 1
}

fi
