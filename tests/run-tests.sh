#!/usr/bin/env bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

if ! command -v bash >/dev/null 2>&1; then
    echo "bash is required to run the test suite" >&2
    exit 1
fi

if [[ $# -gt 0 ]]; then
    files=()
    for name in "$@"; do
        case "$name" in
            /*) files+=("$name") ;;
            *) files+=("$TESTS_DIR/$name") ;;
        esac
    done
else
    shopt -s nullglob
    files=("$TESTS_DIR"/test_*.sh)
    shopt -u nullglob
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No test files found in $TESTS_DIR" >&2
    exit 1
fi

failed=0
ran=0

for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "FAIL  $(basename "$file") (not found)"
        failed=$((failed + 1))
        continue
    fi

    ran=$((ran + 1))
    echo "RUN   $(basename "$file")"

    output="$(bash "$file" 2>&1)"
    status=$?

    if [[ $status -eq 0 ]]; then
        echo "PASS  $(basename "$file")"
        [[ -n "$output" ]] && printf '%s\n' "$output"
    else
        echo "FAIL  $(basename "$file")"
        [[ -n "$output" ]] && printf '%s\n' "$output"
        failed=$((failed + 1))
    fi
done

echo
if [[ $failed -gt 0 ]]; then
    echo "$failed of $ran test file(s) failed"
    exit 1
fi

echo "All $ran test file(s) passed"
