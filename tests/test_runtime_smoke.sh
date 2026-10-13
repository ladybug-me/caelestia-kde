#!/usr/bin/env bash
# Drive tests/runtime-smoke.sh against a stubbed runtime.
#
# The smoke script normally needs Weston, Quickshell and a real install tree.
# Here the three commands it shells out to are stubbed, so its own logic -
# argument handling, marker assertions, limit gating, the results document and
# cleanup - runs for real on a machine without a compositor.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="$REPO_ROOT/tests/runtime-smoke.sh"
BASELINE="$REPO_ROOT/.github/ci-baselines/runtime-smoke.json"
MARKS="$REPO_ROOT/tests/runtime-smoke-marks.txt"

setup_env() {
    DIR="$(new_tmpdir)"
    BIN="$DIR/bin"
    INSTALL_ROOT="$DIR/install"
    mkdir -p "$INSTALL_ROOT/etc/xdg/quickshell/caelestia" \
        "$INSTALL_ROOT/usr/lib/qt6/qml" "$INSTALL_ROOT/usr/lib/caelestia"
    : >"$INSTALL_ROOT/etc/xdg/quickshell/caelestia/shell.qml"

    stub_bin "$BIN" quickshell 'exit 0'
    stub_bin "$BIN" ps 'printf " %s\n" "${CAELESTIA_STUB_CPU:-0.5}"'
    stub_bin "$BIN" dbus-run-session 'trap "exit 0" TERM
cat "$CAELESTIA_STUB_LOG"
while :; do sleep 1; done'

    # A real AF_UNIX socket, because the script waits for one before starting.
    cat >"$BIN/weston" <<'PY'
#!/usr/bin/env python3
import os
import socket
import time

server = socket.socket(socket.AF_UNIX)
server.bind(os.path.join(os.environ["XDG_RUNTIME_DIR"], "wayland-runtime"))
server.listen(1)
time.sleep(60)
PY
    chmod +x "$BIN/weston"

    write_full_log
}

# A log that satisfies every requirement, derived from the same declaration the
# smoke script asserts against - so a new marker does not need a matching edit
# here for the suite to keep testing the script's own logic.
write_full_log() {
    local minimum marker i
    : >"$DIR/markers.log"
    while IFS='|' read -r minimum marker; do
        if [[ -z "$minimum" || "$minimum" == \#* ]]; then
            continue
        fi
        for ((i = 0; i < minimum; i++)); do
            printf '%s\n' "$marker" >>"$DIR/markers.log"
        done
    done <"$MARKS"
}

# run_smoke <case> <cpu> [script args...]
run_smoke() {
    local case="$1" cpu="$2"
    shift 2
    CAELESTIA_STUB_LOG="$DIR/markers.log" CAELESTIA_STUB_CPU="$cpu" \
        PATH="$BIN:$PATH" bash "$SMOKE" --install-root "$INSTALL_ROOT" \
        --runs 1 --timeout 20 --log-dir "$DIR/logs-$case" "$@" \
        >"$DIR/$case.json" 2>"$DIR/$case.err"
    LAST_STATUS=$?
    LAST_OUT="$DIR/$case.json"
    LAST_ERR="$DIR/$case.err"
}

test_a_clean_run_reports_a_cold_and_then_a_warm_cycle() {
    setup_env
    CAELESTIA_STUB_LOG="$DIR/markers.log" CAELESTIA_STUB_CPU=0.5 \
        PATH="$BIN:$PATH" bash "$SMOKE" --install-root "$INSTALL_ROOT" \
        --runs 2 --timeout 20 --baseline "$BASELINE" --log-dir "$DIR/logs-happy" \
        >"$DIR/happy.json" 2>"$DIR/happy.err"
    assert_status 0 "$?" "a clean run should pass"

    python3 - "$DIR/happy.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
cycles = document["results"]
assert document["runs"] == 2, document
assert [cycle["scenario"] for cycle in cycles] == ["cold", "warm"], cycles
assert all(isinstance(cycle["startup_ms"], int) for cycle in cycles), cycles
assert all(isinstance(cycle["rss_kb"], int) for cycle in cycles), cycles
PY
    assert_status 0 "$?" "the results document should be valid JSON with both scenarios"
    assert_file_exists "$DIR/logs-happy/weston.log"
}

test_an_unset_limit_only_reports_the_measurement() {
    setup_env
    # The committed baseline has no max_idle_cpu_percent, so a high idle reading
    # must not fail the run - it is reported, not gated.
    run_smoke idle-report 42.0 --baseline "$BASELINE"
    assert_status 0 "$LAST_STATUS" "an unset idle CPU limit should not fail the run"
    assert_contains "$(cat "$LAST_OUT")" '"idle_cpu_percent": 42.0' \
        "the idle reading should still be reported"
}

test_an_explicit_limit_fails_the_run() {
    setup_env
    run_smoke idle-gate 42.0 --max-idle-cpu 10
    assert_status 1 "$LAST_STATUS" "an idle CPU limit of 10 with a reading of 42 should fail"
    assert_contains "$(cat "$LAST_ERR")" "exceeded idle CPU limit" \
        "the failure should name the limit that was exceeded"
}

test_a_missing_marker_fails_the_run_and_keeps_the_report() {
    setup_env
    grep -v '\[caelestia\] wallpaper-ready' "$DIR/markers.log" >"$DIR/markers.tmp"
    mv "$DIR/markers.tmp" "$DIR/markers.log"

    run_smoke missing-marker 0.5 --baseline "$BASELINE"

    assert_status 1 "$LAST_STATUS" "a missing readiness marker should fail the run"
    assert_contains "$(cat "$LAST_ERR")" "wallpaper-ready" \
        "the failure should name the missing marker"
    # A partial run still has to leave a parseable document behind, or the
    # uploaded diagnostics cannot be read back.
    python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$LAST_OUT"
    assert_status 0 "$?" "an interrupted run should still emit valid JSON"
}

test_a_created_window_must_also_be_destroyed() {
    setup_env
    # Every marker count is satisfied here; only the created/destroyed balance
    # can catch this.
    printf '[caelestia] nexus=created\n' >>"$DIR/markers.log"

    run_smoke unbalanced 0.5 --baseline "$BASELINE"

    assert_status 1 "$LAST_STATUS" "a window left un-destroyed should fail the run"
    assert_contains "$(cat "$LAST_ERR")" "but destroyed" \
        "the failure should report the created/destroyed counts"
}

test_a_missing_install_root_is_rejected() {
    setup_env
    run_smoke no-install 0.5 --install-root "$DIR/absent"
    assert_status 2 "$LAST_STATUS" "a missing install root should be rejected"
}

run_tests
