#!/usr/bin/env bash
# uninstall.sh - reverse setup.sh: restore backups, remove generated files.

set -uo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared log helpers: the [INFO]/[OK]/[WARN]/[SKIP]/[ERR] markers the installer TUI
# and every step script use.
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/log.sh"

section() {
    local title="$1"
    echo
    echo "-------------------------------------------------------------"
    echo "  $title"
    echo "-------------------------------------------------------------"
}

# OS detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        arch|cachyos|endeavouros|manjaro|artix) BASE_DISTRO="arch" ;;
        fedora|nobara|bazzite|rhel|centos|almalinux|rocky) BASE_DISTRO="fedora" ;;
        debian|ubuntu|pop|mint|kali|raspbian|elementary|zorin|deepin|devuan) BASE_DISTRO="debian" ;;
        *)
            if echo "${ID_LIKE:-}" | grep -iq "arch"; then BASE_DISTRO="arch"
            elif echo "${ID_LIKE:-}" | grep -iq "fedora"; then BASE_DISTRO="fedora"
            elif echo "${ID_LIKE:-}" | grep -iq -E "debian|ubuntu"; then BASE_DISTRO="debian"
            else BASE_DISTRO="unknown"; fi
            ;;
    esac
else
    BASE_DISTRO="unknown"
fi

if [[ "$BASE_DISTRO" == "unknown" ]]; then
    echo "Could not detect distribution. Select base:"
    echo "  1) Arch-based   2) Fedora-based   3) Debian-based   4) Exit"
    read -r -p "Choice [1-4]: " _dc
    case "$_dc" in
        1) BASE_DISTRO="arch" ;;
        2) BASE_DISTRO="fedora" ;;
        3) BASE_DISTRO="debian" ;;
        *) die "Exiting." ;;
    esac
fi

cat << 'EOF'
   _____            _           _   _
  / ____|          | |         | | (_)
 | |     __ _  ___ | | ___  ___| |_ _  __ _
 | |    / _` |/ _ \| |/ _ \/ __| __| |/ _` |
 | |___| (_| | (_) | |  __/\__ \ |_| | (_| |
  \_____\__,_|\___/|_|\___||___/\__|_|\__,_|
EOF
echo "+------------------------------------------------------------------+"
echo "|                       CAELESTIA UNINSTALLER                       |"
echo "+------------------------------------------------------------------+"
echo
echo " This will remove Caelestia shell files and configs."
echo " Backups in $BUNDLE_DIR/backups/ can be restored during uninstall."
echo

# Sudo setup
sudo -v || die "Failed to obtain sudo privileges."

# Keepalive loop
(while true; do sudo -v 2>/dev/null || break; sleep 55; done) 2>/dev/null &
_SUDO_LOOP=$!
trap 'kill $_SUDO_LOOP 2>/dev/null; true' EXIT

# Confirmation
echo
read -r -p "Are you sure you want to uninstall Caelestia? [y/N]: " _confirm
[[ "${_confirm,,}" == "y" || "${_confirm,,}" == "yes" ]] || die "Uninstall cancelled."

echo
echo "Remove installed packages as well? This will uninstall"
echo "tools like fish, foot, btop, fastfetch, and others."
read -r -p "Remove packages? [y/N]: " _remove_pkgs
REMOVE_PACKAGES=false
[[ "${_remove_pkgs,,}" == "y" || "${_remove_pkgs,,}" == "yes" ]] && REMOVE_PACKAGES=true

# Backup selection
SELECTED_BACKUP=""
SELECTED_KNSV=""
KONSAVE_BIN=""
THEME_RESTORED_FROM_BACKUP="false"
PREVIOUS_LOOKANDFEEL=""
SHELL_RC_RESTORED="false"

if [[ -d "$BUNDLE_DIR/backups" ]]; then
    mapfile -t backups < <(find "$BUNDLE_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*_[0-9]*' | sort -r)
    if [[ ${#backups[@]} -gt 0 ]]; then
        echo
        echo "Available backups to restore from:"
        for i in "${!backups[@]}"; do
            bdir="${backups[$i]}"
            bname="$(basename "$bdir")"
            formatted_date=$(echo "$bname" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

            tag=""
            knsv_file="$(find "$bdir" -maxdepth 1 -type f -name '*.knsv' | head -n 1)"
            if [[ -n "$knsv_file" ]]; then
                tag=" [konsave]"
            fi

            if [[ -f "$bdir/previous_shell.txt" ]]; then
                prev_shell="$(cat "$bdir/previous_shell.txt")"
                prev_shell_name="$(basename "$prev_shell")"
                tag="${tag} [Shell: ${prev_shell_name}]"
            fi

            echo "  $((i+1))) $formatted_date$tag"
        done
        echo "  0) None (Do not restore from backup)"

        while true; do
            read -r -p "Select a backup to restore [1]: " _bsel
            _bsel="${_bsel:-1}"
            if [[ "$_bsel" == "0" ]]; then
                SELECTED_BACKUP=""
                break
            elif [[ "$_bsel" -ge 1 ]] && [[ "$_bsel" -le "${#backups[@]}" ]]; then
                SELECTED_BACKUP="${backups[$((_bsel-1))]}"
                SELECTED_KNSV="$(find "$SELECTED_BACKUP" -maxdepth 1 -type f -name '*.knsv' | head -n 1)"
                if [[ -n "$SELECTED_KNSV" ]]; then
                    break
                fi

                if [[ -f "$SELECTED_BACKUP/.config/quickshell/caelestia/shell.qml" ]]; then
                    echo
                    warn "The selected backup contains Caelestia configurations."
                    echo "   Restoring this backup will NOT revert to a clean KDE desktop!"
                    echo "    Instead, it will restore a previous Caelestia state."
                    read -r -p "Are you sure you want to restore this backup? [y/N]: " _cwarn
                    if [[ "${_cwarn,,}" != "y" && "${_cwarn,,}" != "yes" ]]; then
                        echo "  Backup selection cancelled. Please select again."
                        continue
                    fi
                fi
                break
            else
                echo "Invalid selection."
            fi
        done
    fi
fi

if [[ -n "$SELECTED_BACKUP" ]] && [[ -f "$SELECTED_BACKUP/previous_lookandfeel.txt" ]]; then
    PREVIOUS_LOOKANDFEEL="$(cat "$SELECTED_BACKUP/previous_lookandfeel.txt")"
fi

ensure_konsave() {
    if command -v konsave >/dev/null 2>&1; then
        KONSAVE_BIN="$(command -v konsave)"
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi

    info "Installing konsave for KDE profile restore..."
    KONSAVE_VENV_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/konsave-venv"
    if [[ ! -x "$KONSAVE_VENV_DIR/bin/konsave" ]]; then
        python3 -m venv "$KONSAVE_VENV_DIR" >/dev/null 2>&1 || return 1
        "$KONSAVE_VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null 2>&1 || true
        "$KONSAVE_VENV_DIR/bin/python" -m pip install --upgrade konsave >/dev/null 2>&1 || return 1
    fi

    KONSAVE_BIN="$KONSAVE_VENV_DIR/bin/konsave"
    [[ -x "$KONSAVE_BIN" ]]
}

# restore config from a backup
restore_or_remove() {
    local name="$1"           # e.g. "fish"
    local target="$2"         # full destination path
    local backup_subdir="$3"  # "config" or "local"
    local backup_dir="$SELECTED_BACKUP"

    rm -rf "$target"

    if [[ -n "$backup_dir" ]] && [[ -e "$backup_dir/$backup_subdir/$name" ]]; then
        if cp -r "$backup_dir/$backup_subdir/$name" "$target"; then
            ok "Restored $name from backup"
        else
            warn "Failed to restore $name from backup - $target is now missing"
        fi
    else
        skip "No backup for $name - removed without restore"
    fi
}

section "Step 1 - Stop and Disable Services"

# kde-material-you-colors is listed for installs predating caelestia-color: it used to
# apply a scheme too, and whichever program ran last won.
for svc in qs-kwin-bridge cliphist ydotoold kde-material-you-colors; do
    if systemctl --user is-enabled --quiet "${svc}.service" 2>/dev/null ||
       systemctl --user is-active  --quiet "${svc}.service" 2>/dev/null; then
        systemctl --user disable --now "${svc}.service" 2>/dev/null || true
        ok "Disabled user service: $svc"
    else
        skip "User service not active: $svc"
    fi
done

if systemctl --user is-enabled --quiet "caelestia-update-checker.timer" 2>/dev/null ||
   systemctl --user is-active  --quiet "caelestia-update-checker.timer" 2>/dev/null; then
    systemctl --user disable --now "caelestia-update-checker.timer" 2>/dev/null || true
    systemctl --user disable --now "caelestia-update-checker.service" 2>/dev/null || true
    ok "Disabled user timer: caelestia-update-checker"
fi

# Stop and disable keyd (system service)
if systemctl is-enabled --quiet keyd 2>/dev/null ||
   systemctl is-active  --quiet keyd 2>/dev/null; then
    sudo systemctl disable --now keyd 2>/dev/null || true
    ok "Disabled system service: keyd"
else
    skip "keyd not active"
fi

# Kill any running Caelestia / Quickshell processes
pkill -f "caelestia shell" 2>/dev/null || true
pkill -f "quickshell"      2>/dev/null || true
ok "Stopped any running shell processes"

section "Step 2 - Remove Service and Autostart Files"

USER_SYSTEMD="$HOME/.config/systemd/user"

for svc_file in \
    "$USER_SYSTEMD/qs-kwin-bridge.service" \
    "$USER_SYSTEMD/cliphist.service" \
    "$USER_SYSTEMD/ydotoold.service" \
    "$USER_SYSTEMD/kde-material-you-colors.service" \
    "$USER_SYSTEMD/caelestia-update-checker.service" \
    "$USER_SYSTEMD/caelestia-update-checker.timer"
do
    if [[ -f "$svc_file" ]]; then
        rm -f "$svc_file"
        ok "Removed: $svc_file"
    fi
done

# The shell's systemd user unit, stopped and disabled by name rather than only when the
# user owns a copy: a package's unit lives in /usr/lib/systemd/user, but the enable link
# `systemctl --user enable` wrote is always in ~/.config/systemd/user. Left enabled it
# would keep starting a shell whose files the next step removes.
systemctl --user disable --now caelestia-shell.service >/dev/null 2>&1 || true
if [[ -f "$USER_SYSTEMD/caelestia-shell.service" ]]; then
    rm -f "$USER_SYSTEMD/caelestia-shell.service"
    ok "Removed: caelestia-shell.service"
fi

# That link, for the case where the unit's file is already gone: pacman removes
# /usr/lib/systemd/user/caelestia-shell.service first, and `disable` cannot clear a link
# whose unit it cannot resolve. A link with the unit's name is enough for systemd to count
# it as enabled, so drop the leftovers by hand, as 10-autostart.sh does on the way in.
for link in "$HOME"/.config/systemd/user/*.wants/caelestia-shell.service; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] && continue
    rm -f "$link"
    ok "Removed an enable link whose unit is gone: $link"
done

# Retired autostart desktop entry, and the unit KDE's xdg-autostart generator made of it.
if [[ -f "$HOME/.config/autostart/caelestiashell.desktop" ]]; then
    systemctl --user disable app-caelestiashell@autostart.service >/dev/null 2>&1 || true
    rm -f "$HOME/.config/autostart/caelestiashell.desktop"
    ok "Removed the retired autostart entry: caelestiashell.desktop"
fi

systemctl --user daemon-reload 2>/dev/null || true

section "Step 3 - Remove Shell Installation"

# Quickshell config (QML files)
if [[ -d "$HOME/.config/quickshell/caelestia" ]]; then
    rm -rf "$HOME/.config/quickshell/caelestia"
    ok "Removed ~/.config/quickshell/caelestia"
fi

# Native plugin library
if [[ -d "$HOME/.local/lib/caelestia" ]]; then
    rm -rf "$HOME/.local/lib/caelestia"
    ok "Removed ~/.local/lib/caelestia"
fi

# QML module tree (remove only caelestia-specific entries to be safe)
for qml_mod in Caelestia M3Shapes; do
    if [[ -d "$HOME/.local/lib/qt6/qml/$qml_mod" ]]; then
        rm -rf "$HOME/.local/lib/qt6/qml/$qml_mod"
        ok "Removed QML module: $qml_mod"
    fi
done

# Legacy share path
if [[ -d "$HOME/.local/share/caelestia-shell" ]]; then
    rm -rf "$HOME/.local/share/caelestia-shell"
    ok "Removed ~/.local/share/caelestia-shell"
fi

# Caelestia lockscreen shell package
if [[ -d "$HOME/.local/share/plasma/shells/caelestia.desktop" ]]; then
    rm -rf "$HOME/.local/share/plasma/shells/caelestia.desktop"
    ok "Removed ~/.local/share/plasma/shells/caelestia.desktop"
fi

# Plasma wallpaper application plugin
if command -v kpackagetool6 >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Wallpaper -r net.dosowisko.PlasmaApplicationWallpaper >/dev/null 2>&1 || true
fi
if [[ -d "$HOME/.local/share/plasma/wallpapers/net.dosowisko.PlasmaApplicationWallpaper" ]]; then
    rm -rf "$HOME/.local/share/plasma/wallpapers/net.dosowisko.PlasmaApplicationWallpaper"
    ok "Removed Plasma wallpaper plugin: net.dosowisko.PlasmaApplicationWallpaper"
fi
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/wallpaper-plugin-installed"

section "Step 4 - Remove Bridge Scripts"

for f in \
    "$HOME/.local/bin/kcolorpicker" \
    "$HOME/.local/bin/qs-kwin-bridge.py" \
    "$HOME/.local/bin/caelestia-shortcuts" \
    "$HOME/.local/bin/caelestia-record" \
    "$HOME/.local/bin/caelestia-keyd-run" \
    "$HOME/.local/bin/caelestia-shell-ipc" \
    "$HOME/.local/bin/ydotoold-wrapper" \
    "$HOME/.local/bin/caelestia-update" \
    "$HOME/.local/bin/caelestia-check-updates"
do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        ok "Removed: $f"
    fi
done

# KWin bridge script
if [[ -d "$HOME/.local/share/kwin/scripts/quickshell-kde-bridge" ]]; then
    rm -rf "$HOME/.local/share/kwin/scripts/quickshell-kde-bridge"
    ok "Removed KWin script: quickshell-kde-bridge"
fi


section "Step 5 - Restore or Remove Config Directories"

for cfg in btop fastfetch fish foot hypr kitty micro thunar; do
    if [[ -e "$HOME/.config/$cfg" ]]; then
        restore_or_remove "$cfg" "$HOME/.config/$cfg" ".config"
    fi
done

# starship.toml
if [[ -f "$HOME/.config/starship.toml" ]]; then
    restore_or_remove "starship.toml" "$HOME/.config/starship.toml" ".config"
fi

section "Step 6 - Revert KDE Settings"

# Re-enable KDE OSDs
kwriteconfig6 --file plasmarc         --group "OSD"              --key "Enabled"            "true"  2>/dev/null || true
kwriteconfig6 --file plasmarc         --group "OSD"              --key "ShowOnActiveScreen"  "true"  2>/dev/null || true
kwriteconfig6 --file kdeglobals       --group "KDE"              --key "OSDEnabled"          "true"  2>/dev/null || true
kwriteconfig6 --file plasmanotifyrc   --group "Notifications"    --key "LoudnessChangedOSD" "true"  2>/dev/null || true
kwriteconfig6 --file powerdevilrc     --group "BrightnessControl"--key "showOSD"            "true"  2>/dev/null || true
kwriteconfig6 --file powerdevilrc     --group "AC"               --key "brightnessosd"       "true"  2>/dev/null || true
# kmixrc is kmix's file and may hold settings that are not ours, so only the key the
# installer changed is put back; the file stays.
kwriteconfig6 --file kmixrc           --group "Global"           --key "ShowOSD"            "true"  2>/dev/null || true
ok "Re-enabled KDE OSD notifications"

# Restore KDE theme settings
if [[ -n "$SELECTED_KNSV" ]]; then
    if ensure_konsave; then
        info "Restoring KDE settings from konsave archive..."
        if "$KONSAVE_BIN" -i "$SELECTED_KNSV" >/dev/null 2>&1 && \
           "$KONSAVE_BIN" -a caelestia-preinstall >/dev/null 2>&1; then
            THEME_RESTORED_FROM_BACKUP="true"
            ok "Restored KDE settings from konsave backup."
        else
            warn "konsave restore failed, falling back to manual restore paths."
            SELECTED_KNSV=""
        fi
    else
        warn "konsave is unavailable, falling back to manual restore paths."
        SELECTED_KNSV=""
    fi
fi

if [[ -z "$SELECTED_KNSV" ]]; then
    MANUAL_KDE_RESTORE_COUNT=0
    if [[ -n "$SELECTED_BACKUP" ]]; then
        info "Restoring core KDE configuration files from backup..."
        for kde_cfg in kdeglobals ksplashrc plasmarc kwinrc kcminputrc plasma-org.kde.plasma.desktop-appletsrc; do
            if [[ -f "$SELECTED_BACKUP/.config/$kde_cfg" ]]; then
                if cp "$SELECTED_BACKUP/.config/$kde_cfg" "$HOME/.config/$kde_cfg"; then
                    ((MANUAL_KDE_RESTORE_COUNT++))
                fi
            fi
        done
        if (( MANUAL_KDE_RESTORE_COUNT > 0 )); then
            THEME_RESTORED_FROM_BACKUP="true"
            ok "Restored $MANUAL_KDE_RESTORE_COUNT core KDE configuration file(s) from backup (including wallpaper and splash when present)."
        else
            warn "Selected backup did not contain expected core KDE config files. Falling back to Breeze defaults."
        fi
    fi

    if [[ "$THEME_RESTORED_FROM_BACKUP" != "true" ]]; then
        info "No theme backup found. Reverting to default Breeze theme..."
        kwriteconfig6 --file plasmarc --group "Theme" --key "name" "default"  2>/dev/null || true
        kwriteconfig6 --file kdeglobals --group "KDE"     --key "widgetStyle"  "Breeze" 2>/dev/null || true
        kwriteconfig6 --file kdeglobals --group "General" --key "ColorScheme"  "BreezeLight" 2>/dev/null || true
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" --key "library" "org.kde.breeze" 2>/dev/null || true
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" --key "theme"   "@breeze"        2>/dev/null || true
        kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "breeze_cursors" 2>/dev/null || true
        ok "Reset KDE theme settings to Breeze."
    fi
fi

# Disable Caelestia's KWin plugins
kwriteconfig6 --file kwinrc --group "Plugins" --key "quickshell-kde-bridgeEnabled" "false" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled"             "false" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group "Plugins" --key "kwin_workspace_trackerEnabled" "false" 2>/dev/null || true
ok "Disabled KWin plugins: quickshell-kde-bridge, krohnkite, kwin_workspace_tracker"

# Restore the stock KDE lock screen: clear custom shell package and restore Breeze
kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" "org.kde.breeze.desktop" 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image" 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group net.dosowisko.PlasmaApplicationWallpaper --group General --key command --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group net.dosowisko.PlasmaApplicationWallpaper --group General --key fps --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key alwaysShowClock --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key showMediaControls --delete 2>/dev/null || true
ok "Restored stock KDE lock screen configuration."

# Restore desktop count to 1 (KDE default)
kwriteconfig6 --file kwinrc --group "Desktops" --key "Number" "1" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group "Desktops" --key "Rows"   "1" 2>/dev/null || true
for i in $(seq 1 5); do
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Name_$i" "Desktop $i" 2>/dev/null || true
done
ok "Restored desktop count to 1"

# Remove workspace shortcuts added by the installer
for i in $(seq 1 5); do
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" \
        --key "Switch to Desktop $i"  "none,none,Switch to Desktop $i"          2>/dev/null || true
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" \
        --key "Window to Desktop $i"  "none,none,Move Window to Desktop $i"     2>/dev/null || true
done
ok "Cleared installer workspace shortcuts from kglobalshortcutsrc"

# Restore backed-up kglobalshortcutsrc if available
_bk_dir="$SELECTED_BACKUP"
if [[ -n "$_bk_dir" ]] && [[ -f "$_bk_dir/.config/kglobalshortcutsrc" ]]; then
    cp "$_bk_dir/.config/kglobalshortcutsrc" "$HOME/.config/kglobalshortcutsrc"
    ok "Restored kglobalshortcutsrc from backup"
elif ls "$BUNDLE_DIR/backups/kglobalshortcutsrc_"* >/dev/null 2>&1; then
    _bk_file="$(ls -t "$BUNDLE_DIR/backups/kglobalshortcutsrc_"* 2>/dev/null | head -1)"
    if [[ -f "$_bk_file" ]]; then
        cp "$_bk_file" "$HOME/.config/kglobalshortcutsrc"
        ok "Restored kglobalshortcutsrc from $( basename "$_bk_file")"
    fi
fi

# Clean up generated Konsole profiles
rm -f "$HOME/.local/share/konsole/MaterialYou.colorscheme"
rm -f "$HOME/.local/share/konsole/MaterialYouAlt.colorscheme"
rm -f "$HOME/.local/share/konsole/TempMyou.profile"
rm -f "$HOME/.local/share/color-schemes/MaterialYou"*.colors
# The color command's output counts as generated too: it writes the palette under two
# names and rotates them, because plasma-apply-colorscheme ignores a name already in use.
rm -f "$HOME/.local/share/color-schemes/Matugen"*.colors
ok "Removed Konsole profiles generated by Caelestia"

# Remove Darkly GTK theme (installed via darkly-gtk) and desktop theme symlinks
_DARKLY_GTK_THEME="${XDG_DATA_HOME:-$HOME/.local/share}/themes/Darkly"
_GTK4_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0"
if [[ -d "$_DARKLY_GTK_THEME" ]]; then
    rm -rf "$_DARKLY_GTK_THEME"
    ok "Removed Darkly GTK theme"
fi
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/desktoptheme/Darkly" 2>/dev/null || true
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/desktoptheme/darkly" 2>/dev/null || true
if [[ -f "$_GTK4_DIR/gtk.css.created_by_darkly_installer.bak" ]]; then
    mv -f "$_GTK4_DIR/gtk.css.created_by_darkly_installer.bak" "$_GTK4_DIR/gtk.css"
fi
if [[ -f "$_GTK4_DIR/gtk-darkly.css" || -d "$_GTK4_DIR/darkly-gtk-assets" ]]; then
    rm -f "$_GTK4_DIR/gtk-darkly.css"
    rm -rf "$_GTK4_DIR/darkly-gtk-assets"
    ok "Removed Darkly GTK libadwaita files"
fi

# Restore Konsole config if backed up
if [[ -n "$_bk_dir" ]]; then
    if [[ -f "$_bk_dir/.config/konsolerc" ]]; then
        cp "$_bk_dir/.config/konsolerc" "$HOME/.config/konsolerc"
        ok "Restored konsolerc from backup"
    fi
    if [[ -d "$_bk_dir/local/konsole" ]]; then
        rm -rf "$HOME/.local/share/konsole"
        cp -r  "$_bk_dir/local/konsole" "$HOME/.local/share/konsole"
        ok "Restored ~/.local/share/konsole from backup"
    fi
fi

section "Step 7 - Revert Shell Changes"

restore_shell_rc() {
    local key="$1"
    local target="$2"
    local state_file="$SELECTED_BACKUP/shellrc/$key.state"
    local backup_file="$SELECTED_BACKUP/shellrc/$key"

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local state
    state="$(cat "$state_file" 2>/dev/null || true)"
    case "$state" in
        present)
            mkdir -p "$(dirname "$target")"
            if [[ -f "$backup_file" ]]; then
                cp "$backup_file" "$target"
                ok "Restored $target from backup"
                return 0
            fi
            ;;
        missing)
            rm -f "$target"
            ok "Removed $target (it did not exist before install)"
            return 0
            ;;
    esac

    return 1
}

if [[ -n "$SELECTED_BACKUP" ]]; then
    if restore_shell_rc "bashrc" "$HOME/.bashrc"; then
        SHELL_RC_RESTORED="true"
    fi
    if restore_shell_rc "zshrc" "$HOME/.zshrc"; then
        SHELL_RC_RESTORED="true"
    fi
    if restore_shell_rc "fish_config" "$HOME/.config/fish/config.fish"; then
        SHELL_RC_RESTORED="true"
    fi
fi

# Revert login shell
_RESTORE_SHELL=""
if [[ -n "$SELECTED_BACKUP" ]] && [[ -f "$SELECTED_BACKUP/previous_shell.txt" ]]; then
    _PREV_SHELL="$(cat "$SELECTED_BACKUP/previous_shell.txt")"
    if grep -x -q "$_PREV_SHELL" /etc/shells 2>/dev/null; then
        _RESTORE_SHELL="$_PREV_SHELL"
    else
        warn "Previous shell ($_PREV_SHELL) is not listed in /etc/shells. Falling back to bash."
    fi
fi

if [[ -z "$_RESTORE_SHELL" ]]; then
    if command -v bash >/dev/null 2>&1; then
        _RESTORE_SHELL="$(command -v bash)"
    else
        _RESTORE_SHELL="/bin/bash"
    fi
fi

if [[ -n "$_RESTORE_SHELL" ]]; then
    sudo chsh -s "$_RESTORE_SHELL" "$USER" 2>/dev/null || \
        warn "Could not change login shell to $_RESTORE_SHELL. Run: chsh -s $_RESTORE_SHELL"
    ok "Login shell reverted to $_RESTORE_SHELL"
fi

if [[ "$SHELL_RC_RESTORED" == "true" ]]; then
    info "Skipped shell rc line cleanup because original rc files were restored exactly from backup."
else
    # Legacy fallback for old backups without shellrc snapshots
    if [[ -f "$HOME/.bashrc" ]]; then
        sed -i '/export QML2_IMPORT_PATH=.*caelestia\|export CAELESTIA_LIB_DIR=/d' "$HOME/.bashrc" 2>/dev/null || true
        ok "Removed Caelestia env vars from ~/.bashrc"
    fi

    # The environment lives in environment.d now; the rc files are still cleaned
    # above for older installs.
    if [[ -f "$HOME/.config/environment.d/caelestia.conf" ]]; then
        rm -f "$HOME/.config/environment.d/caelestia.conf"
        ok "Removed the Caelestia environment file"
    fi

    if [[ -f "$HOME/.config/fish/config.fish" ]]; then
        sed -i '/QML2_IMPORT_PATH\|CAELESTIA_LIB_DIR/d' "$HOME/.config/fish/config.fish" 2>/dev/null || true
        ok "Removed Caelestia env vars from fish config"
    fi

    if [[ -f "$HOME/.zshrc" ]]; then
        sed -i '/QML2_IMPORT_PATH\|CAELESTIA_LIB_DIR/d' "$HOME/.zshrc" 2>/dev/null || true
        ok "Removed Caelestia env vars from ~/.zshrc"
    fi
fi

section "Step 8 - Remove System-level Files"

# keyd config
if [[ -f /etc/keyd/quickshell.conf ]]; then
    sudo rm -f /etc/keyd/quickshell.conf
    ok "Removed /etc/keyd/quickshell.conf"
    # Remove the directory only if it's now empty
    sudo rmdir /etc/keyd 2>/dev/null || true
fi

# udev rule for uinput
if [[ -f /etc/udev/rules.d/80-uinput.rules ]]; then
    sudo rm -f /etc/udev/rules.d/80-uinput.rules
    sudo udevadm control --reload-rules 2>/dev/null || true
    ok "Removed udev rule: 80-uinput.rules"
fi

# Revert the system-wide ccache flip made by 01-ensure-prereqs.sh, if we made it.
CCACHE_FLAG="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/ccache-enabled"
if [[ -f "$CCACHE_FLAG" ]] && [[ -f /etc/makepkg.conf ]]; then
    if sudo sed -i 's/\(^\|[[:space:]]\)ccache\([[:space:]]\|$\)/\1!ccache\2/' /etc/makepkg.conf; then
        rm -f "$CCACHE_FLAG"
        ok "Reverted ccache in /etc/makepkg.conf"
    else
        warn "Could not revert ccache in /etc/makepkg.conf; retaining ownership marker."
    fi
fi

# sudoers file for ydotoold
if [[ -f /etc/sudoers.d/ydotoold-nopasswd ]]; then
    sudo rm -f /etc/sudoers.d/ydotoold-nopasswd
    ok "Removed sudoers rule: ydotoold-nopasswd"
fi

# sudoers file for SDDM sync
if [[ -f /etc/sudoers.d/caelestia-sddm-sync ]]; then
    sudo rm -f /etc/sudoers.d/caelestia-sddm-sync
    ok "Removed sudoers rule: caelestia-sddm-sync"
fi

# SDDM theme and config
if [[ -d /usr/share/sddm/themes/caelestia ]]; then
    sudo rm -rf /usr/share/sddm/themes/caelestia
    ok "Removed SDDM theme: /usr/share/sddm/themes/caelestia"
fi
for dropin in /etc/sddm.conf.d/caelestia.conf /etc/sddm.conf.d/zz-caelestia.conf; do
    if [[ -f "$dropin" ]]; then
        sudo rm -f "$dropin"
        ok "Removed SDDM config drop-in: $(basename "$dropin")"
    fi
done
# The theme is named in /etc/sddm.conf too, because which of the two SDDM reads last
# differs between versions. 05-sddm-theme.sh saved whatever was there first, so the user's
# own selection (KDE's Login Screen settings writes the same key) comes back instead of
# being deleted with ours.
SDDM_CONF_BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/sddm.conf.theme-current"
if command -v kwriteconfig6 >/dev/null 2>&1; then
    if [[ -f "$SDDM_CONF_BACKUP" ]]; then
        PREVIOUS_CURRENT="$(cat "$SDDM_CONF_BACKUP")"
        if [[ "$PREVIOUS_CURRENT" == "#none" ]]; then
            sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current --delete 2>/dev/null || true
            ok "Removed the login screen theme selection from /etc/sddm.conf"
        else
            sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current "$PREVIOUS_CURRENT" 2>/dev/null || true
            ok "Restored the login screen theme in /etc/sddm.conf (${PREVIOUS_CURRENT})"
        fi
        rm -f "$SDDM_CONF_BACKUP"
    elif [[ "$(kreadconfig6 --file /etc/sddm.conf --group Theme --key Current 2>/dev/null || true)" == "caelestia" ]]; then
        # No saved value and the key is ours, so removing it is safe; anything else is
        # a selection this installer never saw.
        sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current --delete 2>/dev/null || true
        ok "Removed the login screen theme selection from /etc/sddm.conf"
    fi
fi

# Plasma Login, KDE's SDDM fork (Plasma 6.6+). Its greeter is a Plasma shell: it reads
# the wallpaper from /etc/plasmalogin.conf and its colours from the plasmalogin user's own
# Plasma config, both of which this installer copied in.
if [[ -f /usr/local/bin/caelestia-greeter-sync ]]; then
    sudo rm -f /usr/local/bin/caelestia-greeter-sync
    ok "Removed login screen sync helper: caelestia-greeter-sync"
fi
if [[ -f /etc/plasmalogin.conf ]] && command -v kwriteconfig6 >/dev/null 2>&1; then
    sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key Image --delete 2>/dev/null || true
    ok "Removed the login screen wallpaper from /etc/plasmalogin.conf"
fi
PLASMALOGIN_HOME="$(getent passwd plasmalogin | cut -d: -f6)"
if [[ -n "$PLASMALOGIN_HOME" && "$PLASMALOGIN_HOME" != "/" ]]; then
    # Only the directory the sync helper fills, never the shared wallpapers directory
    # around it: the pictures a user picked in KDE's Login Screen settings live there too.
    # Same for the colour schemes below, where only the copied-in files are named.
    if [[ -d "$PLASMALOGIN_HOME/wallpapers/caelestia" ]]; then
        sudo rm -rf "$PLASMALOGIN_HOME/wallpapers/caelestia"
        ok "Removed the login screen's copy of the wallpaper"
    fi
    for file in kdeglobals plasmarc kxkbrc kcminputrc plasma-localerc; do
        [[ -f "$PLASMALOGIN_HOME/.config/$file" ]] && sudo rm -f "$PLASMALOGIN_HOME/.config/$file"
    done
    if [[ -d "$PLASMALOGIN_HOME/.local/share/color-schemes" ]]; then
        sudo rm -f "$PLASMALOGIN_HOME/.local/share/color-schemes/Matugen"*.colors
        ok "Removed the login screen's copies of the colour schemes"
    fi
fi

# SDDM posthooks from cli.json
CLI_JSON="$HOME/.config/caelestia/cli.json"
if [[ -f "$CLI_JSON" ]] && command -v python3 &>/dev/null; then
    python3 - "$CLI_JSON" <<'PYEOF'
import json, sys, os, re
cli_path = sys.argv[1]
if not os.path.exists(cli_path):
    sys.exit(0)
with open(cli_path) as f:
    config = json.load(f)
changed = False
# Both helpers are ours, and an install that moved between display managers could have
# left either behind, so both spellings are recognised.
ours = re.compile(
    r'\s*&&\s*sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook'
    r'|sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook\s*&&\s*'
    r'|sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook'
)
for section in ("wallpaper", "theme"):
    hook = config.get(section, {}).get("postHook", "")
    if not hook:
        continue
    cleaned = ours.sub('', hook).strip()
    if cleaned != hook:
        changed = True
        if cleaned:
            config[section]["postHook"] = cleaned
        else:
            del config[section]["postHook"]
if changed:
    with open(cli_path, "w") as f:
        json.dump(config, f, indent=4)
PYEOF
    ok "Removed SDDM posthooks from cli.json"
fi

# SDDM template config
rm -f "$HOME/.config/caelestia/templates/sddm-theme.conf"

# Compatibility symlinks and manually installed binaries
for link in /usr/local/bin/sass /usr/local/bin/qdbus6 /usr/local/bin/caelestia /usr/local/bin/wl-clip-persist /usr/local/bin/gpu-screen-recorder; do
    if [[ -L "$link" || -f "$link" ]]; then
        sudo rm -f "$link"
        ok "Removed: $link"
    fi
done

# System-level KWin effect
for effect_lib in /usr/lib/qt6/plugins/kwin/effects/plugins/kwin_workspace_tracker.so /usr/lib64/qt6/plugins/kwin/effects/plugins/kwin_workspace_tracker.so; do
    if [[ -f "$effect_lib" ]]; then
        sudo rm -f "$effect_lib"
        ok "Removed system KWin effect: $effect_lib"
    fi
done

if [[ -f "$HOME/.cargo/bin/satty" ]]; then
    rm -f "$HOME/.cargo/bin/satty"
    ok "Removed: satty (cargo)"
fi

# Remove the user from the 'input' group if it was added by the installer
if groups "$USER" | grep -q '\binput\b'; then
    sudo gpasswd -d "$USER" input 2>/dev/null || \
        warn "Could not remove $USER from input group. Run: sudo gpasswd -d $USER input"
    ok "Removed $USER from 'input' group (takes effect on next login)"
fi

if [[ "$REMOVE_PACKAGES" == "true" ]]; then
    section "Step 9 - Remove Packages (Optional)"

    ARCH_PACKAGES=(
        quickshell matugen python
        cmake ninja
        wl-clipboard cliphist inotify-tools app2unit wireplumber trash-cli
        jq aubio lm_sensors libcava libqalculate
        foot fish eza fastfetch starship btop
        adw-gtk-theme papirus-icon-theme
        ttf-jetbrains-mono-nerd ttf-material-symbols-variable
        ttf-rubik-vf ttf-cascadia-code-nerd darkly darkly-bin
        swappy brightnessctl ddcutil imagemagick
        tesseract tesseract-data-eng satty spectacle sassc
        kvantum kvantum-qt5 kde-material-you-colors
        keyd
    )

    FEDORA_PACKAGES=(
        quickshell-git matugen
        cmake ninja-build
        wl-clipboard cliphist inotify-tools app2unit wireplumber trash-cli
        jq aubio lm_sensors lm_sensors-devel libcava libcava-devel libqalculate libqalculate-devel
        foot fish eza fastfetch starship btop
        adw-gtk3-theme google-rubik-fonts papirus-icon-theme darkly
        swappy brightnessctl ddcutil imagemagick
        tesseract tesseract-langpack-eng spectacle
        fuzzel satty slurp grim sassc
        ffmpeg gpu-screen-recorder
        qt6-qtdeclarative qt6-qtdeclarative-devel
        qt6-qtsvg qt6-qtsvg-devel qt6-qtshadertools-devel
        pipewire-devel aubio-devel
        dbus-devel dbus-glib-devel python3-devel
        kvantum kde-material-you-colors
        keyd
    )

    DEBIAN_PACKAGES=(
        cmake ninja-build ccache g++ build-essential
        wl-clipboard cliphist inotify-tools wireplumber trash-cli jq yq
        libaubio-dev aubio-tools lm-sensors libsensors-dev cava
        libpipewire-0.3-dev pipewire
        qt6-base-dev qt6-base-private-dev qt6-declarative-dev qml6-module-qtquick qt6-wayland qt6-wayland-dev qt6-svg-dev qt6-shadertools-dev
        libkf6globalaccel-dev libkf6windowsystem-dev libkf6kpipewire-dev libsecret-1-dev libkirigami-dev libkdecorations3-dev libkf6style-dev libkf6kcmutils-dev libkf6colorscheme-dev
        ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libqalculate-dev qalc
        foot fish eza fastfetch btop bash
        adw-gtk3-theme fonts-rubik papirus-icon-theme darkly
        fuzzel swappy brightnessctl ddcutil network-manager imagemagick
        tesseract-ocr tesseract-ocr-eng kde-spectacle slurp grim xdg-utils sassc
        libdbus-1-dev libdbus-glib-1-dev python3-dev
        qt6-style-kvantum kvantum quickshell
        libxi-dev libdrm-dev libx11-dev libxcomposite-dev libxdamage-dev libxrender-dev libxrandr-dev libpulse-dev libva-dev libcap-dev libavfilter-dev libvulkan-dev
    )

    if [[ "$BASE_DISTRO" == "arch" ]]; then
        warn "The following packages will be removed:"
        printf '  %s\n' "${ARCH_PACKAGES[@]}"
        echo
        read -r -p "Proceed? [y/N]: " _pkg_confirm
        if [[ "${_pkg_confirm,,}" == "y" || "${_pkg_confirm,,}" == "yes" ]]; then
            # Remove packages that are actually installed; ignore errors for missing ones
            mapfile -t _installed < <(yay -Qq "${ARCH_PACKAGES[@]}" 2>/dev/null)
            if [[ ${#_installed[@]} -gt 0 ]]; then
                yay -Rns --noconfirm "${_installed[@]}" 2>/dev/null || \
                    warn "Some packages could not be removed automatically. Check manually."
            fi
            ok "Arch packages removed"
        else
            skip "Package removal skipped"
        fi
    elif [[ "$BASE_DISTRO" == "fedora" ]]; then
        warn "The following packages will be removed:"
        printf '  %s\n' "${FEDORA_PACKAGES[@]}"
        echo
        read -r -p "Proceed? [y/N]: " _pkg_confirm
        if [[ "${_pkg_confirm,,}" == "y" || "${_pkg_confirm,,}" == "yes" ]]; then
            sudo dnf remove -y "${FEDORA_PACKAGES[@]}" 2>/dev/null || \
                warn "Some packages could not be removed. Check manually."
            ok "Fedora packages removed"
        else
            skip "Package removal skipped"
        fi
    elif [[ "$BASE_DISTRO" == "debian" ]]; then
        warn "The following packages will be removed:"
        printf '  %s\n' "${DEBIAN_PACKAGES[@]}"
        echo
        read -r -p "Proceed? [y/N]: " _pkg_confirm
        if [[ "${_pkg_confirm,,}" == "y" || "${_pkg_confirm,,}" == "yes" ]]; then
            sudo apt-get remove -y "${DEBIAN_PACKAGES[@]}" 2>/dev/null || \
                warn "Some packages could not be removed. Check manually."
            ok "Debian packages removed"
        else
            skip "Package removal skipped"
        fi
    fi

    # This port generates its own colors, so the upstream CLI is no longer a dependency -
    # but an earlier install of this port put it there and nothing else would clean it up.
    if command -v caelestia >/dev/null 2>&1 || python3 -m caelestia --help &>/dev/null 2>&1; then
        sudo pip3 uninstall -y caelestia 2>/dev/null || true
        pip3 uninstall -y caelestia 2>/dev/null || true
        ok "Removed caelestia pip package"
    fi

    # Remove uv-installed tools
    if command -v uv >/dev/null 2>&1; then
        uv tool uninstall kde-material-you-colors 2>/dev/null || true
        uv tool uninstall konsave 2>/dev/null || true
        ok "Removed uv tools: kde-material-you-colors, konsave"
    fi

    # Remove Krohnkite KWin script if installed
    if command -v kpackagetool6 >/dev/null 2>&1; then
        if kpackagetool6 -t KWin/Script -s krohnkite >/dev/null 2>&1; then
            kpackagetool6 -t KWin/Script -r krohnkite 2>/dev/null || true
            ok "Removed Krohnkite KWin script"
        fi
    fi
else
    skip "Package removal skipped (user chose to keep packages)"
fi

section "Step 10 - Clean Up Cache and Build Artifacts"

# CMake build dirs inside the repo
for build_dir in "$BUNDLE_DIR/shell/build" "$BUNDLE_DIR/shell/plugin/build"; do
    if [[ -d "$build_dir" ]]; then
        rm -rf "$build_dir"
        ok "Removed build dir: $build_dir"
    fi
done

# Installer cache
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
if [[ -d "$CACHE_DIR" ]]; then
    read -r -p "Remove installer cache at $CACHE_DIR? [y/N]: " _cache_confirm
    if [[ "${_cache_confirm,,}" == "y" || "${_cache_confirm,,}" == "yes" ]]; then
        rm -rf "$CACHE_DIR"
        ok "Removed installer cache"
    else
        skip "Kept installer cache at $CACHE_DIR"
    fi
fi

section "Step 11 - Reload KDE"

qdbus6 org.kde.KWin /KWin reconfigure                    2>/dev/null || true
systemctl --user restart plasma-kglobalaccel.service      2>/dev/null || true
kbuildsycoca6 --noincremental                             2>/dev/null || true

if command -v lookandfeeltool >/dev/null 2>&1; then
    if [[ -n "$PREVIOUS_LOOKANDFEEL" ]]; then
        info "Reapplying previous KDE look-and-feel: $PREVIOUS_LOOKANDFEEL"
        lookandfeeltool --apply "$PREVIOUS_LOOKANDFEEL" 2>/dev/null || \
            warn "Could not apply $PREVIOUS_LOOKANDFEEL with lookandfeeltool."
    elif [[ "$THEME_RESTORED_FROM_BACKUP" == "true" ]]; then
        info "Skipping Breeze look-and-feel apply because theme was restored from backup."
    else
        lookandfeeltool --apply "org.kde.breeze.desktop" 2>/dev/null || true
    fi
fi

ok "KDE reloaded"

section "Uninstall Complete"
echo
ok "Caelestia has been uninstalled."
echo
echo "  Backups of your original configs are in:  $BUNDLE_DIR/backups/"
echo
warn "Please log out and back in to fully apply all changes."
echo

# Prompt user for immediate logout (same behavior as setup finalizer)
read -r -p "Would you like to log out now? (y/N): " response
case "$response" in
    [yY][eE][sS]|[yY])
        echo "Logging out..."
        qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null
        ;;
    *)
        echo "Exiting script. Please remember to log out manually later."
        ;;
esac
