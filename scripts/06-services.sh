#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"

echo
echo ""
info "Configuring services and KWin"
echo ""

if systemctl --user is-enabled --quiet qs-kwin-bridge.service 2>/dev/null || \
   systemctl --user is-active --quiet qs-kwin-bridge.service 2>/dev/null; then
    echo "  Disabling legacy qs-kwin-bridge service..."
    systemctl --user disable --now qs-kwin-bridge.service 2>/dev/null || true
fi

echo "  Clearing legacy KWin workspace shortcuts to avoid QML conflicts..."
for i in $(seq 1 10); do
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "Switch to Desktop $i" "none,none,Switch to Desktop $i"
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "Window to Desktop $i" "none,none,Move Window to Desktop $i"
done

echo "  Disabling legacy quickshell-kde-bridge KWin script..."
kwriteconfig6 --file kwinrc --group "Plugins" --key "quickshell-kde-bridgeEnabled" "false"

echo "  Setting default KWin virtual desktops to 5 (only if not already configured)..."
EXISTING_DESKTOPS="$(kreadconfig6 --file kwinrc --group "Desktops" --key "Number" 2>/dev/null || true)"
if [ -z "$EXISTING_DESKTOPS" ]; then
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Number" "5"
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Rows" "1"
    for i in $(seq 1 5); do
        kwriteconfig6 --file kwinrc --group "Desktops" --key "Name_$i" "Desktop $i"
    done
else
    echo "  Existing virtual desktop configuration found - leaving it untouched."
fi

system_setup_needed() {
    install_is_packaged && return 1
    systemctl is-enabled --quiet keyd.service 2>/dev/null && return 0
    systemctl is-active --quiet keyd.service 2>/dev/null && return 0
    [[ -f /etc/udev/rules.d/80-uinput.rules ]] || return 0
    groups "$USER" | grep -q '\binput\b' || return 0
    if [[ -e /dev/uinput ]]; then
        [[ "$(stat -c '%a' /dev/uinput 2>/dev/null)" == *660 ]] || return 0
        [[ "$(stat -c '%G' /dev/uinput 2>/dev/null)" == "input" ]] || return 0
    fi
    return 1
}

if ! system_setup_needed; then
    if install_is_packaged; then
        skip "System-level configuration belongs to the package."
        if ! groups "$USER" | grep -q '\binput\b'; then
            info "For the on-screen keyboard, add yourself to the 'input' group: sudo usermod -aG input $USER"
        fi
    else
        skip "System-level configuration already in place."
    fi
else
echo "  Applying system-level configurations (requires root)..."
caelestia_sudo bash -s -- "$USER" << 'EOF'
TARGET_USER="$1"

if systemctl is-enabled --quiet keyd.service 2>/dev/null || \
   systemctl is-active --quiet keyd.service 2>/dev/null; then
    echo "  Disabling legacy keyd service..."
    systemctl disable --now keyd.service 2>/dev/null || true
fi

echo "  Setting up ydotoold (OSK key injection daemon)..."

if [[ ! -f /etc/udev/rules.d/80-uinput.rules ]]; then
    echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' > /etc/udev/rules.d/80-uinput.rules
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    ok "udev rule for uinput created."
fi

if ! groups "$TARGET_USER" | grep -q '\binput\b'; then
    usermod -aG input "$TARGET_USER"
    ok "Added $TARGET_USER to 'input' group (takes effect on next login)."
else
    ok "$TARGET_USER already in 'input' group."
fi

if [[ -e /dev/uinput ]]; then
    UINPUT_PERMS=$(stat -c "%a" /dev/uinput 2>/dev/null)
    UINPUT_GROUP=$(stat -c "%G" /dev/uinput 2>/dev/null)
    if [[ "$UINPUT_PERMS" != *"660" ]] || [[ "$UINPUT_GROUP" != "input" ]]; then
        chmod 660 /dev/uinput 2>/dev/null || true
        chgrp input /dev/uinput 2>/dev/null || true
    fi
fi
EOF
fi

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ydotoold-wrapper" << 'WRAPPER'
#!/bin/bash
# ydotoold-wrapper  starts ydotoold with uinput access (user is in 'input' group)
SOCKET="${YDOTOOL_SOCKET:-/run/user/$(id -u)/.ydotool_socket}"
if [ -S "$SOCKET" ] && pidof ydotoold > /dev/null 2>&1; then
    exit 0
fi
exec /usr/bin/ydotoold \
    --socket-path="$SOCKET" \
    --socket-perm=0660
WRAPPER
chmod +x "$HOME/.local/bin/ydotoold-wrapper"
ok "ydotoold-wrapper deployed to ~/.local/bin."

mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/ydotoold.service" << 'UNIT'
[Unit]
Description=ydotoold key injection daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/ydotoold-wrapper
Restart=on-failure
Environment=YDOTOOL_SOCKET=/run/user/%U/.ydotool_socket

[Install]
WantedBy=graphical-session.target
UNIT
systemctl --user daemon-reload
systemctl --user enable ydotoold.service 2>/dev/null || true
if id -nG | grep -q '\binput\b'; then
    systemctl --user start ydotoold.service 2>/dev/null || \
        info "ydotoold will start on next login."
else
    info "ydotoold starts on next login (input group takes effect then)."
fi
ok "ydotoold service configured."

ok "Services configured."
