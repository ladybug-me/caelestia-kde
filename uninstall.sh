#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BUNDLE_DIR

source "$BUNDLE_DIR/scripts/lib/log.sh"
source "$BUNDLE_DIR/scripts/lib/installer-bin.sh"

caelestia_run_preset uninstall