#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/submodules.sh"

BUNDLE_DIR="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ -f "$BUNDLE_DIR/.gitmodules" ]]; then
    info "Initializing submodules..."
    prune_removed_submodules "$BUNDLE_DIR"
    git -C "$BUNDLE_DIR" submodule sync --recursive >/dev/null 2>&1 || true
    git -C "$BUNDLE_DIR" submodule update --init --recursive --depth 1 --jobs "$(nproc 2>/dev/null || echo 1)" >/dev/null 2>&1 || true
fi

if ! submodule_has_content "$BUNDLE_DIR/src/dots"; then
    info "src/dots is empty; fetching it another way."
    if ! ensure_submodule_content "$BUNDLE_DIR" "src/dots"; then
        err "src/dots is still empty, and the installer cannot deploy without it."
        cat >&2 <<EOF

          Fetch it by hand:

            git -C "$BUNDLE_DIR" submodule update --init --recursive src/dots

          Running this step on its own tries again:

            bash "$BUNDLE_DIR/scripts/02a-submodules.sh"

          A checkout that cannot be written to cannot fetch a submodule. If
          this one is the read-only shared folder, clone the repository to a
          writable directory first and install from there.
EOF
        exit 1
    fi
fi

ok "src/dots ready."

if ! submodule_has_content "$BUNDLE_DIR/src/yet-another-monochrome-icon-set"; then
    info "src/yet-another-monochrome-icon-set is empty; fetching it another way."
    if ensure_submodule_content "$BUNDLE_DIR" "src/yet-another-monochrome-icon-set"; then
        ok "Icon set ready."
    else
        warn "Icon set could not be fetched; the monochrome icon theme will be missing."
    fi
fi
