#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/shell"

# Qt's default render type is QtRendering, which the Rubik font draws nothing through
# on Qt 6.11.2. The shell therefore makes native the process default and no component
# is allowed to ask for the other one, or the blank labels come back.
test_the_shell_asks_for_native_text_rendering_once() {
    assert_file_contains "$SHELL_ROOT/shell.qml" '//@ pragma NativeTextRendering' \
        "the process default has to be native, or every bare Text item draws with QtRendering"
}

test_no_component_opts_back_into_qt_rendering() {
    local offenders
    offenders="$(grep -rn --include='*.qml' -E 'renderType:[[:space:]]*(Text|TextInput|TextEdit)\.(QtRendering|CurveRendering)' "$SHELL_ROOT" || true)"

    assert_eq "" "$offenders" \
        "no shell text may ask for QtRendering: it draws nothing with Rubik, and it is not a per-site choice"
}

run_tests
