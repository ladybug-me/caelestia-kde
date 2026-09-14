#!/usr/bin/env bash
if [[ -z "${CAELESTIA_TEST_HELPERS_SOURCED:-}" ]]; then
CAELESTIA_TEST_HELPERS_SOURCED=1

CAELESTIA_TEST_FAILURES=0
CAELESTIA_TEST_COUNT=0
CAELESTIA_TEST_TMPDIRS=()

fail() {
    CAELESTIA_TEST_FAILURES=$((CAELESTIA_TEST_FAILURES + 1))
    printf '    FAIL: %s\n' "$*" >&2
}

skip_test() {
    printf '    SKIP: %s\n' "$1"
}

fail_with_output() {
    local message="$1" output="$2"
    CAELESTIA_TEST_FAILURES=$((CAELESTIA_TEST_FAILURES + 1))
    printf '    FAIL: %s\n' "$message" >&2
    [[ -n "$output" ]] && printf '      output: %s\n' "$output" >&2
    return 0
}

assert_eq() {
    local expected="$1" actual="$2" message="${3:-values differ}"
    if [[ "$expected" != "$actual" ]]; then
        fail "$message (expected: $(printf '%q' "$expected"), actual: $(printf '%q' "$actual"))"
    fi
}

assert_ne() {
    local unexpected="$1" actual="$2" message="${3:-values should differ}"
    if [[ "$unexpected" == "$actual" ]]; then
        fail "$message (both were: $(printf '%q' "$actual"))"
    fi
}

assert_status() {
    local expected="$1" actual="$2" message="${3:-unexpected exit status}"
    if [[ "$expected" != "$actual" ]]; then
        fail "$message (expected status $expected, got $actual)"
    fi
}

assert_file_exists() {
    local path="$1"
    [[ -e "$path" ]] || fail "expected to exist: $path"
}

assert_file_missing() {
    local path="$1"
    [[ ! -e "$path" ]] || fail "expected to be absent: $path"
}

assert_is_dir() {
    local path="$1"
    [[ -d "$path" ]] || fail "expected a directory: $path"
}

assert_contains() {
    local haystack="$1" needle="$2" message="${3:-substring not found}"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "$message (looked for $(printf '%q' "$needle") in $(printf '%q' "$haystack"))"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" message="${3:-unexpected substring found}"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail "$message (found $(printf '%q' "$needle"))"
    fi
}

new_tmpdir() {
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/caelestia-test.XXXXXX")"
    CAELESTIA_TEST_TMPDIRS+=("$dir")
    printf '%s\n' "$dir"
}

cleanup_tmpdirs() {
    local dir
    for dir in "${CAELESTIA_TEST_TMPDIRS[@]:-}"; do
        [[ -n "$dir" ]] && rm -rf -- "$dir"
    done
    CAELESTIA_TEST_TMPDIRS=()
    return 0
}

stub_bin() {
    local dir="$1" name="$2" body="${3:-exit 0}"
    mkdir -p "$dir"
    printf '#!/bin/bash\n%s\n' "$body" > "$dir/$name"
    chmod +x "$dir/$name"
}

recording_stub() {
    local dir="$1" name="$2" log="$3" status="${4:-0}"
    stub_bin "$dir" "$name" "printf '%s %s\n' '$name' \"\$*\" >> '$log'
exit $status"
}

calls_to() {
    local log="$1" name="$2"
    [[ -f "$log" ]] || return 0
    awk -v want="$name" '$1 == want { sub(/^[^ ]+ /, ""); print }' "$log"
}

run_tests() {
    local fn
    while IFS= read -r fn; do
        CAELESTIA_TEST_COUNT=$((CAELESTIA_TEST_COUNT + 1))
        printf '  %s\n' "$fn"
        "$fn"
    done < <(declare -F | awk '{ print $3 }' | grep '^test_' | sort)

    cleanup_tmpdirs

    if [[ "$CAELESTIA_TEST_FAILURES" -gt 0 ]]; then
        printf '  %s assertion(s) failed across %s test(s)\n' \
            "$CAELESTIA_TEST_FAILURES" "$CAELESTIA_TEST_COUNT" >&2
        return 1
    fi
    printf '  %s test(s) passed\n' "$CAELESTIA_TEST_COUNT"
    return 0
}

fi
