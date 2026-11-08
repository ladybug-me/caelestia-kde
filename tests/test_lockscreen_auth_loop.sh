#!/usr/bin/env bash

# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$REPO_ROOT/tests/qml/lockscreen_auth/run.py"

have_harness_runtime() {
    if ! command -v python3 >/dev/null 2>&1; then
        skip_test "python3 not installed"
        return 1
    fi
    if ! QT_QPA_PLATFORM=offscreen python3 - "$HARNESS" >/dev/null 2>&1 <<'PY'
import sys

try:
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlEngine  # noqa: F401
except ImportError:
    sys.exit(1)
QGuiApplication([])
PY
    then
        skip_test "PySide6 with a Qt platform plugin is not available"
        return 1
    fi
    return 0
}

# expect_harness <message> <scenario...>: the harness owns the verdict, so the shell only
# reports it. Its output is quoted when a scenario fails.
expect_harness() {
    local message="$1" out status
    shift

    out="$(QT_QPA_PLATFORM=offscreen TMPDIR="${TMPDIR:-/tmp}" python3 "$HARNESS" "$@" 2>&1)"
    status=$?
    assert_status 0 "$status" "$message"
    [[ $status -eq 0 ]] || fail_with_output "$message" "$out"
}

# The greeter used to call startAuthenticating() again on a prompt that was already
# waiting, which kscreenlocker answers with an immediate failure: the pill shakes, grace
# locks and the loop starts. An untouched lock screen must stay quiet.
test_an_idle_lock_screen_does_not_restart_the_prompt() {
    have_harness_runtime || return 0
    expect_harness "an idle lock screen must not restart a pending authentication" A
}

# LockScreenUi calls ensureAuthenticating() on every key press, so the act of typing
# the password must not disturb the prompt that is waiting for it.
test_typing_does_not_restart_the_prompt() {
    have_harness_runtime || return 0
    expect_harness "typing the password must not restart a pending authentication" F
}

# The happy paths the previous guard already handled: the first attempt, and a retry
# after a mistyped password.
test_the_correct_password_unlocks() {
    have_harness_runtime || return 0
    expect_harness "the correct password must unlock on the first attempt and after a typo" B C
}

# A failed fingerprint scan runs beside the password prompt rather than ending it, so it
# must leave the prompt -- and the password the user is typing -- alone.
test_a_failed_scan_does_not_discard_the_prompt() {
    have_harness_runtime || return 0
    expect_harness "a failed scan must not discard a waiting password prompt" G
}

# kscreenlocker announces an authenticator reset by firing the prompt signals with no
# prompt behind them; the greeter still has to start its first conversation afterwards.
test_a_prompt_less_prompt_change_still_allows_authenticating() {
    have_harness_runtime || return 0
    expect_harness "an empty prompt change must not block authentication" H
}

# PAM can ask its question echo-on; the pill answers it with the same field, so that
# prompt has to hold the guard as well.
test_an_echo_on_prompt_holds_the_guard() {
    have_harness_runtime || return 0
    expect_harness "an echo-on prompt must not be restarted either" I
}

run_tests
