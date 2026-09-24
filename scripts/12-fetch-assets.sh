#!/usr/bin/env bash
# ci:allow-no-strict-mode - every failure below is handled and exits 0, because failing

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

ASSETS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/assets"
FONTS_DIR="$ASSETS_DIR/fonts"
SHELL_FONTS="$(install_assets_dir)/fonts"

# Fork identity: the owner publishing release artifacts (the released tag the
# fonts are fetched from here). Upstream default stays ladybug-me; a fork
# points this at the owner whose releases carry the fonts. A full URL
# override remains available via CAELESTIA_ASSETS_REPO.
: "${CAELESTIA_PREBUILT_OWNER:=ladybug-me}"
REPO="${CAELESTIA_ASSETS_REPO:-https://github.com/${CAELESTIA_PREBUILT_OWNER}/caelestia-kde}"

has_fonts() {
    [[ -n "$(find "$1" -maxdepth 2 \( -name '*.ttf' -o -name '*.otf' \) -print -quit 2>/dev/null)" ]]
}

if has_fonts "$SHELL_FONTS"; then
    ok "Fonts are part of this install's tree."
    exit 0
fi

if has_fonts "$FONTS_DIR"; then
    ok "Fonts already downloaded to $FONTS_DIR"
    exit 0
fi

if [[ "${CAELESTIA_SKIP_ASSETS:-}" == "1" ]]; then
    skip "Skipping the font download (CAELESTIA_SKIP_ASSETS=1)."
    exit 0
fi

if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi 'SF Pro'; then
    ok "SF Pro is already installed on this machine."
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    warn "git is not installed, so the fonts cannot be downloaded; the shell will use a system font."
    exit 0
fi

if [[ -n "${CAELESTIA_ASSETS_REF:-}" ]]; then
    GIT_REF="${CAELESTIA_ASSETS_REF#tag=}"
    GIT_REF="${GIT_REF#branch=}"
else
    version="$("$(install_lib_dir)/version" -s 2>/dev/null | awk '{ sub(/,/, "", $2); print $2 }')"
    if [[ -z "$version" ]]; then
        warn "Could not tell which version to download the fonts from; set CAELESTIA_ASSETS_REF to fetch them."
        exit 0
    fi
    GIT_REF="v${version#v}"
fi

info "Downloading the bundled fonts (about 150 MiB, once)..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! git clone --depth 1 --filter=blob:none --sparse "$REPO" "$TMP_DIR/repo" >/dev/null 2>&1; then
    warn "Could not clone $REPO for the fonts; the shell will use a system font. Re-run 'caelestia install' to try again."
    exit 0
fi

if ! git -C "$TMP_DIR/repo" fetch --depth 1 origin "$GIT_REF" >/dev/null 2>&1 ||
    ! git -C "$TMP_DIR/repo" checkout --detach FETCH_HEAD >/dev/null 2>&1; then
    warn "$REPO has no '$GIT_REF'; the shell will use a system font."
    exit 0
fi

if ! git -C "$TMP_DIR/repo" sparse-checkout set shell/assets/fonts >/dev/null 2>&1; then
    warn "Could not check the fonts out of $GIT_REF; the shell will use a system font."
    exit 0
fi

if [[ ! -d "$TMP_DIR/repo/shell/assets/fonts" ]]; then
    warn "$GIT_REF has no shell/assets/fonts to copy."
    exit 0
fi

mkdir -p "$FONTS_DIR"
cp -a "$TMP_DIR/repo/shell/assets/fonts/." "$FONTS_DIR/" || {
    warn "Could not copy the fonts into $FONTS_DIR."
    exit 0
}

ok "Fonts installed into $FONTS_DIR"
