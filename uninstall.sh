#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"

set -uo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BUNDLE_DIR

source "$BUNDLE_DIR/scripts/lib/log.sh"
source "$BUNDLE_DIR/scripts/lib/installer-bin.sh"

# The uninstall itself belongs to the installer, so this entry point only has to find the
# binary: keeping the published `bash uninstall.sh` working is the whole job.
bin="$(caelestia_installer_bin)" || die "The uninstall runs through caelestia-install, which could not be found or downloaded. Set CAELESTIA_INSTALL_BIN to a local build, or re-run install.sh."

exec "$bin" --uninstall --bundle "$BUNDLE_DIR"