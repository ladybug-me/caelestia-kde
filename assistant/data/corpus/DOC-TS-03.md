id: DOC-TS-03
title: 3. Runtime Issues — Shell
source: docs/TROUBLESHOOTING.md — section 3 (Runtime Issues — Shell)
tags: runtime, shell, quickshell, caelestia-shell.service, systemd user unit, journalctl, environment variables, environment.d, plasma-workspace env, caelestia.sh, kscreenlocker_greet, qml2_import_path, window thumbnails, screencast, screen share, vesktop, camera freeze, colors not applying, scheme, screen recording, screenshots, screen flashes, kde-material-you-colors, workspace tracker, workspace pills, kde update, tonal spot
synonyms: shell does not start, blank screen at login, vesktop freezes when i screenshare, colors revert after reboot, workspace pills not loading, scheme resets

### 3.1 Shell Doesn't Start After Login

The shell starts from the systemd user unit `caelestia-shell.service`, which `caelestia install` enables once. The environment the shell needs is set by `~/.local/bin/caelestia-autostart.sh` for a source install, and by `/usr/bin/caelestia-autostart` for a packaged one; the unit runs whichever belongs to that install.

| Symptom | Likely Cause |
|---|---|
| Blank screen at login | Shell binary launched but crashed immediately. Check `journalctl --user -xe`. |
| Plasma desktop visible, no shell | The unit didn't start. `systemctl --user status caelestia-shell.service`, and `systemctl --user is-enabled caelestia-shell.service` for whether it is on at all. |
| Shell appears briefly then disappears | Quickshell crashed. Run manually from a terminal. |
| `quickshell: command not found` | Quickshell not in PATH at login. The wrapper the unit runs resolves the binary path. |

**Manual start for debugging:**
```bash
export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml"
export CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
quickshell -d -n -p ~/.config/quickshell/caelestia/shell.qml
```

### 3.2 Environment Variables Not Set On Login

They live in two locations:
1. `~/.config/environment.d/caelestia.conf`: read by systemd for every session process and for the user manager the shell's unit runs under.
2. `~/.config/plasma-workspace/env/caelestia.sh`: sourced by KDE Plasma on session startup for KWin, `kscreenlocker_greet`, and graphical applications.

```bash
QML2_IMPORT_PATH=$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia
CAELESTIA_LIB_DIR=$HOME/.local/lib/caelestia
CAELESTIA_BIN_DIR=$HOME/.local/bin
CAELESTIA_SHELL_CONFIG=$HOME/.config/quickshell/caelestia/shell.qml
```

**If they are missing:** re-run `scripts/08-build-shell.sh`, then log out and back
in. `systemctl --user show-environment` lists what the systemd user manager has.

### 3.3 Window Thumbnails / Screencast Not Working

KWin only grants `zkde_screencast_unstable_v1` to clients whose `.desktop` file lists the protocol.

**Fix:**
```bash
# Verify the desktop file exists
cat ~/.local/share/applications/quickshell.desktop
# Rebuild KService cache
kbuildsycoca6 --noincremental
# Reload KWin
qdbus6 org.kde.KWin /KWin reconfigure
```

If the desktop file is missing, re-run `scripts/10-autostart.sh`.

### 3.3.1 Screen Sharing / Camera Freezes Vesktop (or other apps)

Some NVIDIA + KWin setups cannot handle two separate clients using KWin's
privileged `zkde_screencast_unstable_v1` protocol at the same time. Caelestia
uses this protocol for live taskbar/overview/alt-tab window thumbnails, which
can conflict with another app's screencast (e.g. Vesktop screen share with
audio, or camera) using the same KWin subsystem via xdg-desktop-portal-kde,
causing that app to freeze or crash.

**Fix:** Disable live window previews:
- Nexus -> Taskbar -> "Live window previews" toggle, or
- Set `"bar": { "livePreviews": false }` in `shell.json` and reload

This falls back to static app icons for thumbnails instead of live video and
avoids Caelestia's use of the protocol entirely.

### 3.4 Colors Not Applying

| Symptom | Fix |
|---|---|
| Colors do not change with the wallpaper | `caelestia wallpaper -f <image>` generates and applies the palette. If Plasma stays on the old one, check that `plasma-apply-colorscheme --list-schemes` names `Matugen`. |
| Two Material You entries in System Settings | Expected: `Matugen` and `Matugen Alt`. `plasma-apply-colorscheme` does nothing when handed the scheme already in effect, so the palette is applied under whichever of the two is not current. |
| A leftover accent color wins over the palette | Plasma rewrites the focus, link and selection colors from `kdeglobals`' accent, so the palette is applied with that key removed. If it is set again - System Settings, or a theme tool of your own - the colors it drives will follow it. |
| Colors come back as the built-in default (Mocha) | The CLI derives dynamic colors from the wallpaper it was last told about. When it has none it writes nothing, and the shell keeps its own default palette. The shell re-derives from the wallpaper it is showing at every start. |
| Konsole keeps its own colors | The command writes `~/.local/share/konsole/Matugen.colorscheme` and points the profiles that exist at it. Konsole's built-in default profile is not a file, so a fresh account has nothing to point: create a profile once and the next change themes it. |
| The desktop flickers between two palettes | A `kde-material-you-colors` unit from an older install is still applying a scheme of its own. See 3.7. |

There is no service to restart. A palette is generated and applied by the command the shell calls, so
the way to redo it by hand is:

```bash
caelestia scheme set -n dynamic      # re-derive from the wallpaper on screen
caelestia wallpaper -f ~/Pictures/Wallpapers/one.png
```

### 3.5 Screen Recording Issues

| Symptom | Cause |
|---|---|
| Recording appears stuck | `gpu-screen-recorder` not installed or not in PATH |
| Portal dialog doesn't appear | The `caelestia-record` wrapper restarts `plasma-xdg-desktop-portal-kde` and `xdg-desktop-portal` before launching `gpu-screen-recorder`. If the portal still doesn't appear, restart them manually: `systemctl --user restart plasma-xdg-desktop-portal-kde xdg-desktop-portal`. |
| Recording doesn't start | `caelestia-record` wraps `gpu-screen-recorder` directly with KDE-specific monitor detection (via `kscreen-doctor`) and portal management. No Python/OpenCV dependency. |

The recorder now verifies both `pidof gpu-screen-recorder` AND that `recording.mp4` exists, preventing false positives from stale PID matches.

### 3.6 Screenshot Issues

The screenshot tool uses `spectacle` (KDE's native screenshot utility) via the `caelestia-screenshot` wrapper.

- If `spectacle` isn't installed, screenshots silently fail
- Full-screen screenshots save to `~/Pictures/Screenshots/` by default

### 3.7 Screen Flashes and the Shell Stutters Every Second

The screen flashes, colors look briefly wrong and the shell hangs for about a
second, repeating on a rhythm of roughly one second.

That was `kde-material-you-colors` getting stuck. It decided on every loop that
the palette had changed, applied an identical scheme again and spawned
`plasma-apply-colorscheme` each time, and every apply rewrites `kdeglobals` and
repaints every window. Nothing here runs it any more: it is not installed, the
installer removes its unit, and the palette is applied once per change rather than
once per poll.

If it is still happening, a unit from an older install is behind it:

```bash
systemctl --user status kde-material-you-colors   # active means it is still applying
systemctl --user disable --now kde-material-you-colors
pgrep -af plasma-apply-colorscheme                # a new pid every second means something still loops
```

`bash scripts/10-autostart.sh` stops that unit and deletes it, if you would rather
not do it by hand. It also removes the `MaterialYou*.colors` files KMY left in
System Settings.

Applying once when the wallpaper or theme changes is expected and does not
trigger any of this.

---

### 3.8 Workspace Tracker Effect Stops Loading After a KDE Update

The workspace pills show the focused screen's desktop on every screen, swiping
does not track the gesture, and the shell reports that the workspace tracker
effect is not running.

`kwin_workspace_tracker` is a compiled KWin effect, and KWin makes no promise
that a binary effect keeps working across releases: it is linked against
libkwin's internals and has to be relinked when KDE updates them. KWin then
refuses the stale binary, so per-output desktops and the swipe offset stop
arriving. A routine `pacman -Syu` is enough to cause it; nothing in Caelestia is
corrupted.

Rebuild it by re-running the installer or `update.sh`, then log out and back in -
KWin only loads effects at startup:

```bash
bash update.sh                     # rebuilds and reinstalls the effect
qdbus6 org.kde.KWin /Caelestia/Workspaces org.freedesktop.DBus.Introspectable.Introspect
```

The last command prints the effect's interface once it is loaded again, and
fails while it is not. `bash shell/scripts/check-workspace-tracker.sh` answers the
same question with an exit status (3 means enabled but not loaded).
