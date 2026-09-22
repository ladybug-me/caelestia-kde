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
    else
        install_if_missing kvantum
        install_if_missing kvantum-qt5 || true
    fi
else
    skip "Skipping Kvantum installation by user choice."
fi

kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

echo "[OK]  KDE extra apps step complete."
