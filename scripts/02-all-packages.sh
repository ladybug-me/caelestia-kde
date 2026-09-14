#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
export PACKAGE_GROUP="all"
if [[ "${BASE_DISTRO:-}" == "arch" ]]; then
    bash "$BUNDLE_DIR/installer/distro/arch/packages.sh"
elif [[ "${BASE_DISTRO:-}" == "fedora" ]]; then
    bash "$BUNDLE_DIR/installer/distro/fedora/packages.sh"
elif [[ "${BASE_DISTRO:-}" == "debian" ]]; then
    bash "$BUNDLE_DIR/installer/distro/debian/packages.sh"
else
    die "BASE_DISTRO must be 'arch', 'fedora', or 'debian' (got '${BASE_DISTRO:-unset}')"
fi
