#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/log.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/privileges.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/packages.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/skwd-wall.sh"

test_skwd_wall_present_checks_path() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/plasma" "$tmp/qml"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        PATH="$tmp/bin:/usr/bin:/bin"
        SKWD_PLASMA_DIR="$tmp/plasma"
        SKWD_QML_DIR="$tmp/qml"
        package_present() { return 1; }
        export -f package_present

        # Neither binary nor plasma plugin present
        if skwd_wall_present; then
            exit 1
        fi

        # Only binary present
        printf '#!/bin/sh\necho "skwd-wall 1.0.0"\n' > "$tmp/bin/skwd-wall-v2"
        chmod +x "$tmp/bin/skwd-wall-v2"
        if skwd_wall_present; then
            exit 2
        fi

        # Both binary and plasma plugin present
        mkdir -p "$tmp/.local/share/plasma/wallpapers/org.skwd.wall.plasma"
        if ! skwd_wall_present; then
            exit 3
        fi
    ) || fail "skwd_wall_present check failed"
}

test_ensure_skwd_wall_reports_success_when_present() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin"
    printf '#!/bin/sh\necho "skwd-wall 1.0.0"\n' > "$tmp/bin/skwd-wall-v2"
    chmod +x "$tmp/bin/skwd-wall-v2"
    mkdir -p "$tmp/.local/share/plasma/wallpapers/org.skwd.wall.plasma"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        BASE_DISTRO=arch
        PATH="$tmp/bin:/usr/bin:/bin"
        SKWD_PLASMA_DIR="$tmp/plasma"
        SKWD_QML_DIR="$tmp/qml"
        package_present() { return 1; }
        export -f package_present
        systemctl() { return 0; }
        export -f systemctl
        if ! ensure_skwd_wall; then
            exit 1
        fi
    ) || fail "ensure_skwd_wall should succeed when skwd-wall is present"
}

test_install_skwd_wall_arch_calls_yay() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/plasma" "$tmp/qml"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        BASE_DISTRO=arch
        PATH="$tmp/bin:/usr/bin:/bin"
        SKWD_PLASMA_DIR="$tmp/plasma"
        SKWD_QML_DIR="$tmp/qml"
        yay() {
            if [[ "$*" == *"-S"* && "$*" == *"skwd-wall-v2-bin"* ]]; then
                printf '#!/bin/sh\necho "skwd-wall 1.0.0"\n' > "$tmp/bin/skwd-wall-v2"
                chmod +x "$tmp/bin/skwd-wall-v2"
                mkdir -p "$tmp/.local/share/plasma/wallpapers/org.skwd.wall.plasma"
                return 0
            fi
            return 1
        }
        export -f yay
        package_present() { return 1; }
        export -f package_present
        systemctl() { return 0; }
        export -f systemctl

        if ! install_skwd_wall_arch; then
            exit 1
        fi
    ) || fail "install_skwd_wall_arch should succeed via yay prebuilt"

    assert_file_exists "$tmp/bin/skwd-wall-v2" "skwd-wall-v2 binary should be present"
}

test_install_skwd_wall_fedora_calls_dnf() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/plasma" "$tmp/qml"

    (
        HOME="$tmp"
        XDG_DATA_HOME="$tmp/.local/share"
        BASE_DISTRO=fedora
        PATH="$tmp/bin:/usr/bin:/bin"
        SKWD_PLASMA_DIR="$tmp/plasma"
        SKWD_QML_DIR="$tmp/qml"
        caelestia_sudo() {
            if [[ "$1" == "dnf" ]]; then
                printf '#!/bin/sh\necho "skwd-wall 1.0.0"\n' > "$tmp/bin/skwd-wall-v2"
                chmod +x "$tmp/bin/skwd-wall-v2"
                mkdir -p "$tmp/.local/share/plasma/wallpapers/org.skwd.wall.plasma"
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo
        package_present() { return 1; }
        export -f package_present
        systemctl() { return 0; }
        export -f systemctl

        if ! install_skwd_wall_fedora; then
            exit 1
        fi
    ) || fail "install_skwd_wall_fedora should succeed via dnf"

    assert_file_exists "$tmp/bin/skwd-wall-v2" "skwd-wall-v2 binary should be present after dnf install"
}

run_tests
