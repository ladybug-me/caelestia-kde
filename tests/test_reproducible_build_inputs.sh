#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMAKE_FILE="$ROOT/shell/CMakeLists.txt"
FETCH_SCRIPT="$ROOT/scripts/fetch-dependencies.sh"
REVISION_FILE="$ROOT/scripts/m3shapes-revision"
MAKEFILE="$ROOT/Makefile"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -Fq 'set(_M3SHAPES_REVISION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/m3shapes-revision")' "$CMAKE_FILE" \
    || fail "CMake must locate the M3Shapes revision manifest"
grep -Fq 'file(STRINGS "${_M3SHAPES_REVISION_FILE}" M3SHAPES_REV' "$CMAKE_FILE" \
    || fail "CMake must read the M3Shapes revision manifest"
grep -Eq '^[0-9a-f]{40}$' "$REVISION_FILE" \
    || fail "the M3Shapes revision manifest must contain one commit"
grep -Fq 'option(CAELESTIA_OFFLINE "Disallow downloading build dependencies" OFF)' "$CMAKE_FILE" \
    || fail "CMake must expose an offline build mode"
grep -Fq 'CAELESTIA_M3SHAPES_SOURCE_DIR' "$CMAKE_FILE" \
    || fail "CMake must accept a pre-fetched dependency directory"
grep -Fq 'Offline build requested' "$CMAKE_FILE" \
    || fail "offline configure must fail when the dependency is absent"
grep -Fq 'm3shapes-revision' "$FETCH_SCRIPT" \
    || fail "the fetch command must read the revision manifest"
grep -Fq 'fetch-dependencies:' "$MAKEFILE" \
    || fail "make must expose the dependency-fetch command"

echo "PASS: reproducible build inputs are pinned and have an offline path"
