#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"

set -uo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BUNDLE_DIR

source "$BUNDLE_DIR/scripts/lib/log.sh"
source "$BUNDLE_DIR/scripts/lib/installer-bin.sh"

# The update itself belongs to the installer, so this entry point only has to find the binary:
# keeping the published `bash update.sh` working is the whole job, and it stays a bootstrap.
bin="$(caelestia_installer_bin)" || die "The update runs through caelestia-install, which could not be found or downloaded. Set CAELESTIA_INSTALL_BIN to a local build, or re-run install.sh."

CAELESTIA_UPDATE_BRANCH="${1:-}" exec "$bin" --update --bundle "$BUNDLE_DIR"