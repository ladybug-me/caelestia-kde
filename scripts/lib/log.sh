#!/usr/bin/env bash
# log.sh - the [INFO]/[OK]/[WARN]/[SKIP]/[ERR] status lines step scripts emit.
# The TUI parses these markers, so the spelling and spacing are load-bearing.

if [[ -n "${CAELESTIA_LOG_LOADED:-}" ]]; then
    return 0
fi
CAELESTIA_LOG_LOADED=1

# No ANSI: output lands in install.log and the TUI strips escapes anyway.
info() { printf '  [INFO]  %s\n' "$*"; }
ok()   { printf '  [OK]    %s\n' "$*"; }
warn() { printf '  [WARN]  %s\n' "$*"; }
skip() { printf '  [SKIP]  %s\n' "$*"; }
err()  { printf '  [ERR]   %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
