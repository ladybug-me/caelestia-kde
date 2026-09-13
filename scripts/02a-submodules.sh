#!/usr/bin/env bash
# 02a-submodules.sh - Fetch the git submodule content.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/submodules.sh"

# Same bundle root as the other steps, so this can run on its own to repair a
# checkout that is missing its submodule content.
BUNDLE_DIR="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ -f "$BUNDLE_DIR/.gitmodules" ]]; then
    info "Initializing submodules..."
    prune_removed_submodules "$BUNDLE_DIR"
    git -C "$BUNDLE_DIR" submodule sync --recursive >/dev/null 2>&1 || true
    git -C "$BUNDLE_DIR" submodule update --init --recursive --depth 1 --jobs "$(nproc 2>/dev/null || echo 1)" >/dev/null 2>&1 || true
fi

# The update above is the quietest way to fail: a shallow fetch can miss the
# recorded commit, and a non-repository checkout cannot run it at all. Content
# is what decides this step's status, so a failed command with another route that
# worked is not a warning.
#
# src/dots holds the files 03 deploys, so failing to fetch it is fatal; the icon
# set only affects a monochrome theme 08 warns about, so it is not.
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

# The icon set only affects a monochrome icon theme, which 08-build-shell.sh warns
# about on its own, so a missing one must not stop an install.
if ! submodule_has_content "$BUNDLE_DIR/src/yet-another-monochrome-icon-set"; then
    info "src/yet-another-monochrome-icon-set is empty; fetching it another way."
    if ensure_submodule_content "$BUNDLE_DIR" "src/yet-another-monochrome-icon-set"; then
        ok "Icon set ready."
    else
        warn "Icon set could not be fetched; the monochrome icon theme will be missing."
    fi
fi
