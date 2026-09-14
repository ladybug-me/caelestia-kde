#!/usr/bin/env bash
# check_shell_quality.sh - shell script quality checks for CI.
#
# Usage: bash .github/scripts/check_shell_quality.sh [--fix]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

EXIT_CODE=0
VIOLATIONS=()

log_ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_err()   { echo -e "${RED}[ERR]${RESET}   $*"; VIOLATIONS+=("$*"); EXIT_CODE=1; }

is_in_git() {
    git ls-files --error-unmatch "$1" &>/dev/null
}

# Returns 0 if file has a shebang indicating it's meant to be executed directly
is_executable_script() {
    local file="$1"
    head -c 30 "$file" 2>/dev/null | grep -qE '^#!.*/(ba)?sh'
}

# Every tracked shell script: *.sh plus extensionless files with a shebang (e.g.
# src/bin/caelestia-update), which are easy to forget.
get_shell_files() {
    git ls-files '*.sh'
    git ls-files | while IFS= read -r f; do
        case "$f" in
            *.sh) ;;
            *)
                if is_executable_script "$f"; then
                    echo "$f"
                fi
                ;;
        esac
    done
}

# 1. Syntax: bash -n on every shell script
echo -e "${BOLD}=== Shell Syntax Check (bash -n) ===${RESET}"
for f in $(get_shell_files); do
    if ! bash -n "$f" 2>/dev/null; then
        err_output="$(bash -n "$f" 2>&1 || true)"
        log_err "Syntax error in $f: $err_output"
    fi
done
if [[ "$EXIT_CODE" -eq 0 ]]; then
    log_ok "All shell scripts passed syntax check"
fi

# 2. shellcheck
echo ""
echo -e "${BOLD}=== ShellCheck Lint ===${RESET}"
if command -v shellcheck &>/dev/null; then
    for f in $(get_shell_files); do
        if is_executable_script "$f" || [[ "$f" == scripts/* ]]; then
            if ! shellcheck -S warning "$f" 2>/dev/null; then
                log_err "shellcheck violations in $f"
            fi
        fi
    done
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        log_ok "shellcheck passed on all scripts"
    fi
else
    log_warn "shellcheck not installed - skipping (install with: apt install shellcheck)"
fi

# 3. Strict mode (set -euo pipefail)
echo ""
echo -e "${BOLD}=== Strict Mode Check ===${RESET}"
# Enforced for scripts/. src/bin/* vary their `set` flags on purpose (explicit exits)
# and scripts/lib/* are sourced helpers, where -e would reach every caller. A step
# that must never fail the install opts out with `ci:allow-no-strict-mode`.
for f in $(git ls-files 'scripts/*.sh' 2>/dev/null | grep -v '^scripts/lib/' || true); do
    grep -q 'ci:allow-no-strict-mode' "$f" 2>/dev/null && continue
    if ! grep -qE 'set\s+-euo\s+pipefail|set\s+-eu\s+-o\s+pipefail' "$f" 2>/dev/null; then
        log_err "$f is missing 'set -euo pipefail' (required for scripts in scripts/)"
    fi
done
if [[ "$EXIT_CODE" -eq 0 ]]; then
    log_ok "All scripts in scripts/ use strict mode"
fi

# 4. No curl-pipe-bash patterns
echo ""
echo -e "${BOLD}=== Unsafe Pattern Detection ===${RESET}"
CURL_PIPE_FOUND=0
for f in $(git ls-files '*.sh'); do
    # Skip this checker itself: it describes patterns, not uses them.
    [[ "$f" == ".github/scripts/check_shell_quality.sh" ]] && continue
    # Skip comment-only lines so doc strings don't self-match.
    if grep -nE 'curl\s.*\|\s*(sudo\s+)?(ba)?sh\b' "$f" 2>/dev/null | grep -vE '(^[0-9]+:\s*#|ci:allow-curl-pipe)'; then
        log_err "$f contains unsafe 'curl | bash' pattern"
        CURL_PIPE_FOUND=1
    fi
    # Flag wget -O - | sh patterns too
    if grep -nE 'wget\s.*-O\s*-\s*.*\|\s*(sudo\s+)?(ba)?sh\b' "$f" 2>/dev/null | grep -vE '(^[0-9]+:\s*#|ci:allow-curl-pipe)'; then
        log_err "$f contains unsafe 'wget -O - | sh' pattern"
        CURL_PIPE_FOUND=1
    fi
done
if [[ "$CURL_PIPE_FOUND" -eq 0 ]]; then
    log_ok "No unsafe curl/wget-pipe-shell patterns found"
fi

# Summary
echo ""
if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}All shell quality checks passed.${RESET}"
else
    echo -e "${BOLD}${RED}${#VIOLATIONS[@]} shell quality violation(s) found.${RESET}"
fi

exit "$EXIT_CODE"
