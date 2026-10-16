#!/usr/bin/env bash
# suite: isolated
# The uninstall itself belongs to the installer; what is left in shell is the entry point, so
# this covers the hand-off: which binary it finds, what it says to it, and what happens when
# there is no binary to run.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_bundle() {
    local root="$1"
    mkdir -p "$root/scripts/lib"
    cp "$REPO_ROOT/uninstall.sh" "$root/uninstall.sh"
    cp "$REPO_ROOT/scripts/lib/log.sh" "$REPO_ROOT/scripts/lib/installer-bin.sh" \
        "$root/scripts/lib/"
}

stub_installer() {
    local root="$1" log="$2" status="${3:-0}"
    cat > "$root/caelestia-install" <<EOF
#!/bin/bash
printf 'args=%s bundle=%s\n' "\$*" "\$BUNDLE_DIR" >> '$log'
exit $status
EOF
    chmod +x "$root/caelestia-install"
}

test_the_entry_point_runs_the_installers_uninstall() {
    local root bin log status line
    root="$(new_tmpdir)"
    bin="$root/bin"
    log="$root/calls.log"
    mkdir -p "$bin"
    make_bundle "$root"
    stub_installer "$root" "$log"
    cp "$root/caelestia-install" "$bin/"

    status="$(
        PATH="$bin:$PATH" bash "$root/uninstall.sh" > "$root/uninstall.log" 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 0 "$status" "an uninstall whose installer succeeds should succeed"

    line="$(cat "$log")"
    assert_contains "$line" "--uninstall" "the installer should be asked to uninstall"
    assert_contains "$line" "--bundle $root" "and told which tree it belongs to"
}

test_a_failed_uninstall_is_reported_as_a_failure() {
    local root bin status
    root="$(new_tmpdir)"
    bin="$root/bin"
    mkdir -p "$bin"
    make_bundle "$root"
    stub_installer "$root" "$root/calls.log" 3
    cp "$root/caelestia-install" "$bin/"

    status="$(
        PATH="$bin:$PATH" bash "$root/uninstall.sh" > "$root/uninstall.log" 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 3 "$status" "the installer's own exit status should be what the caller sees"
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
            bash "$root/uninstall.sh" > "$root/uninstall.log" 2>&1
        printf '%s\n' "$?"
    )"
    assert_status 1 "$status" "an uninstall with no installer to run should fail"
    assert_contains "$(cat "$root/uninstall.log")" "caelestia-install" \
        "and should name what it could not find"
}

run_tests