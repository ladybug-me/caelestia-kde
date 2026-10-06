#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

RUNNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-tests.sh"

make_case() {
    local dir="$1" name="$2" body="$3"
    mkdir -p "$dir"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$dir/$name"
    chmod +x "$dir/$name"
}

test_runner_reports_missing_named_test() {
    local tmp output status
    tmp="$(new_tmpdir)"
    output="$(bash "$RUNNER" "$tmp/missing.sh" 2>&1)"
    status=$?

    assert_status 1 "$status" "a missing named test should fail the runner"
    assert_contains "$output" "FAIL  missing.sh" "missing tests should be named"
    assert_contains "$output" "Summary:" "missing tests should still produce a summary"
}

test_runner_captures_multiline_failure_artifact() {
    local tmp artifacts output status
    tmp="$(new_tmpdir)"
    artifacts="$tmp/artifacts"
    make_case "$tmp" test_failure.sh 'printf "first line\\nsecond line\\n"; exit 7'

    output="$(bash "$RUNNER" --artifacts "$artifacts" "$tmp/test_failure.sh" 2>&1)"
    status=$?

    assert_status 1 "$status" "a failing test should fail the runner"
    assert_contains "$output" "status 7" "failure output should include the exit status"
    assert_file_exists "$artifacts/test_failure.sh.txt"
    assert_contains "$(cat "$artifacts/test_failure.sh.txt")" "second line" \
        "multiline diagnostics should be preserved in the artifact"
}

test_runner_times_out_a_hanging_test() {
    local tmp output status
    tmp="$(new_tmpdir)"
    make_case "$tmp" test_hanging.sh 'while :; do :; done'

    output="$(bash "$RUNNER" --timeout 1 "$tmp/test_hanging.sh" 2>&1)"
    status=$?

    assert_status 1 "$status" "a timed out test should fail the runner"
    assert_contains "$output" "status 124" "timeout should be reported with the timeout status"
}

test_runner_filters_fast_and_isolated_suites() {
    local tmp output status
    tmp="$(new_tmpdir)"
    make_case "$tmp" test_fast.sh 'exit 0'
    make_case "$tmp" test_isolated_example.sh '# suite: isolated
exit 0'

    output="$(bash "$RUNNER" --suite fast "$tmp/test_fast.sh" "$tmp/test_isolated_example.sh" 2>&1)"
    status=$?

    assert_status 0 "$status" "the fast suite should run matching tests"
    assert_contains "$output" "PASS  [fast] test_fast.sh" "fast tests should run"
    assert_not_contains "$output" "RUN   [isolated]" "isolated tests should be skipped"
    assert_contains "$output" "1 skipped" "suite filtering should report skipped tests"
}

run_tests