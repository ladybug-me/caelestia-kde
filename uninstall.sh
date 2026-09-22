#!/usr/bin/env bash

set -uo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/scripts/lib"

source "$LIB_DIR/log.sh"
# shellcheck source=scripts/lib/packages.sh
source "$LIB_DIR/packages.sh"
# shellcheck source=scripts/lib/privileges.sh
source "$LIB_DIR/privileges.sh"

section() {
    local title="$1"
    echo
    echo "-------------------------------------------------------------"
    echo "  $title"
    echo "-------------------------------------------------------------"
}

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

caelestia_prime_sudo || die "Failed to obtain sudo privileges."
trap 'caelestia_stop_sudo_keepalive; true' EXIT

echo
read -r -p "Are you sure you want to uninstall Caelestia? [y/N]: " _confirm
[[ "${_confirm,,}" == "y" || "${_confirm,,}" == "yes" ]] || die "Uninstall cancelled."

echo
echo "Remove installed packages as well? This will uninstall"
echo "tools like foot, btop, fastfetch, and others."
read -r -p "Remove packages? [y/N]: " _remove_pkgs
REMOVE_PACKAGES=false
[[ "${_remove_pkgs,,}" == "y" || "${_remove_pkgs,,}" == "yes" ]] && REMOVE_PACKAGES=true

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

if systemctl is-enabled --quiet keyd 2>/dev/null ||
   systemctl is-active  --quiet keyd 2>/dev/null; then
    caelestia_sudo systemctl disable --now keyd 2>/dev/null || true
    ok "Disabled system service: keyd"
else
    skip "keyd not active"
fi

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

systemctl --user disable --now caelestia-shell.service >/dev/null 2>&1 || true
if [[ -f "$USER_SYSTEMD/caelestia-shell.service" ]]; then
    rm -f "$USER_SYSTEMD/caelestia-shell.service"
    ok "Removed: caelestia-shell.service"
fi

for link in "$HOME"/.config/systemd/user/*.wants/caelestia-shell.service; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] && continue
    rm -f "$link"
    ok "Removed an enable link whose unit is gone: $link"
done

if [[ -f "$HOME/.config/autostart/caelestiashell.desktop" ]]; then
    systemctl --user disable app-caelestiashell@autostart.service >/dev/null 2>&1 || true
    rm -f "$HOME/.config/autostart/caelestiashell.desktop"
    ok "Removed the retired autostart entry: caelestiashell.desktop"
fi

systemctl --user daemon-reload 2>/dev/null || true

section "Step 3 - Remove Shell Installation"

if [[ -d "$HOME/.config/quickshell/caelestia" ]]; then
    rm -rf "$HOME/.config/quickshell/caelestia"
    ok "Removed ~/.config/quickshell/caelestia"
fi

if [[ -d "$HOME/.local/lib/caelestia" ]]; then
    rm -rf "$HOME/.local/lib/caelestia"
    ok "Removed ~/.local/lib/caelestia"
fi

for qml_mod in Caelestia M3Shapes; do
    if [[ -d "$HOME/.local/lib/qt6/qml/$qml_mod" ]]; then
        rm -rf "$HOME/.local/lib/qt6/qml/$qml_mod"
        ok "Removed QML module: $qml_mod"
    fi
done

if [[ -d "$HOME/.local/share/caelestia-shell" ]]; then
    rm -rf "$HOME/.local/share/caelestia-shell"
    ok "Removed ~/.local/share/caelestia-shell"
fi

if [[ -d "$HOME/.local/share/plasma/shells/caelestia.desktop" ]]; then
    rm -rf "$HOME/.local/share/plasma/shells/caelestia.desktop"
    ok "Removed ~/.local/share/plasma/shells/caelestia.desktop"
fi

if command -v kpackagetool6 >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Wallpaper -r net.dosowisko.PlasmaApplicationWallpaper >/dev/null 2>&1 || true
fi
if [[ -d "$HOME/.local/share/plasma/wallpapers/net.dosowisko.PlasmaApplicationWallpaper" ]]; then
    rm -rf "$HOME/.local/share/plasma/wallpapers/net.dosowisko.PlasmaApplicationWallpaper"
    ok "Removed Plasma wallpaper plugin: net.dosowisko.PlasmaApplicationWallpaper"
fi
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/wallpaper-plugin-installed"

section "Step 4 - Remove Bridge Scripts"

# Derived from src/bin, which is what 03-deploy-configs.sh and 08-build-shell.sh copy into
# ~/.local/bin: a hand-written list here has already drifted from theirs twice.
for source_file in "$BUNDLE_DIR"/src/bin/*; do
    [[ -f "$source_file" ]] || continue
    bin_target="$HOME/.local/bin/$(basename -- "$source_file")"
    if [[ -f "$bin_target" ]]; then
        rm -f "$bin_target"
        ok "Removed: $bin_target"
    fi
done

# Names no version installs any more.
for name in kcolorpicker qs-kwin-bridge.py caelestia-shortcuts caelestia-keyd-run ydotoold-wrapper caelestia-autostart.sh; do
    bin_target="$HOME/.local/bin/$name"
    if [[ -f "$bin_target" ]]; then
        rm -f "$bin_target"
        ok "Removed: $bin_target"
    fi
done

if [[ -d "$HOME/.local/share/kwin/scripts/quickshell-kde-bridge" ]]; then
    rm -rf "$HOME/.local/share/kwin/scripts/quickshell-kde-bridge"
    ok "Removed KWin script: quickshell-kde-bridge"
fi


section "Step 5 - Restore or Remove Config Directories"

# hypr is deliberately absent: nothing here deploys ~/.config/hypr any more (compare the
# deploy and backup lists in 03-deploy-configs.sh), so removing it deleted a Hyprland
# user's own configuration with no backup to restore it from.
for cfg in btop fastfetch fish foot kitty micro thunar; do
    if [[ -e "$HOME/.config/$cfg" ]]; then
        restore_or_remove "$cfg" "$HOME/.config/$cfg" ".config"
    fi
done

if [[ -f "$HOME/.config/starship.toml" ]]; then
    restore_or_remove "starship.toml" "$HOME/.config/starship.toml" ".config"
fi

section "Step 6 - Revert KDE Settings"

kwriteconfig6 --file plasmarc         --group "OSD"              --key "Enabled"            "true"  2>/dev/null || true
kwriteconfig6 --file plasmarc         --group "OSD"              --key "ShowOnActiveScreen"  "true"  2>/dev/null || true
kwriteconfig6 --file kdeglobals       --group "KDE"              --key "OSDEnabled"          "true"  2>/dev/null || true
kwriteconfig6 --file plasmanotifyrc   --group "Notifications"    --key "LoudnessChangedOSD" "true"  2>/dev/null || true
kwriteconfig6 --file powerdevilrc     --group "BrightnessControl"--key "showOSD"            "true"  2>/dev/null || true
kwriteconfig6 --file powerdevilrc     --group "AC"               --key "brightnessosd"       "true"  2>/dev/null || true
kwriteconfig6 --file kmixrc           --group "Global"           --key "ShowOSD"            "true"  2>/dev/null || true
ok "Re-enabled KDE OSD notifications"

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
        # kwinrulesrc belongs in this list because 00-backup-themes.sh saves it with
        # the other KDE configuration files, so the fallback has to put it back.
        for kde_cfg in \
            kdeglobals ksplashrc plasmarc kwinrc kwinrulesrc kcminputrc \
            plasma-org.kde.plasma.desktop-appletsrc; do
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

kwriteconfig6 --file kwinrc --group "Plugins" --key "quickshell-kde-bridgeEnabled" "false" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled"             "false" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group "Plugins" --key "kwin_workspace_trackerEnabled" "false" 2>/dev/null || true
ok "Disabled KWin plugins: quickshell-kde-bridge, krohnkite, kwin_workspace_tracker"

# The three rule groups the installer writes are removed one key at a time. The
# list is explicit rather than a file-wide reset because kwinrulesrc also holds the
# user's own rules, and kwriteconfig6 can only delete a key, never a whole group.
# A group leaves the file once no keys are left in it. scripts/04a-window-rules.sh
# owns this key list: changing one means changing the other.
kwriteconfig6 --file kwinrulesrc --group "caelestia-opacity" --key "Description"         --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-opacity" --key "types"               --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-opacity" --key "opacityinactive"     --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-opacity" --key "opacityinactiverule" --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-dialogs" --key "Description"         --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-dialogs" --key "types"               --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-dialogs" --key "placement"           --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-dialogs" --key "placementrule"       --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-pip"     --key "Description"         --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-pip"     --key "title"               --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-pip"     --key "titlematch"          --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-pip"     --key "above"               --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "caelestia-pip"     --key "aboverule"           --delete 2>/dev/null || true

# [General] rules= is the index of the rule groups: KWin loads the groups that list
# names and nothing else, so our names have to leave it as well, or the file keeps
# an index entry for three groups that are no longer there. The user's own names are
# kept, in their order, and count= is rewritten to the number that is left. Both
# keys go only once no name is left, which is the shape the file had before the
# install. scripts/04a-window-rules.sh owns this index: changing one means changing
# the other.
KEPT_RULE_NAMES=()
KEPT_RULE_COUNT=0
while IFS= read -r rule_name; do
    rule_name="${rule_name#"${rule_name%%[![:space:]]*}"}"
    rule_name="${rule_name%"${rule_name##*[![:space:]]}"}"
    [[ -n "$rule_name" ]] || continue
    case "$rule_name" in
        caelestia-opacity|caelestia-dialogs|caelestia-pip) continue ;;
    esac
    KEPT_RULE_NAMES+=("$rule_name")
    KEPT_RULE_COUNT=$((KEPT_RULE_COUNT + 1))
done <<< "$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null | tr ',' '\n' || true)"

if (( KEPT_RULE_COUNT > 0 )); then
    KEPT_RULE_LIST="$(IFS=,; printf '%s' "${KEPT_RULE_NAMES[*]}")"
    kwriteconfig6 --file kwinrulesrc --group General --key rules "$KEPT_RULE_LIST" 2>/dev/null || true
    kwriteconfig6 --file kwinrulesrc --group General --key count "$KEPT_RULE_COUNT" 2>/dev/null || true
else
    kwriteconfig6 --file kwinrulesrc --group General --key rules --delete 2>/dev/null || true
    kwriteconfig6 --file kwinrulesrc --group General --key count --delete 2>/dev/null || true
fi
ok "Removed the Caelestia window rules from kwinrulesrc"

kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" "org.kde.breeze.desktop" 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image" 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group net.dosowisko.PlasmaApplicationWallpaper --group General --key command --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group net.dosowisko.PlasmaApplicationWallpaper --group General --key fps --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key alwaysShowClock --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key showMediaControls --delete 2>/dev/null || true
ok "Restored stock KDE lock screen configuration."

kwriteconfig6 --file kwinrc --group "Desktops" --key "Number" "1" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group "Desktops" --key "Rows"   "1" 2>/dev/null || true
for i in $(seq 1 5); do
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Name_$i" "Desktop $i" 2>/dev/null || true
done
ok "Restored desktop count to 1"

for i in $(seq 1 5); do
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" \
        --key "Switch to Desktop $i"  "none,none,Switch to Desktop $i"          2>/dev/null || true
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" \
        --key "Window to Desktop $i"  "none,none,Move Window to Desktop $i"     2>/dev/null || true
done
ok "Cleared installer workspace shortcuts from kglobalshortcutsrc"

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

rm -f "$HOME/.local/share/konsole/MaterialYou.colorscheme"
rm -f "$HOME/.local/share/konsole/MaterialYouAlt.colorscheme"
rm -f "$HOME/.local/share/konsole/TempMyou.profile"
rm -f "$HOME/.local/share/color-schemes/MaterialYou"*.colors
rm -f "$HOME/.local/share/color-schemes/Matugen"*.colors
ok "Removed Konsole profiles generated by Caelestia"

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
    caelestia_sudo chsh -s "$_RESTORE_SHELL" "$USER" 2>/dev/null || \
        warn "Could not change login shell to $_RESTORE_SHELL. Run: chsh -s $_RESTORE_SHELL"
    ok "Login shell reverted to $_RESTORE_SHELL"
fi

if [[ "$SHELL_RC_RESTORED" == "true" ]]; then
    info "Skipped shell rc line cleanup because original rc files were restored exactly from backup."
else
    if [[ -f "$HOME/.bashrc" ]]; then
        sed -i '/export QML2_IMPORT_PATH=.*caelestia\|export CAELESTIA_LIB_DIR=/d' "$HOME/.bashrc" 2>/dev/null || true
        ok "Removed Caelestia env vars from ~/.bashrc"
    fi

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

if [[ -f /etc/keyd/quickshell.conf ]]; then
    caelestia_sudo rm -f /etc/keyd/quickshell.conf
    ok "Removed /etc/keyd/quickshell.conf"
    caelestia_sudo rmdir /etc/keyd 2>/dev/null || true
fi

if [[ -f /etc/udev/rules.d/80-uinput.rules ]]; then
    caelestia_sudo rm -f /etc/udev/rules.d/80-uinput.rules
    caelestia_sudo udevadm control --reload-rules 2>/dev/null || true
    ok "Removed udev rule: 80-uinput.rules"
fi

CCACHE_FLAG="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/ccache-enabled"
if [[ -f "$CCACHE_FLAG" ]] && [[ -f /etc/makepkg.conf ]]; then
    if caelestia_sudo sed -i 's/\(^\|[[:space:]]\)ccache\([[:space:]]\|$\)/\1!ccache\2/' /etc/makepkg.conf; then
        rm -f "$CCACHE_FLAG"
        ok "Reverted ccache in /etc/makepkg.conf"
    else
        warn "Could not revert ccache in /etc/makepkg.conf; retaining ownership marker."
    fi
fi

if [[ -f /etc/sudoers.d/ydotoold-nopasswd ]]; then
    caelestia_sudo rm -f /etc/sudoers.d/ydotoold-nopasswd
    ok "Removed sudoers rule: ydotoold-nopasswd"
fi

if [[ -f /etc/sudoers.d/caelestia-sddm-sync ]]; then
    caelestia_sudo rm -f /etc/sudoers.d/caelestia-sddm-sync
    ok "Removed sudoers rule: caelestia-sddm-sync"
fi

if [[ -d /usr/share/sddm/themes/caelestia ]]; then
    caelestia_sudo rm -rf /usr/share/sddm/themes/caelestia
    ok "Removed SDDM theme: /usr/share/sddm/themes/caelestia"
fi
for dropin in /etc/sddm.conf.d/caelestia.conf /etc/sddm.conf.d/zz-caelestia.conf; do
    if [[ -f "$dropin" ]]; then
        caelestia_sudo rm -f "$dropin"
        ok "Removed SDDM config drop-in: $(basename "$dropin")"
    fi
done
SDDM_CONF_BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/sddm.conf.theme-current"
if command -v kwriteconfig6 >/dev/null 2>&1; then
    if [[ -f "$SDDM_CONF_BACKUP" ]]; then
        PREVIOUS_CURRENT="$(cat "$SDDM_CONF_BACKUP")"
        if [[ "$PREVIOUS_CURRENT" == "#none" ]]; then
            caelestia_sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current --delete 2>/dev/null || true
            ok "Removed the login screen theme selection from /etc/sddm.conf"
        else
            caelestia_sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current "$PREVIOUS_CURRENT" 2>/dev/null || true
            ok "Restored the login screen theme in /etc/sddm.conf (${PREVIOUS_CURRENT})"
        fi
        rm -f "$SDDM_CONF_BACKUP"
    elif [[ "$(kreadconfig6 --file /etc/sddm.conf --group Theme --key Current 2>/dev/null || true)" == "caelestia" ]]; then
        caelestia_sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current --delete 2>/dev/null || true
        ok "Removed the login screen theme selection from /etc/sddm.conf"
    fi
fi

if [[ -f /usr/local/bin/caelestia-greeter-sync ]]; then
    caelestia_sudo rm -f /usr/local/bin/caelestia-greeter-sync
    ok "Removed login screen sync helper: caelestia-greeter-sync"
fi
if [[ -f /etc/plasmalogin.conf ]] && command -v kwriteconfig6 >/dev/null 2>&1; then
    caelestia_sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key Image --delete 2>/dev/null || true
    ok "Removed the login screen wallpaper from /etc/plasmalogin.conf"
fi
PLASMALOGIN_HOME="$(getent passwd plasmalogin | cut -d: -f6)"
if [[ -n "$PLASMALOGIN_HOME" && "$PLASMALOGIN_HOME" != "/" ]]; then
    if [[ -d "$PLASMALOGIN_HOME/wallpapers/caelestia" ]]; then
        caelestia_sudo rm -rf "$PLASMALOGIN_HOME/wallpapers/caelestia"
        ok "Removed the login screen's copy of the wallpaper"
    fi
    for file in kdeglobals plasmarc kxkbrc kcminputrc plasma-localerc; do
        [[ -f "$PLASMALOGIN_HOME/.config/$file" ]] && caelestia_sudo rm -f "$PLASMALOGIN_HOME/.config/$file"
    done
    if [[ -d "$PLASMALOGIN_HOME/.local/share/color-schemes" ]]; then
        caelestia_sudo rm -f "$PLASMALOGIN_HOME/.local/share/color-schemes/Matugen"*.colors
        ok "Removed the login screen's copies of the colour schemes"
    fi
fi

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

rm -f "$HOME/.config/caelestia/templates/sddm-theme.conf"

for link in /usr/local/bin/sass /usr/local/bin/qdbus6 /usr/local/bin/caelestia /usr/local/bin/wl-clip-persist /usr/local/bin/gpu-screen-recorder; do
    if [[ -L "$link" || -f "$link" ]]; then
        caelestia_sudo rm -f "$link"
        ok "Removed: $link"
    fi
done

for effect_lib in /usr/lib/qt6/plugins/kwin/effects/plugins/kwin_workspace_tracker.so /usr/lib64/qt6/plugins/kwin/effects/plugins/kwin_workspace_tracker.so; do
    if [[ -f "$effect_lib" ]]; then
        caelestia_sudo rm -f "$effect_lib"
        ok "Removed system KWin effect: $effect_lib"
    fi
done

if [[ -f "$HOME/.cargo/bin/satty" ]]; then
    rm -f "$HOME/.cargo/bin/satty"
    ok "Removed: satty (cargo)"
fi

if groups "$USER" | grep -q '\binput\b'; then
    caelestia_sudo gpasswd -d "$USER" input 2>/dev/null || \
        warn "Could not remove $USER from input group. Run: sudo gpasswd -d $USER input"
    ok "Removed $USER from 'input' group (takes effect on next login)"
fi

if [[ "$REMOVE_PACKAGES" == "true" ]]; then
    section "Step 9 - Remove Packages (Optional)"

    # Only user-level utilities, standalone apps, custom fonts, and shell tools.
    # NEVER include core libraries, development headers, compiler toolchains,
    # desktop environment services, or base system components (e.g. pipewire,
    # networkmanager, qt6-*, kf6-*, cmake, python, bash).
    # fish is absent on purpose even though the installer offers it: it may be the
    # user's login shell, and removing it locks them out of the machine.
    ARCH_PACKAGES=(
        quickshell matugen
        foot eza fastfetch starship btop
        fuzzel swappy satty gpu-screen-recorder slurp grim
        wl-clipboard cliphist wl-clip-persist app2unit libcava
        brightnessctl ddcutil tesseract tesseract-data-eng
        bat ripgrep lazygit jq trash-cli inotify-tools
        imagemagick sassc xdg-utils xdg-user-dirs spectacle
        adw-gtk-theme papirus-icon-theme darkly darkly-bin
        ttf-jetbrains-mono-nerd ttf-material-symbols-variable
        ttf-rubik-vf ttf-cascadia-code-nerd
    )

    FEDORA_PACKAGES=(
        quickshell-git matugen
        foot eza fastfetch starship btop
        fuzzel swappy satty gpu-screen-recorder gpu-screen-recorder-ui slurp grim
        wl-clipboard cliphist wl-clip-persist app2unit libcava libcava-devel
        brightnessctl ddcutil tesseract tesseract-langpack-eng
        bat ripgrep jq trash-cli inotify-tools
        ImageMagick sassc xdg-utils xdg-user-dirs spectacle
        adw-gtk3-theme papirus-icon-theme darkly
        google-rubik-fonts
    )

    DEBIAN_PACKAGES=(
        quickshell matugen
        foot eza fastfetch starship btop
        fuzzel swappy satty gpu-screen-recorder slurp grim
        wl-clipboard cliphist wl-clip-persist app2unit cava libcava
        brightnessctl ddcutil tesseract-ocr tesseract-ocr-eng
        jq yq trash-cli inotify-tools
        imagemagick sassc xdg-utils kde-spectacle
        adw-gtk3 adw-gtk3-theme papirus-icon-theme darkly
    )

    # One flow for all three: the distro only decides which list to walk and which
    # remover to call. What is not installed is filtered out first, because a single
    # unknown name makes dnf and apt refuse the whole batch.
    case "$BASE_DISTRO" in
        arch)
            _pkg_list=("${ARCH_PACKAGES[@]}")
            _remove_cmd=(yay -Rns --noconfirm)
            ;;
        fedora)
            _pkg_list=("${FEDORA_PACKAGES[@]}")
            _remove_cmd=(caelestia_sudo dnf remove -y)
            ;;
        debian)
            _pkg_list=("${DEBIAN_PACKAGES[@]}")
            _remove_cmd=(caelestia_sudo apt-get remove -y)
            ;;
        *)
            _pkg_list=()
            _remove_cmd=()
            ;;
    esac

    if [[ ${#_pkg_list[@]} -gt 0 ]]; then
        warn "The following packages will be removed:"
        printf '  %s\n' "${_pkg_list[@]}"
        echo
        read -r -p "Proceed? [y/N]: " _pkg_confirm
        if [[ "${_pkg_confirm,,}" == "y" || "${_pkg_confirm,,}" == "yes" ]]; then
            mapfile -t _installed < <(filter_installed "${_pkg_list[@]}")
            if [[ ${#_installed[@]} -gt 0 ]]; then
                "${_remove_cmd[@]}" "${_installed[@]}" 2>/dev/null || \
                    warn "Some packages could not be removed automatically. Check manually."
                ok "$BASE_DISTRO packages removed"
            else
                skip "None of the listed packages are installed"
            fi
        else
            skip "Package removal skipped"
        fi
    fi

    if command -v caelestia >/dev/null 2>&1 || python3 -m caelestia --help &>/dev/null 2>&1; then
        caelestia_sudo pip3 uninstall -y caelestia 2>/dev/null || true
        pip3 uninstall -y caelestia 2>/dev/null || true
        ok "Removed caelestia pip package"
    fi

    if command -v uv >/dev/null 2>&1; then
        uv tool uninstall kde-material-you-colors 2>/dev/null || true
        uv tool uninstall konsave 2>/dev/null || true
        ok "Removed uv tools: kde-material-you-colors, konsave"
    fi

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

for build_dir in "$BUNDLE_DIR/shell/build" "$BUNDLE_DIR/shell/plugin/build"; do
    if [[ -d "$build_dir" ]]; then
        rm -rf "$build_dir"
        ok "Removed build dir: $build_dir"
    fi
done

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

# KWin does not watch kwinrulesrc, so this reload is what applies the rule deletions
# made in Step 6. The call needs the exact bus name KWin owns, org.kde.KWin.
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
