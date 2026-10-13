#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/virtual-desktops.sh"

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

ensure_five_virtual_desktops

UINPUT_RULE="/etc/udev/rules.d/70-uinput.rules"
LEGACY_UINPUT_RULE="/etc/udev/rules.d/80-uinput.rules"
UINPUT_RULE_LINE='KERNEL=="uinput", MODE="0600", OPTIONS+="static_node=uinput", TAG+="uaccess"'

uinput_rule_current() {
    [[ -f "$UINPUT_RULE" ]] && grep -q 'TAG+="uaccess"' "$UINPUT_RULE"
}

system_setup_needed() {
    install_is_packaged && return 1
    systemctl is-enabled --quiet keyd.service 2>/dev/null && return 0
    systemctl is-active --quiet keyd.service 2>/dev/null && return 0
    uinput_rule_current || return 0
    [[ ! -f "$LEGACY_UINPUT_RULE" ]] || return 0
    return 1
}

if ! system_setup_needed; then
    if install_is_packaged; then
        skip "System-level configuration belongs to the package."
    else
        skip "System-level configuration already in place."
    fi
else
echo "  Applying system-level configurations (requires root)..."
caelestia_sudo bash -s -- "$USER" "$UINPUT_RULE" "$LEGACY_UINPUT_RULE" "$UINPUT_RULE_LINE" << 'EOF'
TARGET_USER="$1"
UINPUT_RULE="$2"
LEGACY_UINPUT_RULE="$3"
UINPUT_RULE_LINE="$4"
RULE_CHANGED=""

if systemctl is-enabled --quiet keyd.service 2>/dev/null || \
   systemctl is-active --quiet keyd.service 2>/dev/null; then
    echo "  Disabling legacy keyd service..."
    systemctl disable --now keyd.service 2>/dev/null || true
fi

echo "  Setting up ydotoold (OSK key injection daemon)..."

if [ -f "$LEGACY_UINPUT_RULE" ]; then
    rm -f "$LEGACY_UINPUT_RULE"
    RULE_CHANGED=1
    if id -nG "$TARGET_USER" | grep -qw input; then
        if gpasswd -d "$TARGET_USER" input >/dev/null 2>&1; then
            echo "  Removed $TARGET_USER from the 'input' group (takes effect on next login)."
        else
            echo "  Could not remove $TARGET_USER from the 'input' group; run: sudo gpasswd -d $TARGET_USER input"
        fi
    fi
fi

if [ ! -f "$UINPUT_RULE" ]; then
    printf '%s\n' "$UINPUT_RULE_LINE" > "$UINPUT_RULE"
    RULE_CHANGED=1
    echo "  udev rule for uinput created (active session only, no group membership)."
fi

if [ -n "$RULE_CHANGED" ]; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --sysname-match=uinput 2>/dev/null || true
fi

if [ ! -e /dev/uinput ]; then
    echo "  /dev/uinput is not present yet; the on-screen keyboard needs it. Load it with: modprobe uinput"
fi
EOF
fi

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ydotoold-wrapper" << 'WRAPPER'
#!/bin/bash
# ydotoold-wrapper  starts ydotoold with uinput access (the active session gets it from the udev rule)
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
if systemctl --user start ydotoold.service 2>/dev/null; then
    ok "ydotoold started."
else
    info "ydotoold will start on next login."
fi
ok "ydotoold service configured."

configure_quick_share() {
    local bundle="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local setup="$bundle/shell/scripts/quickshare_setup.sh"
    local port_file="$bundle/shell/scripts/quickshare-port"
    local port status

    if install_is_packaged; then
        skip "Quick Share's setup is the shell's own prompt on a packaged install."
        return 0
    fi

    if [[ ! -f "$setup" ]]; then
        warn "Quick Share's setup helper is missing from $setup; it may not be able to receive."
        return 0
    fi

    if [[ ! -f "$port_file" ]]; then
        warn "Quick Share's transfer port is missing from $port_file; it may not be able to receive."
        return 0
    fi

    # The port the service listens on, read from the file the plugin build bakes it in
    # from: the rule below has to open the port the listener actually binds, and a second
    # copy of the number here is what would let the two drift apart.
    port="$(<"$port_file")"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        warn "Quick Share's transfer port in $port_file is not a port number; it may not be able to receive."
        return 0
    fi

    status="$(bash "$setup" --status --port "$port" 2>/dev/null || true)"
    if [[ "$status" != *"SETUP=needed"* ]]; then
        skip "Quick Share already has the access it needs."
        return 0
    fi

    if caelestia_sudo bash "$setup" --port "$port"; then
        ok "Quick Share can receive: Avahi is running and port $port is open."
    else
        warn "Quick Share setup did not finish; retry from Settings -> Services -> Quick Share."
    fi
}

configure_quick_share

ok "Services configured."
