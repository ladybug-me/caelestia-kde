#!/usr/bin/env bash
# suite: isolated
# The update itself belongs to the installer; what is left in shell is the entry point, so this
# covers the hand-off: which binary it finds, what it says to it, and what happens when there is
# no binary to run.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_bundle() {
    local root="$1"
    mkdir -p "$root/scripts/lib"
    cp "$REPO_ROOT/update.sh" "$root/update.sh"
    cp "$REPO_ROOT/scripts/lib/log.sh" "$REPO_ROOT/scripts/lib/installer-bin.sh" \
        "$root/scripts/lib/"
}

# A stand-in for the installer: it records the arguments it was given and the branch it was told
# to follow, and answers with the status it was asked for.
stub_installer() {
    local root="$1" log="$2" status="${3:-0}"
    cat > "$root/caelestia-install" <<EOF
#!/bin/bash
printf 'args=%s branch=%s bundle=%s\n' "\$*" "\${CAELESTIA_UPDATE_BRANCH:-}" "\$BUNDLE_DIR" >> '$log'
exit $status
EOF
    chmod +x "$root/caelestia-install"
}

test_the_entry_point_runs_the_installers_update() {
    local root bin log status line
    root="$(new_tmpdir)"
    bin="$root/bin"
    log="$root/calls.log"
    mkdir -p "$bin"
    make_bundle "$root"
    stub_installer "$root" "$log"
    cp "$root/caelestia-install" "$bin/"

    status="$(
        PATH="$bin:$PATH" bash "$root/update.sh" > "$root/update.log" 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 0 "$status" "an update whose installer succeeds should succeed"

    line="$(cat "$log")"
    assert_contains "$line" "--update" "the installer should be asked to update"
    assert_contains "$line" "--bundle $root" "and told which tree to update"
    assert_contains "$line" "branch= bundle=" "with no branch asked for unless one was given"
}

test_the_entry_point_forwards_the_branch_it_was_given() {
    local root bin log status
    root="$(new_tmpdir)"
    bin="$root/bin"
    log="$root/calls.log"
    mkdir -p "$bin"
    make_bundle "$root"
    stub_installer "$root" "$log"
    cp "$root/caelestia-install" "$bin/"

    PATH="$bin:$PATH" bash "$root/update.sh" dev > "$root/update.log" 2>&1 || true
    assert_contains "$(cat "$log")" "branch=dev" "the branch argument should reach the installer"

    status="$(
        PATH="$bin:$PATH" bash "$root/update.sh" > /dev/null 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 0 "$status" "and an update with no branch should still run"
}

test_a_failed_update_is_reported_as_a_failure() {
    local root bin status
    root="$(new_tmpdir)"
    bin="$root/bin"
    mkdir -p "$bin"
    make_bundle "$root"
    stub_installer "$root" "$root/calls.log" 7
    cp "$root/caelestia-install" "$bin/"

    status="$(
        PATH="$bin:$PATH" bash "$root/update.sh" > "$root/update.log" 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 7 "$status" "the installer's own exit status should be what the caller sees"
}

test_without_a_binary_the_entry_point_says_so() {
    local root status
    root="$(new_tmpdir)"
    mkdir -p "$root/home"
    make_bundle "$root"

    # A PATH with the system's own tools but no installer, a home with none either, and
    # nothing to fetch one with: the resolver has no way to answer.
    status="$(
        HOME="$root/home" PATH="/usr/bin:/bin" CAELESTIA_NO_INSTALLER_FETCH=1 \
            bash "$root/update.sh" > "$root/update.log" 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 1 "$status" "an update with no installer to run should fail"
    assert_contains "$(cat "$root/update.log")" "caelestia-install" \
        "and should name what it could not find"
}

run_tests