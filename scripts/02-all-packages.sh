#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
export BUNDLE_DIR

# This is the all-groups entry point: the TUI's "Install packages" step and
# 08-build-shell.sh's update path both want every group at once. A partial install
# calls a distro's packages.sh directly with PACKAGE_GROUP set.
export PACKAGE_GROUP="all"

# The distro name is also the directory its package list lives in, so the dispatch
# is a path rather than a ladder.
packages_script="$BUNDLE_DIR/installer/distro/$BASE_DISTRO/packages.sh"
if [[ ! -f "$packages_script" ]]; then
    die "No package list for '$BASE_DISTRO' (expected arch, fedora or debian)"
fi

bash "$packages_script"
