#!/usr/bin/env bash
# 10-autostart.sh  Write the autostart entry that starts the shell. Idempotent.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"

# Same resolution as the build script, so this works whether the installer exports
# BUNDLE_DIR or the script is run directly.
BUNDLE_DIR="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
mkdir -p "$HOME/.local/bin"

echo
echo ""
info "Setting up autostart entries"
echo ""

# The tree the shell runs from and what the session needs to find it. From
# install-kind.sh, which 08-build-shell.sh also writes into environment.d: one definition,
# so this cannot name a tree the install did not put there.
SHELL_CONFIG="$(install_shell_config)"
QML_IMPORT_PATH="$(install_qml_import_path)"
LIB_DIR="$(install_lib_dir)"
BIN_DIR="$(install_bin_dir)"

# Absolute path so PATH differences at login cannot bite. Both kinds need it: the
# wrapper runs it, and the KWin declaration further down names it for screencasting.
if command -v quickshell >/dev/null 2>&1; then
    QUICKSHELL_PATH="$(command -v quickshell)"
elif command -v qs >/dev/null 2>&1; then
    QUICKSHELL_PATH="$(command -v qs)"
elif [ -x "/usr/bin/quickshell" ]; then
    QUICKSHELL_PATH="/usr/bin/quickshell"
elif [ -x "/usr/local/bin/quickshell" ]; then
    QUICKSHELL_PATH="/usr/local/bin/quickshell"
else
    die "Quickshell is not installed or is not available in PATH."
fi

# The launcher and the unit that starts it.
#
# A package ships both (/usr/bin/caelestia-autostart, the unit under
# /usr/lib/systemd/user), and those are the ones to use: owning them is what makes
# `pacman -R` clean, with nothing left enabled pointing at a gone tree. This step used to
# write the user's own copies, which survived the package and then failed five times over.
#
# A checkout has no package to own them, so it generates them around its own tree.
if install_is_packaged; then
    # A user copy shadows the package's, since a unit in ~/.config wins over /usr/lib.
    # An earlier version of this port wrote one, so take it back out.
    if [[ -f "$HOME/.config/systemd/user/caelestia-shell.service" ]]; then
        rm -f "$HOME/.config/systemd/user/caelestia-shell.service"
        info "Removed the user's copy of the shell unit; the package's is the one to use."
    fi
    if [[ -f "$HOME/.local/bin/caelestia-autostart.sh" ]]; then
        rm -f "$HOME/.local/bin/caelestia-autostart.sh"
        info "Removed the user's copy of the shell launcher; the package's is the one to use."
    fi
else
    if [[ ! -f "$SHELL_CONFIG" ]]; then
        die "Caelestia Shell entrypoint not found: $SHELL_CONFIG (run scripts/08-build-shell.sh first)"
    fi

    # Launch the shell this install produced directly, not through a wrapper that would
    # have to guess where it ended up.
    echo "  Creating Caelestia Shell autostart entry..."
    cat > "$HOME/.local/bin/caelestia-autostart.sh" << EOF
#!/bin/bash
# Where this install's files are. environment.d carries the same values for a
# session; they are repeated because the unit can start this outside one.
#
# The command the shell and its widgets call by name must be on PATH for everything
# this spawns: 08-build-shell.sh installs it into ~/.local/bin, which a session started
# by the display manager does not necessarily have on PATH.
export PATH="$BIN_DIR:\$PATH"
export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
export CAELESTIA_LIB_DIR="$LIB_DIR"
export CAELESTIA_BIN_DIR="$BIN_DIR"
export CAELESTIA_SHELL_CONFIG="$SHELL_CONFIG"
export QS_NO_RELOAD_POPUP=1
export QS_DROP_EXPENSIVE_FONTS=1
export QS_DISABLE_CRASH_HANDLER=1
export QSG_RENDER_LOOP=threaded
export QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
# Self-heal Caelestia lock screen if KDE updates or kconf_update reset it
if [ -f "\$HOME/.local/share/plasma/shells/caelestia.desktop/contents/lockscreen/LockScreen.qml" ] || [ -f "/usr/share/plasma/shells/caelestia.desktop/contents/lockscreen/LockScreen.qml" ]; then
    if command -v kreadconfig6 >/dev/null 2>&1 && command -v kwriteconfig6 >/dev/null 2>&1; then
        current_shell="\$(kreadconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" 2>/dev/null || true)"
        if [ "\$current_shell" != "caelestia.desktop" ]; then
            kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop" 2>/dev/null || true
        fi
        kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" --delete 2>/dev/null || true
    fi
fi
# No --daemonize: the unit supervises this process and sends its stdout/stderr to
# the journal. Detaching would replace that with /dev/null, and every app launched
# from the shell inherits those descriptors - which is how the shell was handing
# apps a stdout that goes nowhere. Vesktop deadlocks in exactly that state when a
# call starts (issue #402); reproducible outside the shell with
# \`vesktop >/dev/null 2>&1\`.
#
# It also makes the old stdbuf wrapper unnecessary: journald stdio is what the
# line-buffering hack worked around, and stdbuf leaked LD_PRELOAD=libstdbuf.so into
# every launched app besides.
exec "$QUICKSHELL_PATH" -n -p "$SHELL_CONFIG"
EOF
    chmod +x "$HOME/.local/bin/caelestia-autostart.sh"

    # One mechanism starts the shell: this unit, which replaced the desktop entry this
    # script used to write (KDE's xdg-autostart generator turned that into
    # app-caelestiashell@autostart.service).
    #
    # The ordering still matters: the shell registers org.freedesktop.Notifications, and
    # an app decides once at start whether a server exists - one that finds none draws its
    # own popups for the rest of the session. Before=xdg-desktop-autostart.target puts this
    # in front of the app units that generator creates. (A no-op without the target, which
    # is worse than the old phase but never wrong.)
    echo "  Creating the Caelestia Shell unit..."
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/caelestia-shell.service" << EOF
[Unit]
Description=Caelestia Shell
PartOf=graphical-session.target
After=graphical-session.target
Before=xdg-desktop-autostart.target

[Service]
Type=exec
ExecStart=%h/.local/bin/caelestia-autostart.sh
# A shell that cannot start is retried, but not in a tight loop: systemd gives up on
# a unit that starts five times in ten seconds, and clearing that state falls to an
# install. Upstream's unit waits the same five seconds between attempts.
Restart=on-failure
RestartSec=5s
TimeoutStopSec=5s
Slice=session.slice

[Install]
WantedBy=graphical-session.target
EOF
fi

# Take the older mechanisms back out. The entry is ours, so removing it is safe; the
# generated unit is disabled too, or it would keep starting a shell from the same wrapper.
if [[ -f "$AUTOSTART_DIR/caelestiashell.desktop" ]]; then
    rm -f "$AUTOSTART_DIR/caelestiashell.desktop"
    systemctl --user disable app-caelestiashell@autostart.service >/dev/null 2>&1 || true
    info "Removed the retired autostart entry; the shell's unit replaced it."
fi

# A repairing install may be repairing this too: a unit that failed to start repeatedly
# is refused by systemd with "Start request repeated too quickly" until it is reset, and
# that is what an uninstall leaves behind - the unit still enabled, pointing at a gone
# tree, five failed starts and a `start-limit-hit`. Without this the run that puts the
# install back reports success and leaves the shell unable to start.
systemctl --user reset-failed caelestia-shell.service >/dev/null 2>&1 || true

# The links that enable the unit, which are what makes the session start it at login.
#
# Taking the user's copy of the unit out - which is what the packaged branch above does to
# an install an earlier version of this port made - leaves the link that pointed at it
# behind, and a link whose file has gone is still a link with the unit's name: systemd
# counts the unit as enabled whenever one of those exists, however dead, so `enable` below
# leaves it exactly as it is instead of repairing it. The same state is reachable from the
# other direction, by putting a checkout's install under a package that was later removed.
# Both leave the link naming a file that is gone, so drop those here and let enable write
# one against the unit that is actually in use.
for link in "$HOME"/.config/systemd/user/*.wants/caelestia-shell.service; do
    [[ -L "$link" ]] || continue
    [[ -e "$link" ]] && continue
    rm -f "$link"
    info "Removed an enable link that named a copy of the shell unit that is gone."
done

systemctl --user daemon-reload
if systemctl --user enable caelestia-shell.service >/dev/null 2>&1; then
    ok "Caelestia Shell unit enabled."
else
    warn "Could not enable caelestia-shell.service; start the shell with 'systemctl --user start caelestia-shell.service'."
fi

# KWin restricts privileged Wayland protocols such as zkde_screencast_unstable_v1
# (live window thumbnails). For each one it calls
# KWin::fetchRequestedInterfaces(executablePath()), which uses KApplicationTrader to
# find a .desktop whose Exec first token resolves - via canonicalFilePath() - exactly
# to that path: no $PATH lookup, and no wrapper scripts. So write a user-level entry
# with Exec pointing at the resolved quickshell binary.
echo "  Creating quickshell KDE Wayland interface declaration..."
mkdir -p "$HOME/.local/share/applications"
QUICKSHELL_CANONICAL_PATH="$(realpath "$QUICKSHELL_PATH")"
cat > "$HOME/.local/share/applications/quickshell.desktop" << DESKEOF
[Desktop Entry]
Type=Application
Name=Quickshell
NoDisplay=true
Exec=$QUICKSHELL_CANONICAL_PATH
X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1,org_kde_plasma_window_management
DESKEOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
# KApplicationTrader/KService go through the ksycoca cache, not just the database
# above, so rebuild it for the new Exec to be seen.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
fi
ok "Quickshell Wayland interface declaration created."

# Retired: kde-material-you-colors.
#
# caelestia-color generates and applies the palette now. An install predating that
# still has the unit enabled, and it would keep applying a scheme of its own on top
# of ours - whichever runs last wins - so stop it here.
echo "  Retiring the KDE Material You Colors service..."
rm -f "$AUTOSTART_DIR/kde-material-you-colors.desktop" 2>/dev/null || true

KMY_UNIT="$HOME/.config/systemd/user/kde-material-you-colors.service"
if [[ -e "$KMY_UNIT" ]]; then
    systemctl --user disable --now kde-material-you-colors.service >/dev/null 2>&1 || true
    rm -f "$KMY_UNIT"
    systemctl --user daemon-reload
    ok "kde-material-you-colors no longer applies the scheme; its service was removed."
else
    skip "kde-material-you-colors service is not installed."
fi

# KMY wrote two schemes per change because plasma-apply-colorscheme refuses the name
# already in effect. Ours rotates between two names of its own, so its leftovers would
# only be duplicates in System Settings.
rm -f "$HOME/.local/share/color-schemes/MaterialYou"*.colors 2>/dev/null || true

# Retired: the status icons order file.
#
# The bar kept the user's dragged order in ~/.config/caelestia. The order is part of
# the config now (bar.statusIcons), and the shell moves it there: ConfigMigrations.qml
# reads the file, writes the list, and deletes the file on the following start. This
# script must not delete it - it runs on the same login as the shell, and removing it
# here would take the order with it before the shell has read it.
if [[ -f "$HOME/.config/caelestia/status_icons_order.txt" ]]; then
    skip "Status icon order file left to the shell, which migrates it into bar.statusIcons."
fi

# Live window thumbnails.
#
# KWin only advertises its privileged Wayland interfaces to clients whose desktop file
# requests them: it resolves /proc/<pid>/exe and looks for an installed .desktop whose
# Exec resolves to that same binary, then reads X-KDE-Wayland-Interfaces. Quickshell's
# packaged entry has no Exec line, so the shell matches nothing and
# zkde_screencast_unstable_v1 is never offered - the dock hover popup and window
# switcher then draw the app icon instead of a live preview.
#
# This cannot live on the autostart entry above: KWin matches the resolved executable,
# and that entry's Exec is the wrapper script, not the quickshell binary.
if [[ -f "$BUNDLE_DIR/assets/org.quickshell.desktop" ]]; then
    echo "  Requesting KWin screencast interface for window previews..."
    mkdir -p "$HOME/.local/share/applications"
    sed "s|^Exec=.*|Exec=$QUICKSHELL_CANONICAL_PATH|" \
        "$BUNDLE_DIR/assets/org.quickshell.desktop" \
        > "$HOME/.local/share/applications/org.quickshell.desktop" 2>/dev/null || true
    # KWin reads this through KService, which needs its cache rebuilt.
    kbuildsycoca6 >/dev/null 2>&1 || true
    echo "  [OK]  Window preview interface requested."
fi

ok "Autostart entries configured."
