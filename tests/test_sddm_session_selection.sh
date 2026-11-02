#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML_TESTS="$REPO_ROOT/src/sddm/tests"

find_qmltestrunner() {
    local candidate resolved target
    for candidate in qmltestrunner6 /usr/lib/qt6/bin/qmltestrunner qmltestrunner; do
        resolved="$(command -v "$candidate" 2>/dev/null)" || continue
        # Debian and Ubuntu install a qtchooser shim that fails to exec when the
        # Qt 5 tools are not installed.
        target="$(readlink -f "$resolved" 2>/dev/null || printf '%s' "$resolved")"
        [[ "$(basename "$target")" == "qtchooser" ]] && continue
        printf '%s\n' "$resolved"
        return 0
    done
    return 1
}

test_session_picker_honors_the_saved_session() {
    local runner
    if ! runner="$(find_qmltestrunner)"; then
        skip_test "qmltestrunner is not installed"
        return 0
    fi

    local output status
    output="$(QT_QPA_PLATFORM=offscreen "$runner" -input "$QML_TESTS" 2>&1)"
    status=$?

    if [[ $status -ne 0 ]]; then
        fail_with_output "the session picker QML tests failed" "$output"
    fi
}

run_tests
