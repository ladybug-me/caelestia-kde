#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGIN_STEP="$REPO_ROOT/installer/src/steps/login_screen.rs"
UNINSTALL_STEP="$REPO_ROOT/installer/src/uninstall.rs"
SYNC_SCRIPT="$REPO_ROOT/src/sddm/sync.sh"
CLI="$REPO_ROOT/src/bin/caelestia"

PLASMA_LOGIN_HOOK="sudo /usr/local/bin/caelestia-greeter-sync --posthook"

# What the step installs is the crate's own behaviour now, and the crate tests it
# (installer/src/steps/login_screen.rs and installer/tests/steps.rs): the variant that is
# read from the installed theme, the Qt version SDDM routes on, which greeter that version
# needs, which display manager is live, when a theme is left unselected, and the posthook
# edit that keeps a hook the user wrote. What is left here is the pairing between the step
# and the uninstall that undoes it, and sync.sh, which is shipped rather than run.

json_get() {
    python3 - "$@" <<'PYEOF'
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2:]:
    if not isinstance(value, dict) or key not in value:
        print("<absent>")
        sys.exit(0)
    value = value[key]
print(value)
PYEOF
}

have_python() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    skip_test "python3 not installed"
    return 1
}

write_fixture() {
    cat > "$1" <<EOF
{
    "wallpaper": { "postHook": "my-own-tool --posthook && $PLASMA_LOGIN_HOOK" },
    "theme": { "postHook": "$PLASMA_LOGIN_HOOK" },
    "unrelated": { "keep": true }
}
EOF
}

test_the_step_and_uninstall_recognise_the_same_helpers() {
    local step uninstall
    step="$(cat "$LOGIN_STEP")"
    uninstall="$(cat "$UNINSTALL_STEP")"

    for helper in 'sync\.sh' 'caelestia-greeter-sync'; do
        assert_contains "$step" "$helper" "the step should treat $helper as one of ours"
        assert_contains "$uninstall" "$helper" "and so should uninstall, or it would leave one behind"
    done
}

test_uninstall_removes_the_same_hooks_the_installer_writes() {
    have_python || return 0

    local dir
    dir="$(new_tmpdir)"
    write_fixture "$dir/cli.json"

    # The editor is a Python script in the crate; the test drives that same script at the
    # fixture, so what it checks is what the uninstall runs.
    python3 - "$UNINSTALL_STEP" "$dir/uninstall.py" <<'PYEOF'
import re, sys
source = open(sys.argv[1]).read()
blocks = re.findall(r'POSTHOOK_CLEANER: &str = r##"(.*?)"##;', source, re.S)
for block in blocks:
    if "postHook" in block:
        open(sys.argv[2], "w").write(block)
        sys.exit(0)
sys.exit(1)
PYEOF

    if [[ ! -f "$dir/uninstall.py" ]]; then
        fail "the uninstall no longer has a posthook editor"
        return 0
    fi

    python3 "$dir/uninstall.py" "$dir/cli.json" >/dev/null 2>&1

    assert_eq "my-own-tool --posthook" "$(json_get "$dir/cli.json" wallpaper postHook)" "uninstall should leave the user's hook behind"
    assert_eq "<absent>" "$(json_get "$dir/cli.json" theme postHook)" "uninstall should remove ours, not leave an empty hook behind"
}

test_the_saved_theme_selection_is_named_the_same_twice() {
    local written read_back
    written="$(grep -o 'sddm\.conf\.theme-current' "$LOGIN_STEP" | head -n 1)"
    read_back="$(grep -o 'caelestia/sddm\.conf\.theme-current' "$UNINSTALL_STEP" | head -n 1)"

    assert_ne "" "$written" "the step should save the previous theme selection"
    assert_ne "" "$read_back" "and uninstall should read the same record"
    assert_contains "$read_back" "$written" "both should name the same file"

    assert_contains "$(cat "$LOGIN_STEP")" '#none' "the installer should be able to record that there was no selection"
    assert_contains "$(cat "$UNINSTALL_STEP")" '#none' "uninstall should understand that record"
}

test_the_login_wallpaper_copy_has_a_directory_of_its_own() {
    assert_contains "$(cat "$SYNC_SCRIPT")" 'PLASMALOGIN_WALLPAPERS="$PLASMALOGIN_HOME/wallpapers/caelestia"' "the sync should copy into its own directory"
    assert_contains "$(cat "$UNINSTALL_STEP")" 'wallpapers/caelestia' "uninstall should remove that directory"
    assert_not_contains "$(cat "$UNINSTALL_STEP")" 'join("wallpapers")' "uninstall must not remove the shared wallpapers directory"
}

test_uninstall_removes_only_the_schemes_that_were_copied() {
    assert_contains "$(cat "$UNINSTALL_STEP")" '"Matugen"' "uninstall should name the schemes it copied"
    assert_not_contains "$(cat "$UNINSTALL_STEP")" 'remove_tree(&schemes)' "uninstall must not remove the shared colour schemes directory"
    assert_contains "$(cat "$SYNC_SCRIPT")" 'color-schemes/Matugen*.colors' "the sync should copy only those schemes in the first place"

    assert_contains "$(cat "$UNINSTALL_STEP")" 'remove_by_prefix(&self.path(directory), prefix)' "uninstall should remove the generated schemes from the user's own directory too"
}

test_the_login_screen_command_runs_the_greeter_step() {
    local dir data
    dir="$(new_tmpdir)"
    data="$dir/data"
    mkdir -p "$data/scripts/lib"
    cp "$REPO_ROOT/scripts/lib/installer-bin.sh" "$data/scripts/lib/"

    # The step is native, so the command reaches it the way every other step is reached:
    # by id, through the resolver, which is what this stands in for.
    cat > "$data/caelestia-install" <<EOF
#!/bin/bash
printf '%s|%s|%s|%s\n' "\$1" "\$2" "\$BUNDLE_DIR" "\$CAELESTIA_INSTALL_KIND" > "$dir/ran"
printf 'INSTALL_SDDM=%s\n' "\$INSTALL_SDDM" >> "$dir/ran"
EOF
    chmod +x "$data/caelestia-install"

    CAELESTIA_DATA_DIR="$data" CAELESTIA_INSTALL_KIND=package \
        bash "$CLI" login-screen > "$dir/out.txt" 2>&1
    local status=$?

    assert_status 0 "$status" "login-screen should run the greeter step"
    assert_contains "$(cat "$dir/ran" 2>/dev/null)" "step|05-sddm-theme|$data|package" \
        "the step should hear which install it belongs to, and where its bundle is"
    assert_contains "$(cat "$dir/ran" 2>/dev/null)" "INSTALL_SDDM=true" \
        "running the step by hand is asking for the login screen"
}

display_manager_seen_by() {
    with_path "$1" "" "$BASH" -c \
        'source "$1"; if is_plasmalogin_active; then echo plasmalogin; else echo sddm; fi' _ "$2"
}

test_the_shipped_sync_helper_reads_the_boot_alias() {
    # sync.sh is shipped into the theme, not run by the installer, so it keeps its own copy
    # of this - and it has to keep agreeing with the step on which manager is live.
    local dir stubs extracted
    dir="$(new_tmpdir)"
    stubs="$dir/bin"
    mkdir -p "$stubs"

    stub_bin "$stubs" systemctl 'exit 1'
    cat > "$stubs/readlink" <<STUB
#!/bin/bash
target=""
read -r target < "$dir/alias" 2>/dev/null || target=""
printf '%s\n' "\$target"
STUB
    chmod +x "$stubs/readlink"

    extracted="$dir/sync.detect.sh"
    extract_function "$SYNC_SCRIPT" is_plasmalogin_active > "$extracted"
    assert_ne "" "$(cat "$extracted")" "sync.sh should say which display manager is live"

    printf '%s\n' /usr/lib/systemd/system/sddm.service > "$dir/alias"
    assert_eq "sddm" "$(display_manager_seen_by "$stubs" "$extracted")" \
        "the boot alias should decide for SDDM"
    printf '%s\n' /usr/lib/systemd/system/plasmalogin.service > "$dir/alias"
    assert_eq "plasmalogin" "$(display_manager_seen_by "$stubs" "$extracted")" \
        "and for Plasma Login"

    printf '%s\n' /usr/lib/systemd/system/sddm.service > "$dir/alias"
    stub_bin "$stubs" systemctl 'case "$*" in *plasmalogin*) exit 0 ;; *) exit 1 ;; esac'
    assert_eq "sddm" "$(display_manager_seen_by "$stubs" "$extracted")" \
        "a still-enabled Plasma Login should not outvote the boot alias"

    rm -f "$dir/alias"
    stub_bin "$stubs" systemctl 'case "$*" in *plasmalogin*) exit 0 ;; *) exit 1 ;; esac'
    assert_eq "plasmalogin" "$(display_manager_seen_by "$stubs" "$extracted")" \
        "an enabled Plasma Login should still be found without an alias"
    stub_bin "$stubs" systemctl 'case "$*" in *sddm.service*) exit 0 ;; *) exit 1 ;; esac'
    assert_eq "sddm" "$(display_manager_seen_by "$stubs" "$extracted")" \
        "and so should an enabled SDDM"
}

run_tests