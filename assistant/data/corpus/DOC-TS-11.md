id: DOC-TS-11
title: 11. Diagnostic Commands Reference
source: docs/TROUBLESHOOTING.md — section 11 (Diagnostic Commands Reference)
tags: diagnostics, diagnostic commands, reference, journalctl, systemctl status, debug mode, system state checks, kde cache refresh, kbuildsycoca6, logs

### System State Checks

```bash
# KWin reconfigure
qdbus6 org.kde.KWin /KWin reconfigure

# Check user services
systemctl --user list-units | grep -E 'caelestia|quickshell'

# Check KWin plugins
kwriteconfig6 --file kwinrc --group Plugins --key list

# Verify QML imports
qml6 -p ~/.config/quickshell/caelestia/shell.qml 2>&1 | head -30
```

### Caelestia-Specific Diagnostics

```bash
# Check if the shell binary was built
ls -la ~/.local/lib/qt6/qml/Caelestia/

# Check installed wallpaper plugin
kpackagetool6 --list -t Plasma/Wallpaper

# Read lock screen config
kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin

# View failed packages log
cat $XDG_CACHE_HOME/caelestia-kde/failed_packages.txt 2>/dev/null

# View failed patches log
cat $XDG_CACHE_HOME/caelestia-kde/failed_patches.txt 2>/dev/null

# View installer build log
cat /tmp/caelestia_build.log 2>/dev/null | tail -60

# View installer stderr log
cat /tmp/caelestia_installer_err.log 2>/dev/null
```

### Network Diagnostics

```bash
# Test submodule availability
git ls-remote https://github.com/ladybug-me/caelestia-kde.git HEAD

# Test AUR access
curl -sI https://aur.archlinux.org/rpc/?v=5\&type=info\&arg[]=quickshell-git | head -5
```

### KDE Cache Refresh

```bash
# Rebuild desktop file cache
kbuildsycoca6 --noincremental

# Refresh desktop database
update-desktop-database ~/.local/share/applications/

# Restart Plasma shell (affects current session)
systemctl --user restart plasma-plasmashell
```

---

## Quick Reference: Common Fixes

| Problem | Quick Fix |
|---|---|
| Shell won't start | `quickshell -d -n -p ~/.config/quickshell/caelestia/shell.qml` |
| Lock screen not active | `kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop"` |
| Stale lock file | `rm -f "${XDG_RUNTIME_DIR:-/tmp}/caelestia-setup.lock"` |
| Missing QML module | `export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml"` |
| No window thumbnails | `kbuildsycoca6 --noincremental && qdbus6 org.kde.KWin /KWin reconfigure` |
| Git submodule error | `git submodule update --init --recursive src/dots` |
| Colors not updating | Run `caelestia scheme set -n dynamic`, and check that `plasma-apply-colorscheme --list-schemes` names Matugen |
| Installer compiles but flashes/exits | Check `/tmp/caelestia_installer_err.log` |
| Recording not working | Verify `gpu-screen-recorder` is installed |
| Screenshot not working | Verify `spectacle` is installed |
