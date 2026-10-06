#!/usr/bin/env bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

if ! command -v bash >/dev/null 2>&1; then
    echo "bash is required to run the test suite" >&2
    exit 1
fi

suite="all"
timeout_seconds="${CAELESTIA_TEST_TIMEOUT:-120}"
artifact_dir="${CAELESTIA_TEST_ARTIFACTS:-}"
requested=()

usage() {
    printf 'Usage: %s [--suite fast|isolated|all] [--timeout seconds] [--artifacts dir] [test ...]\n' \
        "$(basename "$0")"
    printf 'Each test file declares its suite with a "# suite: fast|isolated" line; the default is fast.\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --suite)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            suite="$2"
            shift 2
            ;;
        --timeout)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            timeout_seconds="$2"
            shift 2
            ;;
        --artifacts)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            artifact_dir="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            requested+=("$@")
            break
            ;;
        *)
            requested+=("$1")
            shift
            ;;
    esac
done

case "$suite" in
    fast|isolated|all) ;;
    *) printf 'Unknown suite: %s\n' "$suite" >&2; usage >&2; exit 2 ;;
esac

if ! [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Timeout must be a positive integer number of seconds: %s\n' "$timeout_seconds" >&2
    exit 2
fi

if [[ -n "$artifact_dir" ]] && ! mkdir -p -- "$artifact_dir"; then
    printf 'Could not create artifact directory: %s\n' "$artifact_dir" >&2
    exit 2
fi

if [[ ${#requested[@]} -gt 0 ]]; then
    files=()
    for name in "${requested[@]}"; do
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
passed=0
ran=0
skipped=0
started_at=$SECONDS
current_tmp=""
current_pid=""

cleanup() {
    local status=$?
    if [[ -n "$current_pid" ]] && kill -0 "$current_pid" 2>/dev/null; then
        kill -TERM "$current_pid" 2>/dev/null || true
        wait "$current_pid" 2>/dev/null || true
    fi
    if [[ -n "$current_tmp" ]]; then
        rm -rf -- "$current_tmp"
        current_tmp=""
    fi
    trap - EXIT INT TERM
    if [[ $status -eq 130 || $status -eq 143 ]]; then
        printf '\nInterrupted after %ss (%s test file(s) started)\n' "$((SECONDS - started_at))" "$ran" >&2
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

suite_for_file() {
    local declared
    declared="$(awk '/^# suite: (fast|isolated)$/ { print $3; exit }' "$1")"
    printf '%s' "${declared:-fast}"
}

for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "FAIL  $(basename "$file") (status 1, elapsed 0s, not found)"
        failed=$((failed + 1))
        continue
    fi

    file_suite="$(suite_for_file "$file")"
    if [[ "$suite" != all && "$suite" != "$file_suite" ]]; then
        skipped=$((skipped + 1))
        echo "SKIP  [$file_suite] $(basename "$file")"
        continue
    fi

    ran=$((ran + 1))
    label="$(basename "$file")"
    test_started_at=$SECONDS
    echo "RUN   [$file_suite] $label"

    current_tmp="$(mktemp -d "${TMPDIR:-/tmp}/caelestia-tests.XXXXXX")"
    output_file="$current_tmp/output.txt"
    if command -v timeout >/dev/null 2>&1; then
        TMPDIR="$current_tmp" timeout --signal=TERM --kill-after=5 "$timeout_seconds" bash "$file" >"$output_file" 2>&1 &
    else
        TMPDIR="$current_tmp" bash "$file" >"$output_file" 2>&1 &
    fi
    current_pid=$!
    wait "$current_pid"
    status=$?
    current_pid=""
    output="$(cat "$output_file")"
    elapsed=$((SECONDS - test_started_at))

    if [[ $status -eq 0 ]]; then
        passed=$((passed + 1))
        echo "PASS  [$file_suite] $label"
        [[ -n "$output" ]] && printf '%s\n' "$output"
    else
        failed=$((failed + 1))
        echo "FAIL  [$file_suite] $label (status $status, elapsed ${elapsed}s)"
        [[ -n "$output" ]] && printf '%s\n' "$output"
        if [[ -n "$artifact_dir" ]]; then
            cp -- "$output_file" "$artifact_dir/$label.txt"
            printf '  diagnostics: %s\n' "$artifact_dir/$label.txt"
        fi
    fi
    rm -rf -- "$current_tmp"
    current_tmp=""
done

echo
echo "Summary: $passed passed, $failed failed, $skipped skipped of $ran run test file(s) in $((SECONDS - started_at))s"
if [[ $failed -gt 0 ]]; then
    exit 1
fi
