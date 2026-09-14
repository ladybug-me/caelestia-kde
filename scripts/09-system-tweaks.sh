#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"

echo
echo ""
echo "  Caelestia  Live System Tweaks"
echo ""

tweak_disable_kde_osd() {
    info "Disabling KDE OSD popups (volume/brightness)..."

    kwriteconfig6 --file plasmarc --group "OSD" --key "Enabled" "false" 2>/dev/null || true
    kwriteconfig6 --file plasmarc --group "OSD" --key "ShowOnActiveScreen" "false" 2>/dev/null || true

    kwriteconfig6 --file kdeglobals --group "KDE" --key "OSDEnabled" "false" 2>/dev/null || true

    kwriteconfig6 --file plasmanotifyrc --group "Notifications" \
        --key "LoudnessChangedOSD" "false" 2>/dev/null || true

    kwriteconfig6 --file powerdevilrc --group "BrightnessControl" \
        --key "showOSD" "false" 2>/dev/null || true
    kwriteconfig6 --file powerdevilrc --group "AC" \
        --key "brightnessosd" "false" 2>/dev/null || true

    kwriteconfig6 --file kmixrc --group "Global" --key "ShowOSD" "false" 2>/dev/null || true

    ok "KDE OSD popups disabled."
}

tweak_five_desktops() {
    info "Configuring 5 virtual desktops..."

    kwriteconfig6 --file kwinrc --group "Desktops" --key "Number" "5"
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Rows" "1"
    for i in $(seq 1 5); do
        kwriteconfig6 --file kwinrc --group "Desktops" --key "Name_$i" "Desktop $i"
    done

    ok "5 virtual desktops configured."
}

tweak_remove_panels() {
    info "Removing KDE Plasma panels..."

    if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "var p = panels(); for (var i = 0; i < p.length; i++) { p[i].remove(); }" \
        2>/dev/null; then
        ok "KDE panels removed."
        return 0
    fi

    python3 - <<'EOF' || warn "Failed to remove KDE panels from config."
import os
import re

path = os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")
if not os.path.exists(path):
    raise SystemExit(0)

lines = open(path, "r", encoding="utf-8").read().splitlines()

panel_ids = set()
current = None
for line in lines:
    s = line.strip()
    m = re.match(r"^\[Containments\]\[(\d+)\]$", s)
    if m:
        current = m.group(1)
    elif s.startswith("[Containments][") and not re.match(r"^\[Containments\]\[\d+\]$", s):
        continue
    elif s.startswith("[") and s.endswith("]"):
        current = None
    elif current is not None and re.match(r"^(formfactor\s*=\s*[23]|plugin\s*=\s*org\.kde\.plasma\.panel)\s*$", s, re.IGNORECASE):
        panel_ids.add(current)

if not panel_ids:
    raise SystemExit(0)

out = []
skip = False
for line in lines:
    s = line.strip()
    m = re.match(r"^\[Containments\]\[(\d+)\]$", s)
    if m:
        skip = m.group(1) in panel_ids
        if skip:
            continue
    elif s.startswith("[Containments][") and not m:
        pass
    elif s.startswith("[") and s.endswith("]"):
        skip = False
    if skip:
        continue
    out.append(line)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(f"Removed {len(panel_ids)} KDE panel(s)")
EOF

    ok "KDE panels removed."
}

tweak_no_splash_screen() {
    info "Turning off the Plasma startup splash..."

    kwriteconfig6 --file ksplashrc --group KSplash --key Engine "none" 2>/dev/null || true

    ok "Plasma splash screen disabled."
}

tweak_reload_kde() {
    info "Reloading KWin and plasma-kglobalaccel..."
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    systemctl --user restart plasma-kglobalaccel.service 2>/dev/null || true
    ok "KDE daemons reloaded."
}

tweak_default_scheme() {
    info "Setting default Caelestia color scheme..."
    if command -v caelestia >/dev/null 2>&1; then
        STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
        CURRENT=""
        if [[ -s "$STATE_DIR/scheme.json" ]] && command -v python3 >/dev/null 2>&1; then
            CURRENT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name", ""))' "$STATE_DIR/scheme.json" 2>/dev/null || true)"
        fi
        if [[ -n "$CURRENT" && "$CURRENT" != "dynamic" ]]; then
            info "Keeping user-selected Caelestia color scheme ($CURRENT)."
            ok "Default Caelestia color scheme kept."
            return
        fi

        WALLPAPER="$(cat "$STATE_DIR/wallpaper/path.txt" 2>/dev/null || true)"
        if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]]; then
            timeout 10s caelestia wallpaper -f "$WALLPAPER" >/dev/null 2>&1 || true
        fi
        timeout 10s caelestia scheme set -n dynamic >/dev/null 2>&1 || true
    fi
    ok "Default Caelestia color scheme set."
}


tweak_default_shell() {
    local target_shell="${DEFAULT_SHELL:-fish}"
    info "Setting default shell to $target_shell..."

    if command -v "$target_shell" >/dev/null 2>&1; then
        local shell_path
        shell_path="$(command -v "$target_shell")"

        local current_shell
        current_shell="$(getent passwd "$USER" | cut -d: -f7)"
        if [[ -z "$current_shell" ]]; then
            current_shell="$SHELL"
        fi

        if [[ "$current_shell" == "$shell_path" ]]; then
            info "Shell is already set to $shell_path. Skipping chsh."
        else
            caelestia_sudo_quiet chsh -s "$shell_path" "$USER" 2>/dev/null || warn "Failed to change shell for $USER without prompting. You may need to run 'sudo chsh -s $shell_path $USER' manually."
        fi

        local konsole_profile_dir="$HOME/.local/share/konsole"
        mkdir -p "$konsole_profile_dir"

        local profiles_found=0
        for profile in "$konsole_profile_dir"/*.profile; do
            if [[ -f "$profile" ]]; then
                kwriteconfig6 --file "$profile" --group "General" --key "Command" "$shell_path"
                profiles_found=1
            fi
        done

        if [[ $profiles_found -eq 0 ]]; then
            kwriteconfig6 --file "$konsole_profile_dir/Profile 1.profile" --group "General" --key "Name" "Profile 1"
            kwriteconfig6 --file "$konsole_profile_dir/Profile 1.profile" --group "General" --key "Command" "$shell_path"
            kwriteconfig6 --file "$HOME/.config/konsolerc" --group "Desktop Entry" --key "DefaultProfile" "Profile 1.profile"
        fi
    else
        warn "$target_shell is not installed, skipping shell change."
    fi

    ok "Shell configuration applied."
}

tweak_user_avatar_symlinks() {
    if [[ -e "$HOME/.face.icon" || -L "$HOME/.face.icon" ]]; then
        # shellcheck disable=SC2088
        info "~/.face.icon already exists. Skipping avatar setup."
        return 0
    fi

    info "Setting up user profile picture symlinks..."

    local user_name="${USER:-$(id -un)}"
    local account_icon="/var/lib/AccountsService/icons/$user_name"

    if [[ -f "$account_icon" ]]; then
        ln -sf "$account_icon" "$HOME/.face"
        ln -sf "$account_icon" "$HOME/.face.icon"
        info "Linked $account_icon -> $HOME/.face"
        info "Linked $account_icon -> $HOME/.face.icon"
        ok "User profile picture symlinks configured."
    else
        info "No AccountsService avatar found at $account_icon. Skipping."
    fi
}

if [[ "${1:-}" == "--list" ]]; then
    echo
    echo "Available tweaks:"
    declare -F | awk '/^declare -f tweak_/ {print "  ", substr($3, 7)}' | sed 's/_/ /g'
    echo
    exit 0
fi

tweak_disable_kde_osd
tweak_five_desktops
tweak_remove_panels
tweak_no_splash_screen
tweak_default_shell
tweak_default_scheme
tweak_user_avatar_symlinks
tweak_reload_kde

echo
ok "All system tweaks applied."
echo
