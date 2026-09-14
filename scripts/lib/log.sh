#!/usr/bin/env bash

if [[ -n "${CAELESTIA_LOG_LOADED:-}" ]]; then
    return 0
fi
CAELESTIA_LOG_LOADED=1

info() { printf '  [INFO]  %s\n' "$*"; }
ok()   { printf '  [OK]    %s\n' "$*"; }
warn() { printf '  [WARN]  %s\n' "$*"; }
skip() { printf '  [SKIP]  %s\n' "$*"; }
err()  { printf '  [ERR]   %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
