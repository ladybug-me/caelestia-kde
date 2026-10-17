#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/log.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/privileges.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/packages.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/plasma-audio-visualizer.sh"

test_plasma_audio_visualizer_present_checks_dirs() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/system-share" "$tmp/system-qml" "$tmp/system-qml64"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        PLASMA_DATA_DIR="$tmp/system-share"
        PLASMA_SYSTEM_QML_DIR="$tmp/system-qml"
        PLASMA_SYSTEM_QML64_DIR="$tmp/system-qml64"
        package_present() { return 1; }
        export -f package_present

        if plasma_audio_visualizer_present; then
            exit 1
        fi

        # Plasmoid without C++ plugin should still return false
        mkdir -p "$tmp/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer"
        if plasma_audio_visualizer_present; then
            exit 2
        fi

        # Plasmoid + C++ plugin present should return true
        mkdir -p "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process"
        touch "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so"
        if ! plasma_audio_visualizer_present; then
            exit 3
        fi
    ) || fail "plasma_audio_visualizer_present check failed"
}

test_ensure_plasma_audio_visualizer_reports_success_when_present() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer"
    mkdir -p "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process"
    touch "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        PLASMA_DATA_DIR="$tmp/system-share"
        PLASMA_SYSTEM_QML_DIR="$tmp/system-qml"
        PLASMA_SYSTEM_QML64_DIR="$tmp/system-qml64"
        BASE_DISTRO=arch
        package_present() { return 1; }
        export -f package_present
        if ! ensure_plasma_audio_visualizer; then
            exit 1
        fi
    ) || fail "ensure_plasma_audio_visualizer should succeed when plasmoid is already present"
}

test_install_plasma_audio_visualizer_arch_calls_yay() {
    local tmp
    tmp="$(new_tmpdir)"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        PLASMA_DATA_DIR="$tmp/system-share"
        PLASMA_SYSTEM_QML_DIR="$tmp/system-qml"
        PLASMA_SYSTEM_QML64_DIR="$tmp/system-qml64"
        BASE_DISTRO=arch
        PATH="/usr/bin:/bin"
        yay() {
            if [[ "$*" == *"-S"* && "$*" == *"plasma6-applets-audio-visualizer"* ]]; then
                mkdir -p "$tmp/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer"
                mkdir -p "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process"
                touch "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so"
                return 0
            fi
            return 1
        }
        export -f yay
        package_present() { return 1; }
        export -f package_present

        if ! install_plasma_audio_visualizer_arch; then
            exit 1
        fi
    ) || fail "install_plasma_audio_visualizer_arch should succeed via yay"

    assert_is_dir "$tmp/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer"
}

test_install_plasma_audio_visualizer_fedora_downloads_repo() {
    local tmp
    tmp="$(new_tmpdir)"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        PLASMA_DATA_DIR="$tmp/system-share"
        PLASMA_SYSTEM_QML_DIR="$tmp/system-qml"
        PLASMA_SYSTEM_QML64_DIR="$tmp/system-qml64"
        BASE_DISTRO=fedora
        PATH="/usr/bin:/bin"
        curl() {
            if [[ "$*" == *"home:luisbocanegra.repo"* ]]; then
                echo "[home_luisbocanegra]" > "$4"
                return 0
            fi
            return 1
        }
        export -f curl
        caelestia_sudo() {
            if [[ "$1" == "dnf" ]]; then
                mkdir -p "$tmp/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer"
                mkdir -p "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process"
                touch "$tmp/.local/lib/qml/com/github/luisbocanegra/audiovisualizer/process/libprocessplugin.so"
                return 0
            fi
            if [[ "$1" == "cp" ]]; then
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo
        package_present() { return 1; }
        export -f package_present

        if ! install_plasma_audio_visualizer_fedora; then
            exit 1
        fi
    ) || fail "install_plasma_audio_visualizer_fedora should succeed via dnf"

    assert_is_dir "$tmp/.local/share/plasma/plasmoids/luisbocanegra.audio.visualizer"
}

run_tests
