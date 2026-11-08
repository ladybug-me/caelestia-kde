#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/shell/scripts/quickshare_setup.sh"
PORT_FILE="$REPO_ROOT/shell/scripts/quickshare-port"
SERVICE_CPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/QuickShare/quickshare_service.cpp"
PLUGIN_CMAKE="$REPO_ROOT/shell/plugin/CMakeLists.txt"
QUICKSHARE_CMAKE="$REPO_ROOT/shell/plugin/src/Caelestia/Services/QuickShare/CMakeLists.txt"
SERVICES_STEP="$REPO_ROOT/scripts/06-services.sh"
QS_SETUP_QML="$REPO_ROOT/shell/services/QuickShareSetup.qml"

if [[ ! -f "$PORT_FILE" ]]; then
    printf '  cannot check the transfer port without %s\n' "$PORT_FILE" >&2
    exit 1
fi

PORT="$(<"$PORT_FILE")"

test_the_transfer_port_has_one_definition() {
    [[ "$PORT" =~ ^[0-9]+$ ]] || fail "the transfer port manifest must hold one port number, not '$PORT'"

    assert_contains "$(cat "$PLUGIN_CMAKE")" "scripts/quickshare-port" \
        "the plugin build should read the port from the manifest"
    assert_contains "$(cat "$QUICKSHARE_CMAKE")" 'CAELESTIA_QUICKSHARE_PORT=${QUICKSHARE_PORT}' \
        "and bake it into the module that binds it"

    local restated
    restated="$(grep -n "$PORT" "$SERVICE_CPP" "$SERVICES_STEP" || true)"
    assert_eq "" "$restated" "the service and the install step should read the manifest, not restate it"
}

test_the_setup_helper_is_told_the_port_the_service_owns() {
    assert_contains "$(cat "$QS_SETUP_QML")" 'String(QuickShareService.listenPort)' \
        "the helper takes the port as an argument rather than keeping a copy of it"
}

STUB_TOOLS=(bash grep sleep)

stub_environment() {
    local dir="$1" tool
    mkdir -p "$dir"
    for tool in "${STUB_TOOLS[@]}"; do
        ln -sf "$(command -v "$tool")" "$dir/$tool"
    done
}

report_with() {
    local dir="$1"
    shift
    env PATH="$dir" "$@" bash "$SETUP_SCRIPT" --status --port "$PORT"
}

avahi_installed_and_running() {
    stub_bin "$1" avahi-daemon 'exit 0'
    stub_bin "$1" systemctl 'exit 0'
}

test_a_machine_with_no_avahi_and_no_firewall_needs_setup() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"

    out="$(report_with "$tmp/bin")"
    assert_contains "$out" "AVAHI=absent" "a machine without the daemon reports it absent"
    assert_contains "$out" "FIREWALL=none" "and reports no firewall manager"
    assert_contains "$out" "PORT=allowed" "with nothing left that could block the port"
    assert_contains "$out" "SETUP=needed" "so the shell should offer to prepare the system"
}

test_a_stopped_avahi_daemon_needs_setup() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"
    stub_bin "$tmp/bin" avahi-daemon 'exit 0'
    stub_bin "$tmp/bin" avahi-daemon 'exit 0'
    stub_bin "$tmp/bin" systemctl 'exit 1'

    out="$(report_with "$tmp/bin")"
    assert_contains "$out" "AVAHI=inactive" "a daemon that is not running is reported as inactive"
    assert_contains "$out" "SETUP=needed" "and the daemon is what the shell should offer to start"
}

test_a_running_firewalld_that_blocks_the_port_needs_setup() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"
    avahi_installed_and_running "$tmp/bin"
    stub_bin "$tmp/bin" firewall-cmd 'for arg in "$@"; do case "$arg" in --query-port=*) echo no; exit 1 ;; esac; done
exit 0'

    out="$(report_with "$tmp/bin")"
    assert_contains "$out" "FIREWALL=firewalld" "a running firewalld is the manager in charge"
    assert_contains "$out" "PORT=blocked" "and its answer for the port is read"
    assert_contains "$out" "SETUP=needed" "a blocked port is what the shell should offer to open"
}

test_a_running_firewalld_that_allows_the_port_is_ready() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"
    avahi_installed_and_running "$tmp/bin"
    stub_bin "$tmp/bin" firewall-cmd 'echo yes
exit 0'

    out="$(report_with "$tmp/bin")"
    assert_contains "$out" "PORT=allowed" "firewalld's answer is honoured"
    assert_contains "$out" "SETUP=ok" "an open port needs no setup"
}

test_a_running_avahi_daemon_without_a_firewall_is_ready() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"
    avahi_installed_and_running "$tmp/bin"

    out="$(report_with "$tmp/bin")"
    assert_contains "$out" "FIREWALL=none" "firewalld is not running, so nothing is in charge"
    assert_contains "$out" "SETUP=ok" "there is nothing left to do"
}

test_ufw_leaves_the_port_unverified_rather_than_guessed() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"
    avahi_installed_and_running "$tmp/bin"
    stub_bin "$tmp/bin" ufw 'exit 0'

    out="$(report_with "$tmp/bin")"
    assert_contains "$out" "FIREWALL=ufw" "ufw that is enabled is the manager in charge"
    assert_contains "$out" "PORT=unknown" "reading a ufw rule set needs root, so it is not claimed"
    assert_contains "$out" "SETUP=unknown" "and the shell stays quiet instead of guessing"
}

test_the_status_report_insists_on_a_port() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"

    out="$(env PATH="$tmp/bin" bash "$SETUP_SCRIPT" --status 2>&1)"
    status=$?

    assert_status 2 "$status" "a port is required to answer anything about it"
    assert_contains "$out" "--port is required" "and the refusal should say so"
}

test_a_port_outside_the_tcp_range_is_refused() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"

    out="$(env PATH="$tmp/bin" bash "$SETUP_SCRIPT" --status --port 70000 2>&1)"
    status=$?

    assert_status 2 "$status" "70000 is not a TCP port"
    assert_contains "$out" "between 1 and 65535" "and the refusal should say why"
}

test_the_setup_half_refuses_to_run_unprivileged() {
    if [[ "$EUID" -eq 0 ]]; then
        skip_test "running as root, where the refusal cannot be observed"
        return
    fi

    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"

    out="$(env PATH="$tmp/bin" bash "$SETUP_SCRIPT" --port "$PORT" 2>&1)"
    status=$?

    assert_status 1 "$status" "opening the firewall is not a user-level action"
    assert_contains "$out" "needs root" "and the refusal should say what is missing"
}

SETUP_FUNCTIONS="$(extract_function "$SETUP_SCRIPT" avahi_state
extract_function "$SETUP_SCRIPT" firewalld_in_charge
extract_function "$SETUP_SCRIPT" ufw_in_charge
extract_function "$SETUP_SCRIPT" firewall_backend
extract_function "$SETUP_SCRIPT" enable_avahi
extract_function "$SETUP_SCRIPT" open_firewall)"

if [[ -z "$SETUP_FUNCTIONS" ]]; then
    fail "could not extract the setup functions from shell/scripts/quickshare_setup.sh"
fi

call_setup_function() {
    local dir="$1" call="$2"
    shift 2
    env PATH="$dir" "$@" bash -c "$SETUP_FUNCTIONS
$call" 2>&1
}

test_starting_avahi_enables_the_unit() {
    local tmp log out status
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    stub_environment "$tmp/bin"
    stub_bin "$tmp/bin" avahi-daemon 'exit 0'

    cat > "$tmp/bin/systemctl" <<EOS
#!/bin/bash
printf 'systemctl %s\n' "\$*" >> "$log"
if [[ "\$1" == "is-active" ]]; then
    [[ -f "$tmp/avahi-up" ]]
    exit \$?
fi
[[ "\$*" == *"avahi-daemon.service"* ]] && : > "$tmp/avahi-up"
exit 0
EOS
    chmod +x "$tmp/bin/systemctl"

    out="$(call_setup_function "$tmp/bin" 'enable_avahi')"
    status=$?

    assert_status 0 "$status" "starting a stopped daemon should succeed"
    assert_contains "$(calls_to "$log" systemctl)" "enable --now avahi-daemon.service" \
        "the daemon must be enabled, not merely started once"
    assert_contains "$out" "Enabling and starting avahi-daemon" "and the progress should be reported"
}

test_starting_avahi_stops_when_the_package_is_missing() {
    local tmp out status
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"
    stub_bin "$tmp/bin" systemctl 'exit 0'

    out="$(call_setup_function "$tmp/bin" 'enable_avahi')"
    status=$?

    assert_status 1 "$status" "there is no daemon to start"
    assert_contains "$out" "avahi package is not installed" "and the reason should name the package"
}

test_opening_the_firewall_adds_the_port_and_mdns_to_firewalld() {
    local tmp log status
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    stub_environment "$tmp/bin"
    stub_bin "$tmp/bin" systemctl 'exit 0'
    recording_stub "$tmp/bin" firewall-cmd "$log"

    call_setup_function "$tmp/bin" "open_firewall $PORT" >/dev/null
    status=$?

    local calls
    calls="$(calls_to "$log" firewall-cmd)"
    assert_status 0 "$status" "firewalld should accept the rules"
    assert_contains "$calls" "--permanent --add-port=$PORT/tcp" "the transfer port has to survive a reload"
    assert_contains "$calls" "--permanent --add-service=mdns" "and discovery needs its multicast traffic let through"
    assert_contains "$calls" "--reload" "which is what applies the permanent rules"
}

test_opening_the_firewall_goes_through_ufw_when_that_is_what_runs() {
    local tmp log status
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    stub_environment "$tmp/bin"
    stub_bin "$tmp/bin" systemctl 'exit 0'
    recording_stub "$tmp/bin" ufw "$log"

    call_setup_function "$tmp/bin" "open_firewall $PORT" >/dev/null
    status=$?

    local calls
    calls="$(calls_to "$log" ufw)"
    assert_status 0 "$status" "ufw should accept the rules"
    assert_contains "$calls" "allow $PORT/tcp" "the transfer port has to be let through"
    assert_contains "$calls" "allow 5353/udp" "and so does discovery"
}

test_opening_the_firewall_does_nothing_when_no_manager_is_running() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_environment "$tmp/bin"

    out="$(call_setup_function "$tmp/bin" "open_firewall $PORT")"

    assert_contains "$out" "No active firewalld or ufw found" \
        "a hand-rolled rule set is invisible, so nothing is changed and that is said"
}

SERVICES_SOURCE="$(extract_function "$SERVICES_STEP" configure_quick_share)"

if [[ -z "$SERVICES_SOURCE" ]]; then
    fail "could not find configure_quick_share in scripts/06-services.sh"
fi

stub_bundle_reporting() {
    local dir="$1" setup="$2"
    mkdir -p "$dir/shell/scripts"
    cat > "$dir/shell/scripts/quickshare_setup.sh" <<EOS
#!/bin/bash
printf 'AVAHI=active\nFIREWALL=none\nPORT=allowed\nSETUP=$setup\n'
EOS
    cp "$PORT_FILE" "$dir/shell/scripts/quickshare-port"
    printf '%s\n' "$dir"
}

run_configure_quick_share() {
    local bundle="$1" packaged_status="$2" log="${3:-/dev/null}" sudo_status="${4:-0}"
    env BUNDLE_DIR="$bundle" CONFIGURE_LOG="$log" PACKAGED="$packaged_status" SUDO_STATUS="$sudo_status" \
        INSTALL_FS="$REPO_ROOT/scripts/lib/install-fs.sh" \
        bash -c 'source "$INSTALL_FS"
install_is_packaged() { return "$PACKAGED"; }
skip() { printf "SKIP %s\n" "$*"; }
warn() { printf "WARN %s\n" "$*"; }
ok() { printf "OK %s\n" "$*"; }
caelestia_sudo() { printf "ESCALATE %s\n" "$*" >> "$CONFIGURE_LOG"; return "$SUDO_STATUS"; }
'"$SERVICES_SOURCE"'
configure_quick_share'
}

test_a_packaged_install_leaves_quick_share_to_the_package() {
    local tmp out
    tmp="$(new_tmpdir)"

    out="$(run_configure_quick_share "$(stub_bundle_reporting "$tmp/bundle" ok)" 0 2>&1)"

    assert_contains "$out" "packaged install" "a package install gets no root-level changes from the installer"
    assert_not_contains "$out" "ESCALATE" "so the installer must leave it alone"
}

test_a_missing_helper_warns_without_stopping_the_install() {
    local tmp out
    tmp="$(new_tmpdir)"

    out="$(run_configure_quick_share "$tmp/absent" 1 2>&1)"

    assert_contains "$out" "setup helper is missing" "the step should say what it could not find"
    assert_not_contains "$out" "ESCALATE" "and nothing should be elevated for it"
}

test_a_bundle_without_the_transfer_port_warns_without_raising() {
    local tmp dir out
    tmp="$(new_tmpdir)"
    dir="$tmp/bundle"
    mkdir -p "$dir/shell/scripts"
    stub_bin "$dir/shell/scripts" quickshare_setup.sh 'printf "SETUP=needed\n"'

    out="$(run_configure_quick_share "$dir" 1 2>&1)"

    assert_contains "$out" "transfer port is missing" "the step should say what it could not read"
    assert_not_contains "$out" "ESCALATE" "and nothing should be elevated for it"
}

test_a_bundle_whose_transfer_port_is_not_a_number_warns_without_raising() {
    local tmp dir out
    tmp="$(new_tmpdir)"
    dir="$(stub_bundle_reporting "$tmp/bundle" needed)"
    printf 'not-a-port\n' > "$dir/shell/scripts/quickshare-port"

    out="$(run_configure_quick_share "$dir" 1 2>&1)"

    assert_contains "$out" "is not a port number" "a port the firewall cannot be asked for is worth saying"
    assert_not_contains "$out" "ESCALATE" "and nothing should be elevated for it"
}

test_a_system_that_already_works_is_not_raised_for() {
    local tmp log out
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"

    out="$(run_configure_quick_share "$(stub_bundle_reporting "$tmp/bundle" ok)" 1 "$log" 2>&1)"

    assert_contains "$out" "already has the access it needs" "the status check is what decides"
    assert_not_contains "$out" "ESCALATE" "an install that needs no password must not ask for one"
}

test_a_system_that_needs_setup_is_raised_for() {
    local tmp log out
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"

    out="$(run_configure_quick_share "$(stub_bundle_reporting "$tmp/bundle" needed)" 1 "$log" 2>&1)"

    assert_contains "$(cat "$log")" "quickshare_setup.sh --port $PORT" \
        "the elevated run has to carry the port the service listens on"
    assert_contains "$out" "Quick Share can receive" "and the step should report what it achieved"
}

test_a_failed_setup_warns_without_stopping_the_install() {
    local tmp out
    tmp="$(new_tmpdir)"

    out="$(run_configure_quick_share "$(stub_bundle_reporting "$tmp/bundle" needed)" 1 /dev/null 1 2>&1)"

    assert_contains "$out" "did not finish" \
        "a firewall that refused is worth saying, not worth failing the install over"
}

test_the_elevated_run_is_never_the_copy_in_the_checkout() {
    local tmp log bundle out
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    bundle="$(stub_bundle_reporting "$tmp/bundle" needed)"

    out="$(run_configure_quick_share "$bundle" 1 "$log" 2>&1)"

    # The checkout is this user's to rewrite, so sudo must not be handed a path in it:
    # what is elevated is the copy the installer puts where only root can change it.
    assert_not_contains "$(cat "$log")" "ESCALATE bash $bundle/shell/scripts/quickshare_setup.sh" \
        "the user-writable helper must never be what root runs"
    assert_contains "$(cat "$log")" "ESCALATE bash /usr/lib/caelestia/scripts/quickshare_setup.sh --port $PORT" \
        "the elevated run carries the port against the root-owned helper"
    assert_contains "$out" "Quick Share can receive" "and the step still reports what it achieved"
    assert_contains "$(cat "$log")" "ESCALATE install -d -m 0755 -o root -g root /usr/lib/caelestia/scripts" \
        "the helper is installed into a directory root owns"
}

run_tests
