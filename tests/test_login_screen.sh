#!/usr/bin/env bash
# test_login_screen.sh - Tests for what the login-screen install leaves behind.
#
# Four pieces of state two scripts must agree on: which cli.json posthooks are ours,
# where the pre-install /etc/sddm.conf theme selection is kept, the Plasma Login wallpaper
# directory, and which color schemes uninstall removes. The scripts are read and driven,
# not copied - a copy is what would drift.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDDM_SCRIPT="$REPO_ROOT/scripts/05-sddm-theme.sh"
KDE_SCRIPT="$REPO_ROOT/scripts/04-deploy-kde.sh"
UNINSTALL_SCRIPT="$REPO_ROOT/uninstall.sh"
SYNC_SCRIPT="$REPO_ROOT/src/sddm/sync.sh"

PLASMA_LOGIN_HOOK="sudo /usr/local/bin/caelestia-greeter-sync --posthook"
SDDM_HOOK="sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh --posthook"

# extract_python_block <script> <needle>
#
# Prints the `PYEOF` heredoc of <script> whose body mentions <needle>. Both scripts
# embed the posthook handling as python, and running it is the only way to assert
# what it does.
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

# json_get <file> <key-path...>
#
# Prints the value, or `<absent>` when the key is missing - what uninstall leaves
# when a hook was only ever ours.
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

# A cli.json holding one hook of ours, one the user wrote for another tool, a key
# this script has never heard of, and nothing else.
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

    # The pattern used to be `sudo <anything> --posthook`, which this installer cannot
    # claim: reinstalling would silently remove a user's own hook from cli.json.
    local dir
    dir="$(new_tmpdir)"
    write_fixture "$dir/cli.json"
    printf '%s\n' "{\"wallpaper\": {\"postHook\": \"sudo my-own-tool --posthook\"}}" > "$dir/other.json"

    extract_python_block "$SDDM_SCRIPT" postHook > "$dir/install.py" || {
        fail "05-sddm-theme.sh no longer has a posthook python block"
        return 0
    }

    python3 "$dir/install.py" "$dir/other.json" "$PLASMA_LOGIN_HOOK" >/dev/null 2>&1

    # Ours goes in behind it, which is the behaviour wanted; what must not happen is
    # the user's hook disappearing, which is what the old pattern did to it.
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

    # Running it again must land on the same string: a stacked copy would run the sync
    # twice per wallpaper change.
    python3 "$dir/install.py" "$dir/cli.json" "$PLASMA_LOGIN_HOOK" >/dev/null 2>&1
    assert_eq "$wallpaper" "$(json_get "$dir/cli.json" wallpaper postHook)" "a second run should be idempotent"
    assert_eq "True" "$(json_get "$dir/cli.json" unrelated keep)" "keys this script does not know should be left alone"
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
    # 05-sddm-theme.sh saves the pre-install /etc/sddm.conf value and uninstall.sh puts
    # it back. Two spellings of the path mean the user's selection is never restored,
    # and nothing else would notice.
    local written read_back
    written="$(grep -o 'state}/caelestia/sddm\.conf\.theme-current' "$SDDM_SCRIPT" | head -n 1)"
    read_back="$(grep -o 'state}/caelestia/sddm\.conf\.theme-current' "$UNINSTALL_SCRIPT" | head -n 1)"

    assert_ne "" "$written" "05-sddm-theme.sh should save the previous theme selection"
    assert_eq "$written" "$read_back" "both scripts should name the same saved value"

    # `#none` is what stands for "there was no selection to put back", and both sides
    # have to know it.
    assert_contains "$(cat "$SDDM_SCRIPT")" '#none' "the installer should be able to record that there was no selection"
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" '#none' "uninstall should understand that record"
}

test_the_login_wallpaper_copy_has_a_directory_of_its_own() {
    # The greeter's wallpaper directory is shared with KDE's Login Screen settings, so
    # clearing everything but the current wallpaper would delete the user's own picks.
    assert_contains "$(cat "$SYNC_SCRIPT")" 'PLASMALOGIN_WALLPAPERS="$PLASMALOGIN_HOME/wallpapers/caelestia"' "the sync should copy into its own directory"
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" '"$PLASMALOGIN_HOME/wallpapers/caelestia"' "uninstall should remove that directory"
    assert_not_contains "$(cat "$UNINSTALL_SCRIPT")" 'rm -rf "$PLASMALOGIN_HOME/wallpapers"' "uninstall must not remove the shared wallpapers directory"
}

test_uninstall_removes_only_the_schemes_that_were_copied() {
    # The colour schemes directory is KDE's, and other tools write schemes there. Only
    # the files this installer copied are named for removal.
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" 'color-schemes/Matugen"*.colors' "uninstall should name the schemes it copied"
    assert_not_contains "$(cat "$UNINSTALL_SCRIPT")" 'rm -rf "$PLASMALOGIN_HOME/.local/share/color-schemes"' "uninstall must not remove the shared colour schemes directory"
    assert_contains "$(cat "$SYNC_SCRIPT")" 'color-schemes/Matugen*.colors' "the sync should copy only those schemes in the first place"

    # The same pair on the session user's side: the command generates those schemes, so
    # uninstall removes them and nothing else out of that directory.
    assert_contains "$(cat "$UNINSTALL_SCRIPT")" 'rm -f "$HOME/.local/share/color-schemes/Matugen"*.colors' "uninstall should remove the generated schemes from the user's own directory too"
}

test_the_breeze_login_wallpaper_is_patched_in_one_place() {
    # Breeze reads its background from its own theme.conf rather than from our theme, so
    # the KDE step patches it. Two branches need that - the one setting the default
    # wallpaper and the one leaving a user's own alone - and the guard plus sed used to
    # be written out in both. One helper keeps the packaged-install exemption consistent.
    local script
    script="$(cat "$KDE_SCRIPT")"

    assert_eq "1" "$(printf '%s\n' "$script" | grep -c '^patch_breeze_login_wallpaper() {')" "the patch should be defined once"
    assert_eq "1" "$(printf '%s\n' "$script" | grep -c 'background=$image')" "and should be the only thing that writes that background"
    assert_contains "$script" 'patch_breeze_login_wallpaper "$WALLPAPER_IN_USE"' "the branch that keeps the user's wallpaper should still match the logout screen to it"
    assert_contains "$script" 'patch_breeze_login_wallpaper "$WALLPAPER_PATH"' "and the default branch should match it to the wallpaper it sets"

    # Asserted where it now lives rather than repeated per call site.
    assert_contains "$script" 'if ! install_is_packaged &&' "the helper should skip a packaged install, where the theme is a package's file"
}

run_tests
