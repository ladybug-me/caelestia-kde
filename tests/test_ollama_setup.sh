#!/usr/bin/env bash
# suite: fast
#
# Ollama's installer is fetched from a URL that never changes while its content does, so it
# cannot be pinned in this repository without breaking on the next upstream release. What
# the script owes the run instead is that a transferred script is the one that executes,
# that the installer this machine accepted first is the one later runs are measured
# against, and that a change is a decision someone makes rather than something that
# happens to root while nobody is looking. Every command the script would reach outside
# its own files is stubbed, so those decisions are what these tests exercise.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/shell/scripts/ollama_setup.sh"
BASH_BIN="$(command -v bash)"

FIRST_INSTALLER='exit 0'
CHANGED_INSTALLER='exit 0 # a later upstream release'

# The transfer writes whatever STUB_BODY says, so a test can stand in for a different
# upstream release without touching the script under test.
stub_environment() {
    local tmp="$1"
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/curl" <<'STUB'
#!/bin/sh
dest=""
prev=""
for arg in "$@"; do
    [ "$prev" = "-o" ] && dest="$arg"
    prev="$arg"
done
[ -n "$dest" ] || exit 22
printf '%s\n' "${STUB_BODY:-exit 0}" > "$dest"
STUB
    cat > "$tmp/bin/sudo" <<'STUB'
#!/bin/sh
exec "$@"
STUB
    cat > "$tmp/bin/systemctl" <<'STUB'
#!/bin/sh
exit 0
STUB
    chmod +x "$tmp/bin/curl" "$tmp/bin/sudo" "$tmp/bin/systemctl"
}

hash_of() {
    printf '%s\n' "$1" | sha256sum | cut -d' ' -f1
}

# Runs the installer with the stub on PATH and the accepted installer recorded inside the
# temporary tree, so nothing is written outside it.
run_install() {
    local tmp="$1"
    shift
    ( PATH="$tmp/bin:/usr/bin:/bin" CAELESTIA_OLLAMA_PIN_FILE="$tmp/pin.sha256" \
        bash "$SETUP_SCRIPT" "$@" )
}

test_the_first_run_records_the_installer_it_ran() {
    local tmp out status expected
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"
    expected="$(hash_of "$FIRST_INSTALLER")"

    out="$(STUB_BODY="$FIRST_INSTALLER" run_install "$tmp" --no-models 2>&1)"
    status=$?

    assert_status 0 "$status" "a first install has nothing to compare against and has to run"
    assert_contains "$out" "Recorded the Ollama installer's SHA-256" \
        "so the machine remembers which installer it accepted"
    assert_eq "$expected" "$(cat "$tmp/pin.sha256")" "the record is the hash of what ran"
}

test_the_same_installer_runs_again_without_a_word() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"
    printf '%s\n' "$(hash_of "$FIRST_INSTALLER")" > "$tmp/pin.sha256"

    out="$(STUB_BODY="$FIRST_INSTALLER" run_install "$tmp" --no-models 2>&1)"
    status=$?

    assert_status 0 "$status" "an unchanged installer is the ordinary case"
    assert_not_contains "$out" "Refusing" "and must not be reported as a problem"
}

test_a_changed_installer_is_refused_with_both_hashes() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"
    printf '%s\n' "$(hash_of "$FIRST_INSTALLER")" > "$tmp/pin.sha256"

    out="$(STUB_BODY="$CHANGED_INSTALLER" run_install "$tmp" --no-models 2>&1)"
    status=$?

    assert_status 1 "$status" \
        "a different installer is exactly what an upstream release and a tampered one both look like"
    assert_contains "$out" "Refusing to run Ollama's installer as root" "which the run has to say"
    assert_contains "$out" "$(hash_of "$FIRST_INSTALLER")" "naming what it accepted before"
    assert_contains "$out" "$(hash_of "$CHANGED_INSTALLER")" "and what arrived this time"
    assert_contains "$out" "--accept-new-installer" "with the way to accept it deliberately"
    assert_eq "$(hash_of "$FIRST_INSTALLER")" "$(cat "$tmp/pin.sha256")" \
        "a refused installer must not be recorded as accepted"
}

test_accepting_the_new_installer_updates_the_record() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"
    printf '%s\n' "$(hash_of "$FIRST_INSTALLER")" > "$tmp/pin.sha256"

    out="$(STUB_BODY="$CHANGED_INSTALLER" run_install "$tmp" --no-models --accept-new-installer 2>&1)"
    status=$?

    assert_status 0 "$status" "the flag is how a person says the change is expected"
    assert_contains "$out" "changed upstream" "which the log should record"
    assert_eq "$(hash_of "$CHANGED_INSTALLER")" "$(cat "$tmp/pin.sha256")" \
        "and the next run compares against the one that just ran"
}

test_a_pinned_installer_that_does_not_match_fails_the_install() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"

    out="$(OLLAMA_INSTALL_SHA256="$(hash_of 'something else')" \
        STUB_BODY="$FIRST_INSTALLER" run_install "$tmp" --no-models 2>&1)"
    status=$?

    assert_status 1 "$status" "an explicit pin outranks the record and has to stop the install"
    assert_contains "$out" "checksum mismatch" "and the reason has to be stated"
    assert_contains "$out" "$(hash_of "$FIRST_INSTALLER")" "naming what arrived"
}

test_the_unverified_download_opt_in_is_honoured() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"
    printf '%s\n' "$(hash_of "$FIRST_INSTALLER")" > "$tmp/pin.sha256"

    out="$(CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1 STUB_BODY="$CHANGED_INSTALLER" \
        run_install "$tmp" --no-models 2>&1)"
    status=$?

    assert_status 0 "$status" "the documented opt-in lets an unexpected installer run"
    assert_contains "$out" "CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1 is set" "and says that it did"
    assert_contains "$out" "$(hash_of "$CHANGED_INSTALLER")" "with the hash of the script it ran"
}

test_status_reports_without_downloading_anything() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp"

    out="$( ( PATH="$tmp/bin" "$BASH_BIN" "$SETUP_SCRIPT" --status ) 2>&1)"
    status=$?

    assert_status 0 "$status" "--status must not need privileges or the network"
    assert_contains "$out" "VERSION=NOT_INSTALLED" "and reports what is there"
}

run_tests
