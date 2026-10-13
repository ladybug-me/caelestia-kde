#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNINSTALL_SCRIPT="$REPO_ROOT/uninstall.sh"

nopasswd_sudo_stub() {
    local dir="$1" log="$2"
    stub_bin "$dir" sudo "
printf 'sudo %s\n' \"\$*\" >> '$log'
args=()
for arg in \"\$@\"; do
    case \"\$arg\" in
        -n|-A|-S|-v|--non-interactive) ;;
        -*) ;;
        *) args+=(\"\$arg\") ;;
    esac
done
if [ \${#args[@]} -eq 0 ]; then
    for arg in \"\$@\"; do
        if [ \"\$arg\" = -v ]; then
            printf 'sudo: a password is required\n' >&2
            exit 1
        fi
    done
    exit 0
fi
exec \"\${args[@]}\""
    printf '%s\n' "$dir/sudo"
}

make_uninstall_sandbox() {
    local tmp="$1"
    local home="$tmp/home"
    local bin="$tmp/bin"
    mkdir -p \
        "$home/.config/quickshell/caelestia" \
        "$home/.config/caelestia" \
        "$home/.config/Caelestia" \
        "$home/.config/systemd/user" \
        "$home/.config/environment.d" \
        "$home/.config/plasma-workspace/env" \
        "$home/.local/bin" \
        "$home/.local/lib/caelestia" \
        "$home/.local/lib/qt6/qml/Caelestia" \
        "$home/.local/lib/qt6/qml/M3Shapes" \
        "$home/.local/share/caelestia" \
        "$home/.local/share/applications" \
        "$home/.local/share/kwin/scripts/quickshell-kde-bridge" \
        "$home/.cache/Caelestia/caelestia-shell" \
        "$home/.cache/caelestia-shell" \
        "$home/.local/state/caelestia" \
        "$bin"

    printf '{"bar":{}}\n' > "$home/.config/caelestia/shell.json"
    printf '[]\n'          > "$home/.config/caelestia/keybinds.json"
    printf '{}\n'          > "$home/.config/caelestia/cli.json"
    printf '{"kwin":{}}\n' > "$home/.config/caelestia/stolen-shortcuts.json"
    printf '{"edges":{}}\n' > "$home/.config/caelestia/stolen-screen-edges.json"
    printf '{}\n'          > "$home/.config/Caelestia/caelestia-shell.conf"
    printf 'cache\n'       > "$home/.cache/Caelestia/caelestia-shell/qmlcache"
    printf 'cache\n'       > "$home/.cache/caelestia-shell/qmlcache"
    printf '# user bashrc\nexport PATH=$HOME/.local/bin:$PATH\n' > "$home/.bashrc"
    printf '#!/bin/sh\n' > "$home/.local/bin/caelestia"
    printf '# caelestia\n' > "$home/.config/environment.d/caelestia.conf"
    printf '#!/bin/sh\n' > "$home/.config/plasma-workspace/env/caelestia.sh"
    printf '[Desktop Entry]\nX-KDE-Wayland-Interfaces=x\n' \
        > "$home/.local/share/applications/quickshell.desktop"

    local name
    for name in systemctl pkill kwriteconfig6 kreadconfig6 kpackagetool6 \
                qdbus6 qdbus kbuildsycoca6 update-desktop-database lookandfeeltool \
                gpasswd udevadm pgrep dnf apt-get yay pacman rpm dpkg \
                fc-cache update-mime-database xdg-desktop-menu; do
        stub_bin "$bin" "$name" 'exit 0'
    done
    recording_stub "$bin" chsh "$tmp/chsh.log"
    stub_bin "$bin" getent "printf 'camus:x:1000:1000::/home/camus:/usr/bin/fish\n'"
    nopasswd_sudo_stub "$bin" "$tmp/sudo.log" >/dev/null
    printf '%s\n' "$bin"
}

run_uninstall_in_sandbox() {
    local tmp="$1"
    local home="$tmp/home" bin="$tmp/bin"

    (
        cd "$REPO_ROOT" || exit 1
        printf 'y\nn\nn\nn\n' \
            | env -i \
                HOME="$home" \
                PATH="$bin:/usr/bin:/bin" \
                TMPDIR="$tmp" \
                CAELESTIA_SUDO_PRIMED=1 \
                CAELESTIA_SUDO_BIN="$bin/sudo" \
                bash "$UNINSTALL_SCRIPT" >"$tmp/uninstall.log" 2>&1
    )
    printf '%s\n' "$?"
}

test_the_uninstaller_removes_stranded_shortcut_recovery_files() {
    local tmp status home
    tmp="$(new_tmpdir)"
    make_uninstall_sandbox "$tmp" >/dev/null
    home="$tmp/home"

    status="$(run_uninstall_in_sandbox "$tmp")"

    assert_status 0 "$status" "a plain uninstall should complete"

    assert_file_missing "$home/.config/caelestia/stolen-shortcuts.json"
    assert_file_missing "$home/.config/caelestia/stolen-screen-edges.json"
    assert_file_exists "$home/.config/caelestia/shell.json"
    assert_file_exists "$home/.config/caelestia/keybinds.json"
    assert_file_missing "$home/.cache/Caelestia"
    assert_file_missing "$home/.cache/caelestia-shell"
    assert_file_missing "$home/.config/Caelestia"
}

test_the_uninstaller_leaves_the_login_shell_alone_without_a_backup() {
    local tmp status
    tmp="$(new_tmpdir)"
    make_uninstall_sandbox "$tmp" >/dev/null

    status="$(run_uninstall_in_sandbox "$tmp")"
    assert_status 0 "$status" "a plain uninstall should complete"

    assert_eq "" "$(calls_to "$tmp/chsh.log" chsh)" \
        "chsh must not run without a recorded previous shell"
}

test_the_uninstaller_removes_the_installed_footprint() {
    local tmp status home
    tmp="$(new_tmpdir)"
    make_uninstall_sandbox "$tmp" >/dev/null
    home="$tmp/home"

    status="$(run_uninstall_in_sandbox "$tmp")"
    assert_status 0 "$status" "a plain uninstall should complete"

    assert_file_missing "$home/.config/quickshell/caelestia"
    assert_file_missing "$home/.local/lib/caelestia"
    assert_file_missing "$home/.local/lib/qt6/qml/Caelestia"
    assert_file_missing "$home/.local/lib/qt6/qml/M3Shapes"
    assert_file_missing "$home/.local/share/caelestia"
    assert_file_missing "$home/.local/bin/caelestia"
    assert_file_missing "$home/.config/environment.d/caelestia.conf"
    assert_file_missing "$home/.config/plasma-workspace/env/caelestia.sh"
    assert_file_missing "$home/.local/share/kwin/scripts/quickshell-kde-bridge"
    assert_file_missing "$home/.local/state/caelestia"
}

test_the_uninstaller_keeps_shared_config_dirs_when_there_is_no_backup() {
    local tmp status home
    tmp="$(new_tmpdir)"
    make_uninstall_sandbox "$tmp" >/dev/null
    home="$tmp/home"

    # Configs the user keeps editing after install, with no backup to restore them
    # from: they must survive, or the uninstaller destroys unrelated work.
    mkdir -p "$home/.config/btop" "$home/.config/fish" "$home/.config/kitty"
    printf 'user customisation\n' > "$home/.config/btop/btop.conf"
    printf 'user fish config\n'   > "$home/.config/fish/config.fish"
    printf 'user kitty config\n'  > "$home/.config/kitty/kitty.conf"

    status="$(run_uninstall_in_sandbox "$tmp")"
    assert_status 0 "$status" "a plain uninstall should complete"

    assert_file_exists "$home/.config/btop/btop.conf"
    assert_file_exists "$home/.config/fish/config.fish"
    assert_file_exists "$home/.config/kitty/kitty.conf"
    assert_contains "$(cat "$home/.config/btop/btop.conf")" "user customisation" \
        "a shared config dir with no backup must keep the user's own files"
}

test_the_uninstaller_leaves_an_unrelated_qml_import_path_alone() {
    local tmp status home
    tmp="$(new_tmpdir)"
    make_uninstall_sandbox "$tmp" >/dev/null
    home="$tmp/home"

    # The same variable names, but one points somewhere that is not Caelestia and
    # one is Caelestia's own (the exact value 08-build-shell.sh writes). All three
    # shells must agree: drop ours, keep theirs.
    cat > "$home/.bashrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
export QML2_IMPORT_PATH=/opt/some-other-app/qml
export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia"
export CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
EOF
    cat > "$home/.zshrc" <<'EOF'
export QML2_IMPORT_PATH=/opt/some-other-app/qml
export CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
EOF
    mkdir -p "$home/.config/fish"
    cat > "$home/.config/fish/config.fish" <<'EOF'
set -gx QML2_IMPORT_PATH /opt/some-other-app/qml
set -gx QML2_IMPORT_PATH "$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia"
set -gx CAELESTIA_LIB_DIR "$HOME/.local/lib/caelestia"
set -gx EDITOR vim
EOF

    status="$(run_uninstall_in_sandbox "$tmp")"
    assert_status 0 "$status" "a plain uninstall should complete"

    local shell_file
    for shell_file in "$home/.bashrc" "$home/.zshrc" "$home/.config/fish/config.fish"; do
        assert_contains "$(cat "$shell_file")" "/opt/some-other-app/qml" \
            "$shell_file must keep a QML2_IMPORT_PATH that is not Caelestia's"
        assert_not_contains "$(cat "$shell_file")" "CAELESTIA_LIB_DIR" \
            "$shell_file must drop Caelestia's own env var"
        assert_not_contains "$(cat "$shell_file")" "config/quickshell/caelestia" \
            "$shell_file must drop Caelestia's own QML2_IMPORT_PATH value"
    done

    assert_contains "$(cat "$home/.bashrc")" "export PATH=" \
        "unrelated bashrc lines must survive"
    assert_contains "$(cat "$home/.config/fish/config.fish")" "EDITOR vim" \
        "unrelated fish lines must survive"
}

test_the_uninstaller_survives_an_unset_user_variable() {
    local tmp status home
    tmp="$(new_tmpdir)"
    make_uninstall_sandbox "$tmp" >/dev/null
    home="$tmp/home"

    # `set -u` turns an unset $USER into an abort. The sandbox runs with env -i,
    # so HOME/PATH are set but USER is not; the uninstaller must still finish.
    status="$(run_uninstall_in_sandbox "$tmp")"
    assert_status 0 "$status" "an uninstall without \$USER exported must complete"

    assert_file_missing "$home/.config/systemd/user/caelestia-update-checker.service"
    assert_not_contains "$(cat "$tmp/uninstall.log")" "unbound variable" \
        "no unbound-variable abort may appear in the run"
}

run_tests
