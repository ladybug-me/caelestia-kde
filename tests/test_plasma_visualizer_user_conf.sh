#!/usr/bin/env bash
# suite: fast
#
# The user visualizer profile is stored in user.conf. The shell hides the
# widgets itself (moving them to [DisabledApplets]) whenever no player is
# playing, so "no live widgets" must not be mistaken for "the user removed them".

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VISUALIZER_SH="$REPO_ROOT/shell/scripts/plasma-config/scripts/visualizer.sh"
PLUGIN="luisbocanegra.audio.visualizer"
EMPTY_MARKER="# No visualizer widgets configured"

# Lays out a fake config home with a populated user.conf and a qdbus6 stub.
# $1: tmp dir, $2: applets section kind ("Applets", "DisabledApplets" or "none")
setup_env() {
    local tmp="$1" kind="$2"
    mkdir -p "$tmp/config/caelestia/plasma-audio-visualizer" "$tmp/bin"
    printf '[Applet_1]\ngeometry=0,672,848,400,0\nplugin=%s\n' "$PLUGIN" \
        > "$tmp/config/caelestia/plasma-audio-visualizer/user.conf"

    {
        printf '[Containments][1]\nplugin=org.kde.desktopcontainment\n\n'
        if [[ "$kind" != "none" ]]; then
            printf '[Containments][1][%s][5]\nimmutability=1\nplugin=%s\n\n' "$kind" "$PLUGIN"
            printf '[Containments][1][%s][5][Configuration][General]\nbarGap=10\n' "$kind"
        fi
    } > "$tmp/config/plasma-org.kde.plasma.desktop-appletsrc"

    printf '{}\n' > "$tmp/live.json"
    stub_bin "$tmp/bin" qdbus6 "case \"\$*\" in
    *evaluateScript*) [[ -f '$tmp/live-fail' ]] && exit 1; cat '$tmp/live.json' ;;
    *PlasmaShell.shell*) echo org.kde.plasma.desktop ;;
esac"
}

# Runs a visualizer.sh function against the fake environment.
run_visualizer() {
    local tmp="$1"
    shift
    (
        export PATH="$tmp/bin:$PATH"
        export USER_CONFIG_DIR="$tmp/config"
        export VISUALIZER_SNAPSHOT_FILE="$tmp/snapshot.json"
        source "$VISUALIZER_SH"
        "$@"
    )
}

write_snapshot_with_widget() {
    printf '[{"config": {"barGap": "10"}, "geom": [0, 672, 848, 400], "id": "5"}]\n' > "$1/snapshot.json"
}

test_save_user_config_keeps_widgets_hidden_by_shell() {
    local tmp
    tmp="$(new_tmpdir)"
    setup_env "$tmp" DisabledApplets

    run_visualizer "$tmp" save_user_visualizer_config

    assert_file_not_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "$EMPTY_MARKER" \
        "user.conf must survive while the shell keeps the widgets in [DisabledApplets]"
    assert_file_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "geometry=0,672,848,400,0" \
        "user.conf must keep the saved widget geometry"
}

test_save_user_config_still_clears_when_user_removed_widgets() {
    local tmp
    tmp="$(new_tmpdir)"
    setup_env "$tmp" none

    run_visualizer "$tmp" save_user_visualizer_config

    assert_file_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "$EMPTY_MARKER" \
        "user.conf must be cleared when no visualizer widget exists anywhere"
}

test_check_edit_mode_ignores_widgets_hidden_by_shell() {
    local tmp out
    tmp="$(new_tmpdir)"
    setup_env "$tmp" DisabledApplets
    write_snapshot_with_widget "$tmp"

    out="$(run_visualizer "$tmp" check_visualizer_edit_mode_changes)"

    assert_eq "STATUS_UNCHANGED" "$out" "hiding by the shell is not an edit-mode change"
    assert_file_not_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "$EMPTY_MARKER" \
        "user.conf must not be wiped when the shell hid the widgets during edit mode"
    assert_file_missing "$tmp/snapshot.json" "snapshot must be consumed"
}

test_check_edit_mode_still_saves_user_removal() {
    local tmp out
    tmp="$(new_tmpdir)"
    setup_env "$tmp" none
    write_snapshot_with_widget "$tmp"

    out="$(run_visualizer "$tmp" check_visualizer_edit_mode_changes)"

    assert_eq "STATUS_CHANGED" "$out" "removing every widget in edit mode is a change"
    assert_file_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "$EMPTY_MARKER" \
        "user.conf must record that the user removed the widgets"
}

test_check_edit_mode_unchanged_when_plasma_query_fails() {
    local tmp out
    tmp="$(new_tmpdir)"
    setup_env "$tmp" Applets
    write_snapshot_with_widget "$tmp"
    touch "$tmp/live-fail"

    out="$(run_visualizer "$tmp" check_visualizer_edit_mode_changes)"

    assert_eq "STATUS_UNCHANGED" "$out" "an unreadable Plasma state cannot prove a change"
    assert_file_not_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "$EMPTY_MARKER" \
        "user.conf must not be wiped when plasmashell cannot be queried"
}

test_check_edit_mode_saves_moved_widget() {
    local tmp out
    tmp="$(new_tmpdir)"
    setup_env "$tmp" Applets
    write_snapshot_with_widget "$tmp"
    printf '{"5": [100, 600, 848, 400]}\n' > "$tmp/live.json"

    out="$(run_visualizer "$tmp" check_visualizer_edit_mode_changes)"

    assert_eq "STATUS_CHANGED" "$out" "moving a widget in edit mode is a change"
    assert_file_contains "$tmp/config/caelestia/plasma-audio-visualizer/user.conf" "geometry=100,600,848,400,0" \
        "user.conf must record the new widget geometry"
}

run_tests
