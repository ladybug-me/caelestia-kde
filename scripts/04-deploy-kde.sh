#!/usr/bin/env bash
# 04-deploy-kde.sh  Apply the KDE Plasma settings: Darkly theme, Kvantum, five
# virtual desktops, KDE OSDs off.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/js.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"

# True when a Darkly KWin decoration is actually installed and loadable.
darkly_decoration_installed() {
    local plugin_dir
    plugin_dir="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
    [[ -n "$plugin_dir" && -f "$plugin_dir/org.kde.kdecoration3/org.kde.darkly.so" ]] ||
    [[ -f /usr/lib/qt6/plugins/org.kde.kdecoration3/org.kde.darkly.so ]] ||
    [[ -f /usr/local/lib/qt6/plugins/org.kde.kdecoration3/org.kde.darkly.so ]] ||
    [[ -f "${HOME}/.local/lib/qt6/plugins/org.kde.kdecoration3/org.kde.darkly.so" ]]
}

# Point the Breeze login screen's background at an image.
#
# Only a machine running Breeze needs this: our SDDM theme uses its own files,
# while Breeze reads a package-owned theme.conf that only in-place editing can
# change. A package update may revert it until the next run; accepted.
#
# Quiet, and never on a packaged install: there this step owns the user's half
# only, and one caller is deliberately leaving the user's wallpaper alone.
patch_breeze_login_wallpaper() {
    local image="$1"
    if ! install_is_packaged &&
        [[ -f /usr/share/sddm/themes/breeze/theme.conf ]] &&
        command -v sudo >/dev/null 2>&1; then
        sudo sed -i "s|^background=.*|background=$image|" /usr/share/sddm/themes/breeze/theme.conf 2>/dev/null || true
    fi
}

echo
echo ""
info "Applying KDE settings"
echo ""

if [[ "${APPLY_DARKLY:-true}" == "true" ]]; then
    info "Applying Darkly plasma style..."
    kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

    # Symlink both cases so the desktop theme resolves however it is spelled.
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
        # kwriteconfig6 cannot tell whether a decoration is loadable, so fall
        # back to Breeze when Darkly is not installed.
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" \
            --key "library" "org.kde.breeze" 2>/dev/null || true
        kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" \
            --key "theme" "Breeze" 2>/dev/null || true
    fi

else
    skip "Skipping Darkly theme"
fi

# Darkly LNF (which also carries the fonts) through lookandfeeltool.
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

# Default wallpaper: the dharmx "digital" pack from 03a-wallpapers.sh when
# present, otherwise the bundled fallback, so a fresh install always has one.
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
# Set the default only while nothing is in use yet. 09-system-tweaks.sh guards
# its default scheme the same way: this runs again on every install and repair,
# and a wallpaper the user picked is not ours to replace.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
WALLPAPER_IN_USE=""
if [[ -s "$STATE_DIR/wallpaper/path.txt" ]]; then
    WALLPAPER_IN_USE="$(cat "$STATE_DIR/wallpaper/path.txt" 2>/dev/null || true)"
fi

if [[ -n "$WALLPAPER_IN_USE" && -f "$WALLPAPER_IN_USE" ]]; then
    # The shell keeps kscreenlockerrc in step from here on, so leaving both alone
    # keeps them equal. A stale pointer falls through to the default below rather
    # than leaving the desktop and lock screen with no wallpaper.
    skip "Keeping the wallpaper in use: $(basename "$WALLPAPER_IN_USE")"

    # Plasma's own desktop must hold the same picture too: it is what is on
    # screen while the shell starts, so leaving it on the distribution default
    # looks like the wallpaper changing a second into the session.
    #
    # The path goes in as a JS string literal, not pasted between quotes: a name
    # with an apostrophe would end the literal early and the desktop would keep the
    # old picture while this reported success. lib/js.sh escapes it; Wallpapers.qml
    # feeds the same value to the same API through JSON.stringify.
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

    # The logout screen is not a wallpaper choice of its own, so it follows
    # whatever is in use, including here.
    patch_breeze_login_wallpaper "$WALLPAPER_IN_USE"
elif [[ -f "$WALLPAPER_PATH" ]]; then
    info "Setting default wallpaper to $(basename "$WALLPAPER_PATH")..."
    # Escaped the same way as above.
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
    # In the state dir the shell actually reads.
    mkdir -p "$STATE_DIR/wallpaper"
    echo "$WALLPAPER_PATH" > "$STATE_DIR/wallpaper/path.txt"

    # Mirror it onto the KDE lock screen so both match out of the box.
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image" 2>/dev/null || true
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$WALLPAPER_PATH" 2>/dev/null || true
    fi

    # And onto the SDDM login screen, so the logout screen matches.
    patch_breeze_login_wallpaper "$WALLPAPER_PATH"
fi
