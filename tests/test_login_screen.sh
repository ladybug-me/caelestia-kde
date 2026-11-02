#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDDM_SCRIPT="$REPO_ROOT/scripts/05-sddm-theme.sh"
KDE_SCRIPT="$REPO_ROOT/scripts/04-deploy-kde.sh"
UNINSTALL_SCRIPT="$REPO_ROOT/uninstall.sh"
SYNC_SCRIPT="$REPO_ROOT/src/sddm/sync.sh"
CLI="$REPO_ROOT/src/bin/caelestia"

PLASMA_LOGIN_HOOK="sudo -n /usr/local/bin/caelestia-greeter-sync --posthook"
SDDM_HOOK="sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh --posthook"

extract_python_block() {
    awk -v needle="$2" '
        /<<.PYEOF.$/ { inblock = 1; buf = ""; next }
        inblock && /^PYEOF$/ {
            if (index(buf, needle) > 0) { printf "%s", buf; found = 1 }
            inblock = 0
            next
        }
        inblock { buf = buf $0 "\n" }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

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
    "wallpaper": { "postHook": "my-own-tool --posthook && $SDDM_HOOK" },
    "theme": { "postHook": "$PLASMA_LOGIN_HOOK" },
    "unrelated": { "keep": true }
}
EOF
}

test_reinstalling_keeps_a_hook_that_is_not_ours() {
    have_python || return 0

    local dir
    dir="$(new_tmpdir)"
    write_fixture "$dir/cli.json"
    printf '%s\n' "{\"wallpaper\": {\"postHook\": \"sudo my-own-tool --posthook\"}}" > "$dir/other.json"

    extract_python_block "$SDDM_SCRIPT" postHook > "$dir/install.py" || {
        fail "05-sddm-theme.sh no longer has a posthook python block"
        return 0
    }

    python3 "$dir/install.py" "$dir/other.json" "$PLASMA_LOGIN_HOOK" >/dev/null 2>&1

    local after
    after="$(json_get "$dir/other.json" wallpaper postHook)"
    assert_contains "$after" "sudo my-own-tool --posthook" "a hook belonging to another tool must survive a reinstall"
    assert_eq "sudo my-own-tool --posthook && $PLASMA_LOGIN_HOOK" "$after" "and ours should be registered behind it"
}

test_installer_replaces_its_own_hook_in_place() {
    have_python || return 0

    local dir
    dir="$(new_tmpdir)"
    write_fixture "$dir/cli.json"
    extract_python_block "$SDDM_SCRIPT" postHook > "$dir/install.py" || {
        fail "05-sddm-theme.sh no longer has a posthook python block"
        return 0
    }

    python3 "$dir/install.py" "$dir/cli.json" "$PLASMA_LOGIN_HOOK" >/dev/null 2>&1
    local wallpaper theme
    wallpaper="$(json_get "$dir/cli.json" wallpaper postHook)"
    theme="$(json_get "$dir/cli.json" theme postHook)"

    assert_eq "my-own-tool --posthook && $PLASMA_LOGIN_HOOK" "$wallpaper" "the SDDM helper should be replaced by the Plasma Login one, behind the user's hook"
    assert_eq "$PLASMA_LOGIN_HOOK" "$theme" "the old helper should not survive as a second hook"

    python3 "$dir/install.py" "$dir/cli.json" "$PLASMA_LOGIN_HOOK" >/dev/null 2>&1
    assert_eq "$wallpaper" "$(json_get "$dir/cli.json" wallpaper postHook)" "a second run should be idempotent"
    assert_eq "True" "$(json_get "$dir/cli.json" unrelated keep)" "keys this script does not know should be left alone"
}

test_the_registered_hook_cannot_block_on_a_password_prompt() {
    # A wallpaper change runs the hook with no terminal of its own. `sudo` without -n
    # tries to prompt there and either fails with nothing useful in the log or waits,
    # so the hook is registered in a form that only ever succeeds or fails.
    assert_contains "$(cat "$SDDM_SCRIPT")" 'POSTHOOK_CMD="sudo -n $SYNC_SCRIPT --posthook"' \
        "the hook must be registered with sudo -n, in that exact form"
}

test_a_hook_written_before_sudo_n_is_still_recognised() {
    have_python || return 0

    local dir
    dir="$(new_tmpdir)"
    printf '%s\n' '{
    "wallpaper": { "postHook": "sudo /usr/local/bin/caelestia-greeter-sync --posthook" },
    "theme": { "postHook": "sudo -n /usr/local/bin/caelestia-greeter-sync --posthook" }
}' > "$dir/cli.json"

    extract_python_block "$SDDM_SCRIPT" postHook > "$dir/install.py" || {
        fail "05-sddm-theme.sh no longer has a posthook python block"
        return 0
    }
    python3 "$dir/install.py" "$dir/cli.json" "$PLASMA_LOGIN_HOOK" >/dev/null 2>&1

    assert_eq "$PLASMA_LOGIN_HOOK" "$(json_get "$dir/cli.json" wallpaper postHook)" \
        "an install from before -n must not gain a second copy of the helper"
}

test_uninstall_removes_the_same_hooks_the_installer_writes() {
    have_python || return 0

    local dir
    dir="$(new_tmpdir)"
    write_fixture "$dir/cli.json"
    extract_python_block "$UNINSTALL_SCRIPT" postHook > "$dir/uninstall.py" || {
        fail "uninstall.sh no longer has a posthook python block"
        return 0
    }

    python3 "$dir/uninstall.py" "$dir/cli.json" >/dev/null 2>&1

    assert_eq "my-own-tool --posthook" "$(json_get "$dir/cli.json" wallpaper postHook)" "uninstall should leave the user's hook behind"
    assert_eq "<absent>" "$(json_get "$dir/cli.json" theme postHook)" "uninstall should remove ours, not leave an empty hook behind"
}

test_the_saved_theme_selection_is_named_the_same_twice() {
    local written read_back
    written="$(grep -o 'state}/caelestia/sddm\.conf\.theme-current' "$SDDM_SCRIPT" | head -n 1)"
    read_back="$(grep -o 'state}/caelestia/sddm\.conf\.theme-current' "$UNINSTALL_SCRIPT" | head -n 1)"

    assert_ne "" "$written" "05-sddm-theme.sh should save the previous theme selection"
    assert_eq "$written" "$read_back" "both scripts should name the same saved value"

    assert_contains "$(cat "$SDDM_SCRIPT")" '#none' "the installer should be able to record that there was no selection"
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" '#none' "uninstall should understand that record"
}

test_the_login_wallpaper_copy_has_a_directory_of_its_own() {
    assert_contains "$(cat "$SYNC_SCRIPT")" 'PLASMALOGIN_WALLPAPERS="$PLASMALOGIN_HOME/wallpapers/caelestia"' "the sync should copy into its own directory"
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" '"$PLASMALOGIN_HOME/wallpapers/caelestia"' "uninstall should remove that directory"
    assert_not_contains "$(cat "$UNINSTALL_SCRIPT")" 'rm -rf "$PLASMALOGIN_HOME/wallpapers"' "uninstall must not remove the shared wallpapers directory"
}

test_uninstall_removes_only_the_schemes_that_were_copied() {
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" 'color-schemes/Matugen"*.colors' "uninstall should name the schemes it copied"
    assert_not_contains "$(cat "$UNINSTALL_SCRIPT")" 'rm -rf "$PLASMALOGIN_HOME/.local/share/color-schemes"' "uninstall must not remove the shared colour schemes directory"
    assert_contains "$(cat "$SYNC_SCRIPT")" 'color-schemes/Matugen*.colors' "the sync should copy only those schemes in the first place"

    assert_contains "$(cat "$UNINSTALL_SCRIPT")" 'rm -f "$HOME/.local/share/color-schemes/Matugen"*.colors' "uninstall should remove the generated schemes from the user's own directory too"
}

test_the_breeze_login_wallpaper_is_patched_in_one_place() {
    local script
    script="$(cat "$KDE_SCRIPT")"

    assert_eq "1" "$(printf '%s\n' "$script" | grep -c '^patch_breeze_login_wallpaper() {')" "the patch should be defined once"
    assert_eq "1" "$(printf '%s\n' "$script" | grep -c 'background=$image')" "and should be the only thing that writes that background"
    assert_contains "$script" 'patch_breeze_login_wallpaper "$WALLPAPER_IN_USE"' "the branch that keeps the user's wallpaper should still match the logout screen to it"
    assert_contains "$script" 'patch_breeze_login_wallpaper "$WALLPAPER_PATH"' "and the default branch should match it to the wallpaper it sets"

    assert_contains "$script" 'if ! install_is_packaged &&' "the helper should skip a packaged install, where the theme is a package's file"
}

test_the_login_screen_command_runs_the_greeter_step() {
    local dir data
    dir="$(new_tmpdir)"
    data="$dir/data"
    mkdir -p "$data/scripts"

    cat > "$data/scripts/05-sddm-theme.sh" <<EOF
#!/bin/bash
printf '%s|%s\n' "\$BUNDLE_DIR" "\$CAELESTIA_INSTALL_KIND" > "$dir/ran"
EOF

    CAELESTIA_DATA_DIR="$data" CAELESTIA_INSTALL_KIND=package \
        bash "$CLI" login-screen > "$dir/out.txt" 2>&1
    local status=$?

    assert_status 0 "$status" "login-screen should run the greeter step"
    assert_eq "$data|package" "$(cat "$dir/ran" 2>/dev/null)" \
        "the step should hear which install it belongs to, and where its bundle is"
}

test_the_greeter_check_reads_the_theme_like_sddm_does() {
    local dir stubs
    dir="$(new_tmpdir)"

    extract_function "$SDDM_SCRIPT" theme_qt_version > "$dir/qt-version.sh"
    extract_function "$SDDM_SCRIPT" greeter_binary_for_qt > "$dir/greeter-binary.sh"
    extract_function "$SDDM_SCRIPT" greeter_path_for_qt > "$dir/greeter-path.sh"
    assert_ne "" "$(cat "$dir/qt-version.sh")" "05-sddm-theme.sh should read the theme's QtVersion"
    assert_ne "" "$(cat "$dir/greeter-path.sh")" "and should look for the greeter SDDM would run"

    source "$dir/qt-version.sh"
    source "$dir/greeter-binary.sh"
    source "$dir/greeter-path.sh"

    printf '[SddmGreeterTheme]\nQtVersion=6\n' > "$dir/metadata.desktop"
    assert_eq "6" "$(theme_qt_version "$dir/metadata.desktop")" \
        "the version SDDM routes on should come out of the theme's metadata"

    printf '[SddmGreeterTheme]\nName=Caelestia\n' > "$dir/undeclared.desktop"
    assert_eq "" "$(theme_qt_version "$dir/undeclared.desktop")" \
        "a theme that does not declare one should report nothing, which SDDM reads as Qt 5"
    assert_eq "" "$(theme_qt_version "$dir/absent.desktop")" "so should a theme with no metadata at all"

    assert_eq "sddm-greeter" "$(greeter_binary_for_qt 5)" "the Qt 5 greeter is the unsuffixed binary"
    assert_eq "sddm-greeter-qt6" "$(greeter_binary_for_qt 6)" "and every other version carries its number"

    stubs="$dir/stubs"
    stub_bin "$stubs" sddm-greeter-qt6
    assert_eq "$stubs/sddm-greeter-qt6" "$(with_path "$stubs" "" greeter_path_for_qt 6)" \
        "the greeter should be looked up under the name SDDM runs"
}

test_the_theme_is_selected_only_when_its_greeter_is_there() {
    local script
    script="$(cat "$SDDM_SCRIPT")"

    assert_eq "1" "$(printf '%s\n' "$script" | grep -c '^verify_theme_greeter() {')" \
        "the theme's greeter should be checked in one place"
    assert_contains "$script" 'theme_qt_version "$metadata"' "the check should read the theme's QtVersion"
    assert_contains "$script" 'greeter_path_for_qt "$version"' "and look for the greeter that version needs"
    assert_contains "$script" 'if ! verify_theme_greeter; then' "whose result should gate the selection"
    assert_contains "$script" 'elif [[ "$THEME_RUNNABLE" != "true" ]]; then' \
        "a theme that cannot run should not be selected"
    assert_contains "$script" 'remove_theme_selection' \
        "and a selection of ours from an earlier run should be taken back"
    assert_contains "$script" 'The theme is installed but left unselected' \
        "with a warning that says what was left alone"
    assert_contains "$script" "run 'caelestia login-screen'" \
        "and how to try again once the greeter is there"
}

display_manager_seen_by() {
    with_path "$1" "" "$BASH" -c \
        'source "$1"; if is_plasmalogin_active; then echo plasmalogin; else echo sddm; fi' _ "$2"
}

test_the_boot_alias_decides_the_display_manager() {
    local dir stubs script name extracted
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

    for script in "$SDDM_SCRIPT" "$SYNC_SCRIPT"; do
        name="$(basename -- "$script")"
        extracted="$dir/$name.detect.sh"
        extract_function "$script" is_plasmalogin_active > "$extracted"
        assert_ne "" "$(cat "$extracted")" "$name should say which display manager is live"

        printf '%s\n' /usr/lib/systemd/system/sddm.service > "$dir/alias"
        assert_eq "sddm" "$(display_manager_seen_by "$stubs" "$extracted")" \
            "$name: the boot alias should decide over the other manager's unit"
        printf '%s\n' /usr/lib/systemd/system/plasmalogin.service > "$dir/alias"
        assert_eq "plasmalogin" "$(display_manager_seen_by "$stubs" "$extracted")" \
            "$name: and it should decide for Plasma Login too"

        printf '%s\n' /usr/lib/systemd/system/sddm.service > "$dir/alias"
        stub_bin "$stubs" systemctl 'case "$*" in *plasmalogin*) exit 0 ;; *) exit 1 ;; esac'
        assert_eq "sddm" "$(display_manager_seen_by "$stubs" "$extracted")" \
            "$name: a still-enabled Plasma Login should not outvote the boot alias"

        rm -f "$dir/alias"
        stub_bin "$stubs" systemctl 'case "$*" in *plasmalogin*) exit 0 ;; *) exit 1 ;; esac'
        assert_eq "plasmalogin" "$(display_manager_seen_by "$stubs" "$extracted")" \
            "$name: an enabled Plasma Login should still be found without an alias"
        stub_bin "$stubs" systemctl 'case "$*" in *sddm.service*) exit 0 ;; *) exit 1 ;; esac'
        assert_eq "sddm" "$(display_manager_seen_by "$stubs" "$extracted")" \
            "$name: and so should an enabled SDDM"
    done
}

test_the_variant_survives_a_repoint() {
    local dir
    dir="$(new_tmpdir)"

    extract_function "$SDDM_SCRIPT" installed_variant > "$dir/variant.sh"
    assert_ne "" "$(cat "$dir/variant.sh")" \
        "05-sddm-theme.sh should be able to read the variant that is installed"
    source "$dir/variant.sh"

    mkdir -p "$dir/full" "$dir/mini" "$dir/mini/singletons" "$dir/none"
    : > "$dir/full/metadata.desktop"
    : > "$dir/mini/metadata.desktop"

    assert_eq "full" "$(installed_variant "$dir/full")" "a theme without singletons/ is the full one"
    assert_eq "mini" "$(installed_variant "$dir/mini")" "the mini theme ships its own singletons/"
    if installed_variant "$dir/none" >/dev/null 2>&1; then
        fail "a directory holding no theme should not name a variant"
    fi

    assert_contains "$(cat "$SDDM_SCRIPT")" 'installed_variant "$INSTALL_DIR"' \
        "and the step should fall back to it, not to the default variant"
}

run_tests
