#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/privileges.sh"

reset_sudo_state() {
    caelestia_stop_sudo_keepalive
    unset CAELESTIA_SUDO_KEEPALIVE_PID CAELESTIA_SUDO_PRIMED SUDO_ASKPASS CAELESTIA_SUDO_BIN
}

require_unprivileged_user() {
    if [[ "$EUID" -eq 0 ]]; then
        skip_test "the escalation paths only exist below root"
        return 1
    fi
    return 0
}

sudo_stub() {
    local dir="$1" credential="$2" log="$3"
    stub_bin "$dir" sudo "
printf 'sudo %s\n' \"\$*\" >> '$log'
if [ \"\$1\" = -n ] && [ \"\$2\" = true ] && [ \"$credential\" = none ]; then
    exit 1
fi
exit 0"
    printf '%s\n' "$dir/sudo"
}

askpass_file() {
    stub_bin "$1" askpass 'printf "secret\n"'
    printf '%s\n' "$1/askpass"
}

test_a_cached_credential_is_used_without_prompting() {
    require_unprivileged_user || return 0

    local tmp log method
    reset_sudo_state
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    CAELESTIA_SUDO_BIN="$(sudo_stub "$tmp/bin" present "$log")"

    method="$(caelestia_sudo_method)"
    assert_eq "cached" "$method" "a working credential should be the method chosen"

    caelestia_sudo marked-command
    assert_contains "$(calls_to "$log" sudo)" "-n marked-command" \
        "the command should run with the cached credential"
}

test_the_askpass_helper_is_used_when_nothing_is_cached() {
    require_unprivileged_user || return 0

    local tmp log method
    reset_sudo_state
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    CAELESTIA_SUDO_BIN="$(sudo_stub "$tmp/bin" none "$log")"
    export SUDO_ASKPASS="$(askpass_file "$tmp/bin")"

    method="$(caelestia_sudo_method)"
    assert_eq "askpass" "$method" "the helper should be preferred over prompting"

    caelestia_sudo marked-command
    assert_contains "$(calls_to "$log" sudo)" "-A marked-command" \
        "the command should run through the askpass helper"
    reset_sudo_state
}

test_a_quiet_call_refuses_instead_of_prompting() {
    require_unprivileged_user || return 0

    local tmp log status
    reset_sudo_state
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    CAELESTIA_SUDO_BIN="$(sudo_stub "$tmp/bin" none "$log")"

    caelestia_sudo_quiet marked-command
    status=$?

    assert_status 1 "$status" "a quiet call must fail rather than ask for anything"
    assert_not_contains "$(calls_to "$log" sudo)" "marked-command" "the command must not run"
}

test_a_quiet_call_still_uses_the_askpass_helper() {
    require_unprivileged_user || return 0

    local tmp log status
    reset_sudo_state
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    CAELESTIA_SUDO_BIN="$(sudo_stub "$tmp/bin" none "$log")"
    export SUDO_ASKPASS="$(askpass_file "$tmp/bin")"

    caelestia_sudo_quiet marked-command
    status=$?

    assert_status 0 "$status" "the helper needs no prompting, so a quiet call may use it"
    assert_contains "$(calls_to "$log" sudo)" "-A marked-command" "the helper should run the command"
    reset_sudo_state
}

test_priming_uses_the_askpass_helper() {
    require_unprivileged_user || return 0

    local tmp log status
    reset_sudo_state
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    CAELESTIA_SUDO_BIN="$(sudo_stub "$tmp/bin" none "$log")"
    export SUDO_ASKPASS="$(askpass_file "$tmp/bin")"

    caelestia_prime_sudo
    status=$?

    assert_status 0 "$status" "priming should succeed through the helper"
    assert_contains "$(calls_to "$log" sudo)" "-A -v" "the credential should be refreshed through the helper"
    assert_eq "1" "${CAELESTIA_SUDO_PRIMED:-}" "priming should be remembered"
    reset_sudo_state
}

nopasswd_sudo_stub() {
    local dir="$1" log="$2"
    stub_bin "$dir" sudo "
printf 'sudo %s\n' \"\$*\" >> '$log'
for arg in \"\$@\"; do
    if [ \"\$arg\" = -v ]; then
        printf 'sudo: a password is required\n' >&2
        exit 1
    fi
done
exit 0"
    printf '%s\n' "$dir/sudo"
}

test_a_nopasswd_account_primes_without_a_password() {
    require_unprivileged_user || return 0

    local tmp log status
    reset_sudo_state
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    CAELESTIA_SUDO_BIN="$(nopasswd_sudo_stub "$tmp/bin" "$log")"

    caelestia_prime_sudo
    status=$?

    assert_status 0 "$status" "a NOPASSWD account needs no prompt, so priming must succeed"
    assert_eq "1" "${CAELESTIA_SUDO_PRIMED:-}" "priming should be remembered"
    reset_sudo_state
}

run_tests
