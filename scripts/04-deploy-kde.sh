#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/js.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"

darkly_decoration_installed() {
    local plugin_dir
    plugin_dir="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
    [[ -n "$plugin_dir" && -f "$plugin_dir/org.kde.kdecoration3/org.kde.darkly.so" ]] ||
    [[ -f /usr/lib/qt6/plugins/org.kde.kdecoration3/org.kde.darkly.so ]] ||
    [[ -f /usr/local/lib/qt6/plugins/org.kde.kdecoration3/org.kde.darkly.so ]] ||
    [[ -f "${HOME}/.local/lib/qt6/plugins/org.kde.kdecoration3/org.kde.darkly.so" ]]
}

patch_breeze_login_wallpaper() {
    local image="$1"
    # No sudo check here: caelestia_sudo has its own escalation paths (askpass, pkexec),
    # and the edit is best-effort either way.
    if ! install_is_packaged &&
        [[ -f /usr/share/sddm/themes/breeze/theme.conf ]]; then
        caelestia_sudo sed -i "s|^background=.*|background=$image|" /usr/share/sddm/themes/breeze/theme.conf 2>/dev/null || true
    fi
}

echo
echo ""
info "Applying KDE settings"
echo ""

if [[ "${APPLY_DARKLY:-true}" == "true" ]]; then
    info "Applying Darkly plasma style..."
    kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

    if [[ -d "/usr/share/plasma/desktoptheme/darkly" ]]; then
        mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/desktoptheme"
        ln -sfn "/usr/share/plasma/desktoptheme/darkly" "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/desktoptheme/Darkly" 2>/dev/null || true
        ln -sfn "/usr/share/plasma/desktoptheme/darkly" "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/desktoptheme/darkly" 2>/dev/null || true
    fi

    info "Applying Darkly application style..."
    kwriteconfig6 --file kdeglobals --group "KDE" --key "widgetStyle" "darkly" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group "General" --key "ColorScheme" "Darkly" 2>/dev/null || true

    info "Applying Darkly window decoration..."
    if darkly_decoration_installed; then
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" \
            --key "library" "org.kde.darkly" 2>/dev/null || true
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" \
            --key "theme" "@darkly" 2>/dev/null || true
    else
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" \
            --key "library" "org.kde.breeze" 2>/dev/null || true
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" \
            --key "theme" "Breeze" 2>/dev/null || true
    fi

else
    skip "Skipping Darkly theme"
fi

if [[ "${APPLY_FONTS:-true}" == "true" ]]; then
    if command -v lookandfeeltool >/dev/null 2>&1; then
        if [[ "${APPLY_DARKLY:-true}" == "true" ]]; then
            if lookandfeeltool --list 2>/dev/null | grep -qi "^darkly$"; then
                info "Applying custom fonts and LNF via lookandfeeltool..."
                lookandfeeltool --apply "Darkly" 2>/dev/null || true
            fi
        else
            skip "Skipping Darkly LNF as Darkly theme was opted out. (Fonts must be applied manually)"
        fi
    fi
else
    skip "Skipping custom fonts application."
fi

info "Setting up cliphist background service..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/cliphist.service" << 'EOF'
[Unit]
Description=Clipboard history service
After=graphical-session.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'command -v wl-paste >/dev/null 2>&1 || { echo "missing: wl-paste" >&2; exit 1; }; command -v cliphist >/dev/null 2>&1 || { echo "missing: cliphist" >&2; exit 1; }; command -v wl-clip-persist >/dev/null 2>&1 || { echo "missing: wl-clip-persist" >&2; exit 1; }; wl-paste --type text --watch cliphist store & wl-paste --type image --watch cliphist store & wl-clip-persist --clipboard regular & wait -n'
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now cliphist.service 2>/dev/null || true
ok "Cliphist background service enabled."

ok "KDE settings applied."

if [[ -n "${CAELESTIA_WALLPAPERS_DIR:-}" ]]; then
    WALLS_DIR="$CAELESTIA_WALLPAPERS_DIR"
elif [[ -n "${XDG_PICTURES_DIR:-}" ]]; then
    WALLS_DIR="$XDG_PICTURES_DIR/Wallpapers"
elif command -v xdg-user-dir >/dev/null 2>&1 \
        && PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null)" \
        && [[ -n "$PICTURES_DIR" ]]; then
    WALLS_DIR="$PICTURES_DIR/Wallpapers"
else
    WALLS_DIR="$HOME/Pictures/Wallpapers"
fi
PACK_DEFAULT="$WALLS_DIR/dharmx-digital/a_couple_of_people_standing_on_a_mountain.png"
FALLBACK_PATH="$BUNDLE_DIR/shell/assets/wallpapers/Minimal-Paper.png"

if [[ -f "$PACK_DEFAULT" ]]; then
    WALLPAPER_PATH="$PACK_DEFAULT"
else
    WALLPAPER_PATH="$FALLBACK_PATH"
fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
WALLPAPER_IN_USE=""
if [[ -s "$STATE_DIR/wallpaper/path.txt" ]]; then
    WALLPAPER_IN_USE="$(cat "$STATE_DIR/wallpaper/path.txt" 2>/dev/null || true)"
fi

if [[ -n "$WALLPAPER_IN_USE" && -f "$WALLPAPER_IN_USE" ]]; then
    skip "Keeping the wallpaper in use: $(basename "$WALLPAPER_IN_USE")"

    if command -v qdbus6 >/dev/null 2>&1; then
        WALLPAPER_URL="$(js_string "file://$WALLPAPER_IN_USE")"
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            var allDesktops = desktops();
            for (i=0; i < allDesktops.length; i++) {
                d = allDesktops[i];
                d.wallpaperPlugin = 'org.kde.image';
                d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
                d.writeConfig('Image', '$WALLPAPER_URL');
            }
        " 2>/dev/null || true
    fi

    patch_breeze_login_wallpaper "$WALLPAPER_IN_USE"
elif [[ -f "$WALLPAPER_PATH" ]]; then
    info "Setting default wallpaper to $(basename "$WALLPAPER_PATH")..."
    WALLPAPER_URL="$(js_string "file://$WALLPAPER_PATH")"
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        var allDesktops = desktops();
        for (i=0; i < allDesktops.length; i++) {
            d = allDesktops[i];
            d.wallpaperPlugin = 'org.kde.image';
            d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
            d.writeConfig('Image', '$WALLPAPER_URL');
        }
    " 2>/dev/null || true
    mkdir -p "$STATE_DIR/wallpaper"
    echo "$WALLPAPER_PATH" > "$STATE_DIR/wallpaper/path.txt"

    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image" 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$WALLPAPER_PATH" 2>/dev/null || true
    fi

    patch_breeze_login_wallpaper "$WALLPAPER_PATH"
fi
