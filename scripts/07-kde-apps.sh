#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

echo
echo ""
info "Installing KDE theme applications"
echo ""

if [[ "${INSTALL_KVANTUM:-true}" == "true" ]]; then
    if [[ "$BASE_DISTRO" == "debian" ]]; then
        install_if_missing qt6-style-kvantum kvantum
        install_if_missing qt5-style-kvantum || true
    elif [[ "$BASE_DISTRO" == "opensuse" ]]; then
        # openSUSE's default repos rarely carry kvantum-manager: it usually lives in the
        # community KDE:Extra project. Left optional (never aborts the install) because
        # it is a Qt style, not something the shell itself needs to run.
        if ! install_if_missing kvantum-manager; then
            if [[ "${CAELESTIA_OBS_REPOS:-no}" == "yes" ]] &&
               caelestia_sudo zypper --non-interactive addrepo -f                    "https://download.opensuse.org/repositories/KDE:/Extra/$(
                       . /etc/os-release; case "$ID" in
                           opensuse-tumbleweed) echo openSUSE_Tumbleweed ;;
                           opensuse-slowroll)   echo openSUSE_Slowroll ;;
                           *)                   echo openSUSE_Factory ;;
                       esac)/KDE:Extra.repo" KDE_Extra 2>/dev/null &&
               caelestia_sudo zypper --non-interactive --gpg-auto-import-keys refresh KDE_Extra; then
                install_if_missing kvantum-manager || true
            else
                warn "kvantum-manager is not in your enabled repositories."
                warn "  It usually lives in the KDE:Extra OBS project. To add it automatically"
                warn "  on a future run, re-run with CAELESTIA_OBS_REPOS=yes, or add it yourself:"
                warn "  sudo zypper ar https://download.opensuse.org/repositories/KDE:/Extra/openSUSE_Tumbleweed/KDE:Extra.repo KDE_Extra"
                warn "  sudo zypper install kvantum-manager"
            fi
        fi
    else
        install_if_missing kvantum
        install_if_missing kvantum-qt5 || true
    fi
else
    skip "Skipping Kvantum installation by user choice."
fi

kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

echo "[OK]  KDE extra apps step complete."
