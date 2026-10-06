#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M3SHAPES_REV="$(<"$SCRIPT_DIR/m3shapes-revision")"
[[ "$M3SHAPES_REV" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Invalid M3Shapes revision" >&2
    exit 1
}
M3SHAPES_URL="https://github.com/soramanew/m3shapes.git"
DEPS_DIR="${CAELESTIA_DEPS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde}"
DEST="${DEPS_DIR}/m3shapes-${M3SHAPES_REV}"

if [[ -f "${DEST}/CMakeLists.txt" ]]; then
    current="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$current" == "$M3SHAPES_REV" ]]; then
        printf '%s\n' "$DEST"
        exit 0
    fi
    printf 'M3Shapes cache has revision %s, expected %s\n' "$current" "$M3SHAPES_REV" >&2
    exit 1
fi

command -v git >/dev/null 2>&1 || {
    echo "git is required to fetch M3Shapes" >&2
    exit 1
}

mkdir -p "$DEPS_DIR"
tmp="$(mktemp -d "${DEPS_DIR}/.m3shapes.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

git clone --quiet --filter=blob:none "$M3SHAPES_URL" "$tmp"
git -C "$tmp" fetch --quiet --depth 1 origin "$M3SHAPES_REV"
git -C "$tmp" checkout --quiet --detach "$M3SHAPES_REV"

current="$(git -C "$tmp" rev-parse HEAD)"
[[ "$current" == "$M3SHAPES_REV" ]] || {
    echo "M3Shapes checkout did not resolve to the pinned revision" >&2
    exit 1
}

mv "$tmp" "$DEST"
trap - EXIT
printf '%s\n' "$DEST"