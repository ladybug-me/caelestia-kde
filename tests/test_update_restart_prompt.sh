#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_BIN="$REPO_ROOT/src/bin/caelestia-update"

require_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    skip_test "git is not installed"
    return 1
}

# Helper to load step 7 functions and execution block in an isolated environment
run_step7() {
    local bundle="$1" config="$2" bin="$3" log="$4"
    local prev_rev="${5:-}" new_rev="${6:-}" assume_no="${7:-1}" skip_build="${8:-0}"
    local answer="${9:-}"

    (
        export PATH="$bin:$PATH"
        export HOME="$(dirname "$config")"
        export BUNDLE_DIR="$bundle"
        export CAELESTIA_ASSUME_NO="$assume_no"
        export CAELESTIA_SKIP_BUILD="$skip_build"
        export CAELESTIA_LOG_FILE="$log"
        export QUICKSHELL_DIR="$config"

        info() { printf '[INFO] %s\n' "$*" >> "$log"; }
        warn() { printf '[WARN] %s\n' "$*" >> "$log"; }

        # Source the functions directly from caelestia-update
        eval "$(extract_function "$UPDATE_BIN" "ask_yes_no")"
        eval "$(extract_function "$UPDATE_BIN" "notify_update")"
        eval "$(extract_function "$UPDATE_BIN" "log_out_now")"
        eval "$(extract_function "$UPDATE_BIN" "restart_shell_now")"

        PREV_REV="$prev_rev"
        NEW_REV="$new_rev"
        SHELL_CHANGED=0

        if [[ -z "$PREV_REV" || -z "$NEW_REV" ]]; then
            SHELL_CHANGED=1
        elif [[ "$PREV_REV" != "$NEW_REV" ]]; then
            if [[ "$PREV_REV" =~ ^[0-9a-fA-F]{7,40}$ && "$NEW_REV" =~ ^[0-9a-fA-F]{7,40}$ ]] && \
               CHANGED_FILES="$(git -C "$BUNDLE_DIR" diff --name-only "$PREV_REV" "$NEW_REV" 2>/dev/null)"; then
                if grep -q '^shell/' <<< "$CHANGED_FILES"; then
                    SHELL_CHANGED=1
                fi
            else
                SHELL_CHANGED=1
            fi
        fi

        printf 'SHELL_CHANGED=%d\n' "$SHELL_CHANGED" >> "$log"

        if [[ "${CAELESTIA_SKIP_BUILD:-0}" == "1" ]]; then
            info "Build skipped; the running shell is already what is installed."
        elif [[ "$SHELL_CHANGED" -eq 1 ]]; then
            notify_update "Log out to load the new shell: it was rebuilt and a restart alone leaves it on the old plugin."
            if ask_yes_no "The shell itself was rebuilt. Restarting it is not enough, so log out to load it. Log out now? [y/N] "; then
                info "Logging out..."
                log_out_now || warn "Could not log out automatically; log out manually to load the new shell."
            else
                info "Log out when convenient to load the new shell."
            fi
        else
            notify_update "Restart the shell to load it."
            if ask_yes_no "Restart the Caelestia shell to load the update? [y/N] "; then
                info "Restarting the shell..."
                restart_shell_now || warn "Could not restart the shell automatically; restart it manually."
            else
                info "The update will apply the next time the shell starts."
            fi
        fi
    )
}

test_ask_yes_no_without_controlling_tty_returns_1_silently() {
    local tmp out err
    tmp="$(new_tmpdir)"

    # Run in a detached session without a controlling terminal
    python3 -c "
import subprocess, sys

script = '''
source \"$REPO_ROOT/tests/helpers.sh\"
eval \"\$(extract_function \"$UPDATE_BIN\" \"ask_yes_no\")\"
ask_yes_no \"Prompt? [y/N] \"
echo \"STATUS=\$?\"
'''

p = subprocess.Popen(
    ['bash', '-c', script],
    start_new_session=True,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)
out, err = p.communicate()
sys.stdout.write(out.decode())
sys.stderr.write(err.decode())
if err:
    sys.exit(2)
" > "$tmp/out.log" 2> "$tmp/err.log"
    local status=$?

    assert_status 0 "$status" "ask_yes_no should complete without failing or printing errors to stderr"
    assert_file_contains "$tmp/out.log" "STATUS=1" "ask_yes_no without tty must default to 1 (no)"
    assert_eq "" "$(cat "$tmp/err.log")" "ask_yes_no must not print /dev/tty error messages to stderr"
}

test_ask_yes_no_respects_assume_no_flag() {
    local tmp
    tmp="$(new_tmpdir)"

    local res="$(
        eval "$(extract_function "$UPDATE_BIN" "ask_yes_no")"
        CAELESTIA_ASSUME_NO=1 ask_yes_no "Test? " || echo "declined"
    )"
    assert_eq "declined" "$res" "CAELESTIA_ASSUME_NO=1 must immediately decline"
}

test_ask_yes_no_pty_yes_answers() {
    local tmp fn
    tmp="$(new_tmpdir)"
    fn="$(extract_function "$UPDATE_BIN" "ask_yes_no")"

    ASK_FN="$fn" python3 -c "
import pty, os, subprocess, fcntl, termios, sys

master, slave = pty.openpty()

def preexec():
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

script = '''
eval \"\$ASK_FN\"
if ask_yes_no \"Confirm? \"; then
    echo \"ACCEPTED\"
else
    echo \"REJECTED\"
fi
'''

proc = subprocess.Popen(
    ['bash', '-c', script],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    preexec_fn=preexec,
    close_fds=True
)
os.close(slave)
os.write(master, b'y\n')
output = b''
while True:
    try:
        data = os.read(master, 1024)
        if not data:
            break
        output += data
    except OSError:
        break
os.close(master)
proc.wait()
sys.stdout.write(output.decode())
" > "$tmp/pty.log" 2>&1

    assert_file_contains "$tmp/pty.log" "ACCEPTED" "user answering 'y' in a pty must be accepted"
}

test_ask_yes_no_pty_enter_defaults_to_no() {
    local tmp fn
    tmp="$(new_tmpdir)"
    fn="$(extract_function "$UPDATE_BIN" "ask_yes_no")"

    ASK_FN="$fn" python3 -c "
import pty, os, subprocess, fcntl, termios, sys

master, slave = pty.openpty()

def preexec():
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

script = '''
eval \"\$ASK_FN\"
if ask_yes_no \"Confirm? \"; then
    echo \"ACCEPTED\"
else
    echo \"REJECTED\"
fi
'''

proc = subprocess.Popen(
    ['bash', '-c', script],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    preexec_fn=preexec,
    close_fds=True
)
os.close(slave)
os.write(master, b'\n')
output = b''
while True:
    try:
        data = os.read(master, 1024)
        if not data:
            break
        output += data
    except OSError:
        break
os.close(master)
proc.wait()
sys.stdout.write(output.decode())
" > "$tmp/pty.log" 2>&1

    assert_file_contains "$tmp/pty.log" "REJECTED" "user pressing Enter (empty input) must default to no"
}

test_shell_changed_detected_when_shell_directory_modified() {
    require_git || return 0
    local tmp bundle bin log rev1 rev2
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bundle" "$bin"

    git -C "$bundle" init -q -b main
    git -C "$bundle" config user.email "test@example.com"
    git -C "$bundle" config user.name "Test"

    # Commit 1
    mkdir -p "$bundle/shell/modules/bar"
    printf 'initial\n' > "$bundle/shell/modules/bar/Bar.qml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c1"
    rev1="$(git -C "$bundle" rev-parse HEAD)"

    # Commit 2 (touches shell/)
    printf 'updated\n' > "$bundle/shell/modules/bar/Bar.qml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c2"
    rev2="$(git -C "$bundle" rev-parse HEAD)"

    # Stub notify-send
    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0

    # Stub fake logout (DO NOT run real logout)
    stub_bin "$bin" "qdbus6" 'echo "fake echo logging out" >> "$CAELESTIA_LOG_FILE"; exit 0'

    # Run step 7 in non-interactive mode (assume_no=1)
    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$rev1" "$rev2" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=1" "should detect changes under shell/"
    assert_file_contains "$log" "Log out when convenient" "should inform user to log out"
    assert_file_contains "$tmp/notify.log" "Log out to load the new shell" "notification should recommend logout"
}

test_shell_not_changed_when_only_config_modified() {
    require_git || return 0
    local tmp bundle bin log rev1 rev2
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bundle" "$bin"

    git -C "$bundle" init -q -b main
    git -C "$bundle" config user.email "test@example.com"
    git -C "$bundle" config user.name "Test"

    # Commit 1
    mkdir -p "$bundle/src/dots"
    printf 'initial\n' > "$bundle/src/dots/starship.toml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c1"
    rev1="$(git -C "$bundle" rev-parse HEAD)"

    # Commit 2 (touches only src/dots/, NOT shell/)
    printf 'updated\n' > "$bundle/src/dots/starship.toml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c2"
    rev2="$(git -C "$bundle" rev-parse HEAD)"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0
    recording_stub "$bin" "systemctl" "$tmp/systemctl.log" 0

    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$rev1" "$rev2" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=0" "should not flag shell changed when only config changed"
    assert_file_contains "$log" "The update will apply the next time the shell starts" "should inform user of shell restart"
    assert_file_contains "$tmp/notify.log" "Restart the shell to load it" "notification should recommend restart"
}

test_fake_logout_called_when_confirmed() {
    local tmp bundle bin log
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bin"

    # Stub fake logout (DO NOT run real logout)
    stub_bin "$bin" "qdbus6" 'echo "fake echo logging out" >> "$CAELESTIA_LOG_FILE"; exit 0'

    (
        export PATH="$bin:$PATH"
        export CAELESTIA_LOG_FILE="$log"
        eval "$(extract_function "$UPDATE_BIN" "log_out_now")"
        log_out_now
    )

    assert_file_contains "$log" "fake echo logging out" "fake logout command should be triggered without real logout"
}

test_fallback_to_logout_when_git_diff_cannot_compare() {
    require_git || return 0
    local tmp bundle bin log rev1 rev2
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bundle" "$bin"

    git -C "$bundle" init -q -b main
    git -C "$bundle" config user.email "test@example.com"
    git -C "$bundle" config user.name "Test"

    printf 'init\n' > "$bundle/file.txt"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c1"
    rev2="$(git -C "$bundle" rev-parse HEAD)"

    # Fake unreachable commit hash
    rev1="1111111111111111111111111111111111111111"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0

    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$rev1" "$rev2" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=1" "unreachable revision must fall back to SHELL_CHANGED=1"
    assert_file_contains "$tmp/notify.log" "Log out to load the new shell" "notification should advise logout on missing diff"
}

test_fallback_to_logout_when_prev_rev_empty() {
    local tmp bundle bin log rev2
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bin"
    rev2="2222222222222222222222222222222222222222"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0

    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "" "$rev2" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=1" "empty PREV_REV must fall back to SHELL_CHANGED=1"
    assert_file_contains "$tmp/notify.log" "Log out to load the new shell" "should advise logout when previous commit unknown"
}

test_argument_injection_safety_in_commit_hash() {
    require_git || return 0
    local tmp bundle bin log
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bundle" "$bin"

    git -C "$bundle" init -q -b main
    git -C "$bundle" config user.email "test@example.com"
    git -C "$bundle" config user.name "Test"
    printf 'init\n' > "$bundle/file.txt"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c1"

    # Malicious injection attempt in PREV_REV
    local evil_rev="--output=$tmp/injected_file"
    local valid_rev="$(git -C "$bundle" rev-parse HEAD)"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0

    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$evil_rev" "$valid_rev" 1 0

    assert_file_missing "$tmp/injected_file" "malicious option injection in PREV_REV must not be executed by git"
    assert_file_contains "$log" "SHELL_CHANGED=1" "invalid revision format must safely fall back to SHELL_CHANGED=1"
}

test_build_skipped_bypasses_prompts_and_notifications() {
    local tmp bundle bin log
    tmp="$(new_tmpdir)"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bin"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0
    recording_stub "$bin" "systemctl" "$tmp/systemctl.log" 0

    run_step7 "$tmp/repo" "$tmp/config" "$bin" "$log" "rev1" "rev2" 1 1

    assert_file_contains "$log" "Build skipped" "should report build skipped"
    assert_file_missing "$tmp/notify.log" "notify-send must not be called when build is skipped"
    assert_file_missing "$tmp/systemctl.log" "systemctl must not be called when build is skipped"
}

test_dbus_logout_failure_warns_and_does_not_abort() {
    local tmp bin log
    tmp="$(new_tmpdir)"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bin"

    # Stub qdbus6 failing
    stub_bin "$bin" "qdbus6" 'exit 1'
    stub_bin "$bin" "qdbus" 'exit 1'

    (
        export PATH="$bin:$PATH"
        export CAELESTIA_LOG_FILE="$log"
        warn() { printf '[WARN] %s\n' "$*" >> "$log"; }

        eval "$(extract_function "$UPDATE_BIN" "log_out_now")"
        log_out_now || warn "Could not log out automatically; log out manually to load the new shell."
    )
    local status=$?

    assert_status 0 "$status" "DBus logout failure must be caught gracefully"
    assert_file_contains "$log" "Could not log out automatically" "should warn rather than abort"
}

test_systemctl_restart_failure_warns_and_does_not_abort() {
    local tmp bin log
    tmp="$(new_tmpdir)"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bin"

    stub_bin "$bin" "systemctl" 'exit 1'

    (
        export PATH="$bin:$PATH"
        export CAELESTIA_LOG_FILE="$log"
        warn() { printf '[WARN] %s\n' "$*" >> "$log"; }

        systemctl --user restart caelestia-shell.service || warn "Could not restart caelestia-shell.service; restart it manually."
    )
    local status=$?

    assert_status 0 "$status" "systemctl restart failure must be caught gracefully"
    assert_file_contains "$log" "Could not restart caelestia-shell.service" "should warn rather than abort"
}

test_rollback_to_older_commit_detects_shell_change_and_offers_logout() {
    require_git || return 0
    local tmp bundle bin log rev1 rev2
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bundle" "$bin"

    git -C "$bundle" init -q -b main
    git -C "$bundle" config user.email "test@example.com"
    git -C "$bundle" config user.name "Test"

    # Commit 1 (older target)
    mkdir -p "$bundle/shell/modules/bar"
    printf 'version 1\n' > "$bundle/shell/modules/bar/Bar.qml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "v1"
    rev1="$(git -C "$bundle" rev-parse HEAD)"

    # Commit 2 (current running shell)
    printf 'version 2\n' > "$bundle/shell/modules/bar/Bar.qml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "v2"
    rev2="$(git -C "$bundle" rev-parse HEAD)"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0

    # User rolls back: PREV_REV is rev2 (current), NEW_REV is rev1 (older)
    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$rev2" "$rev1" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=1" "rollback must detect shell differences and set SHELL_CHANGED=1"
    assert_file_contains "$tmp/notify.log" "Log out to load the new shell" "rollback must recommend logout so older plugin is reloaded"
}

test_reinstall_same_version_offers_restart() {
    require_git || return 0
    local tmp bundle bin log rev1
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bundle" "$bin"

    git -C "$bundle" init -q -b main
    git -C "$bundle" config user.email "test@example.com"
    git -C "$bundle" config user.name "Test"

    mkdir -p "$bundle/shell/modules/bar"
    printf 'content\n' > "$bundle/shell/modules/bar/Bar.qml"
    git -C "$bundle" add .
    git -C "$bundle" commit -qm "c1"
    rev1="$(git -C "$bundle" rev-parse HEAD)"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0
    recording_stub "$bin" "systemctl" "$tmp/systemctl.log" 0

    # Reinstall same version: PREV_REV == NEW_REV
    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$rev1" "$rev1" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=0" "reinstalling same version has identical tree; SHELL_CHANGED=0"
    assert_file_contains "$tmp/notify.log" "Restart the shell to load it" "reinstalling same version must offer shell restart"
}

test_unknown_version_new_rev_empty_falls_back_to_logout() {
    local tmp bundle bin log rev1
    tmp="$(new_tmpdir)"
    bundle="$tmp/repo"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$bin"
    rev1="1111111111111111111111111111111111111111"

    recording_stub "$bin" "notify-send" "$tmp/notify.log" 0

    # Unknown NEW_REV (e.g. record_installed_revision failed to write)
    run_step7 "$bundle" "$tmp/config" "$bin" "$log" "$rev1" "" 1 0

    assert_file_contains "$log" "SHELL_CHANGED=1" "missing/unknown NEW_REV must safely fall back to SHELL_CHANGED=1"
    assert_file_contains "$tmp/notify.log" "Log out to load the new shell" "unknown revision state must recommend logout"
}

test_restart_shell_now_executes_quickshell_dir_script() {
    local tmp config bin log
    tmp="$(new_tmpdir)"
    config="$tmp/quickshell"
    bin="$tmp/bin"
    log="$tmp/test.log"
    mkdir -p "$config/scripts" "$bin"

    # Create dummy restart_shell.sh in quickshellDir/scripts/
    cat > "$config/scripts/restart_shell.sh" << 'EOF'
#!/bin/bash
echo "restarted via quickshellDir script" >> "$CAELESTIA_LOG_FILE"
EOF
    chmod +x "$config/scripts/restart_shell.sh"

    (
        export PATH="$bin:$PATH"
        export QUICKSHELL_DIR="$config"
        export BUNDLE_DIR="$tmp/bundle"
        export CAELESTIA_LOG_FILE="$log"

        eval "$(extract_function "$UPDATE_BIN" "restart_shell_now")"
        restart_shell_now
    )
    local status=$?

    assert_status 0 "$status" "restart_shell_now should execute successfully"
    assert_file_contains "$log" "restarted via quickshellDir script" \
        "restart_shell_now must run {quickshellDir}/scripts/restart_shell.sh"
}

run_tests
