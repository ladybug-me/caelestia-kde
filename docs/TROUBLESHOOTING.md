# TROUBLESHOOTING

## Troubleshooting guide

This document catalogs known failure modes, error conditions, and edge cases discovered through analysis of the installer, shell build system, scripts, documentation, and runtime architecture of this port.

---

## Table of Contents

1. [Build & Compilation Issues](#1-build--compilation-issues)
2. [Dependency & Package Issues](#2-dependency--package-issues)
3. [Runtime Issues — Shell](#3-runtime-issues--shell)
4. [Runtime Issues — Lock Screen](#4-runtime-issues--lock-screen)
5. [Configuration Issues](#5-configuration-issues)
6. [Network & Proxy Issues](#6-network--proxy-issues)
7. [KDE & Plasma Specific Issues](#7-kde--plasma-specific-issues)
   1. [Installer Window Rules](#77-installer-window-rules)
   2. [Quick Share Cannot Receive Files](#78-quick-share-cannot-receive-files)
8. [Post-Install Issues](#8-post-install-issues)
9. [Uninstall Issues](#9-uninstall-issues)
10. [Update Issues](#10-update-issues)
11. [Diagnostic Commands Reference](#11-diagnostic-commands-reference)

---

## 1. Build & Compilation Issues

### 1.1 C++ Installer Compilation Fails

The installer compiles the `caelestia-install` TUI binary during `setup.sh`. The CMake project requires **C++20** (`CMAKE_CXX_STANDARD 20`).

| Symptom | Likely Cause | Fix |
|---|---|---|
| `g++: command not found` | Build tools not installed | Arch: `sudo pacman -S base-devel` — Fedora: `sudo dnf install gcc-c++` |
| `cmake: command not found` | CMake missing | Auto-installer handles this if `BASE_DISTRO` is detected; otherwise install manually |
| `[FATAL] Failed to build the Caelestia installer` | General CMake/make error | Read build log: `cat /tmp/caelestia_build.log` |
| Compiler error about modern C++ features | GCC older than 10 | Ensure GCC 10+ is installed: `g++ --version` |
| Exit 139 (SIGSEGV) at runtime | C++ bug in the TUI | Check stderr log at `/tmp/caelestia_installer_err.log` |
| Exit 127 at runtime | Missing shared library | Run `ldd` on the binary to find missing `.so` files |

### 1.2 Shell / Plugin Compilation Fails

The shell build (`08-build-shell.sh`) requires **Qt 6.9+** and several system libraries. The CMake project in `shell/CMakeLists.txt` uses `qt_standard_project_setup(REQUIRES 6.9)`.

#### Qt / QML Dependencies

| Missing Dependency | CMake Error Clue | Arch Package | Fedora Package |
|---|---|---|---|
| Qt6::Qml / Qt6::Quick | `find_package` failed | `qt6-declarative` | `qt6-qtdeclarative-devel` |
| Qt6::ShaderTools | Shader tool config | `qt6-shadertools` | `qt6-qtshadertools-devel` |
| Qt6::WaylandClient | Wayland client plugin | `qt6-wayland` | `qt6-qtwayland-devel` |
| KF6WindowSystem | KWindowSystem not found | `kwindowsystem` | `kf6-kwindowsystem-devel` |
| KGlobalAccel | kglobalaccel not found | `kglobalaccel` | `kf6-kglobalaccel-devel` |
| KPipeWire | pipewire integration | `kpipewire` | `kf6-kpipewire-devel` |
| Protobuf | Quick Share: `find_package(Protobuf)` | `protobuf` | `protobuf-devel` |
| OpenSSL | Quick Share: `find_package(OpenSSL)` | `openssl` | `openssl-devel` |

#### Library Dependencies (pkg_check_modules)

| Library | Arch Package | Fedora Package |
|---|---|---|
| `libqalculate` | `libqalculate` | `libqalculate-devel` |
| `libpipewire-0.3` | `pipewire` | `pipewire-devel` |
| `aubio` | `aubio` | `aubio-devel` |
| `libcava` | Prebuilt release asset / `libcava` | Prebuilt release asset / `celestelove/libcava` (COPR) |
| `libpulse` | `libpulse` | `pulseaudio-libs-devel` |
| `libpam` | `pam` | `pam-devel` |
| `lm_sensors` (Fedora) | not needed | `lm_sensors-devel` |

**Fedora note:** The custom `cmake/sensorslib.cmake` module loads `lm_sensors`. If it's missing, the build may silently skip sensor support.

### 1.3 "Missing QML Module Metadata" After Build

```text
[ERR] Missing QML module metadata: $HOME/.local/lib/qt6/qml/Caelestia/Config/qmldir
```

This means the CMake install step didn't copy required `qmldir` or `.so` files properly.

**Causes & fixes:**
- **Install prefix mismatch:** The build uses `-DCMAKE_INSTALL_PREFIX=$HOME/.local`. If Qt6 looks for QML modules elsewhere, the module won't load.
- **Stale build artifacts:** Run `rm -rf shell/build shell/plugin/build` before re-running
- **Partial installation:** If CMake install was interrupted, files may be missing. Re-run `08-build-shell.sh`

### 1.4 ccache Not Speeding Up Rebuilds

The project enables ccache in both `installer/CMakeLists.txt` and `shell/CMakeLists.txt`. If rebuilds are still slow:

- Check ccache stats: `ccache -s`
- The cache directory (`~/.cache/ccache`) may be too small — increase it: `ccache -M 5G`
- Debug builds (`-DCMAKE_BUILD_TYPE=Debug`) are much slower; the installer uses `Release`

---

## 2. Dependency & Package Issues

### 2.1 Arch Linux / yay Failures

| Issue | Cause |
|---|---|
| `yay` fails to install | Network issues, AUR down, or PKGBUILD changes. The script (`installer/distro/arch/packages.sh`) retries individually and falls back to `makepkg -si`. |
| `pacman` errors during install | The script uses `-Sy --noconfirm` (refresh DB) then `-S --needed --noconfirm`. If the system update step (`00a-system-update.sh`) was skipped, partial upgrades can cause conflicts. |

**AUR packages used by Caelestia:**

| AUR Package | Failure Symptoms |
|---|---|
| `quickshell-git` | Shell won't start; autostart fails with exit 127 |
| `matugen` | `caelestia wallpaper` and `caelestia scheme` fail with "matugen is not installed". It is in Arch's `extra`, so it is not an AUR package; it is listed here because nothing themes without it. |
| `darkly` | KDE theme won't apply |

### 2.2 Fedora / COPR Failures

| Package | COPR / Source | Known Issues |
|---|---|---|
| `quickshell-git` | `errornointernet/quickshell` | COPR may be out of date |
| `gpu-screen-recorder` | `brycensranch/gpu-screen-recorder-git` | May need `ffmpeg` from RPM Fusion |
| `app2unit` | `celestelove/app2unit` | Falls back to `make install` |
| `libcava` | Prebuilt release asset / `celestelove/libcava` | Downloads prebuilt SDK from release; falls back to COPR |
| `starship` | `atim/starship` | Stable, rarely fails |
| `wl-clip-persist` | `leloubil/wl-clip-persist` | Needed for clipboard persistence |

**RPM Fusion requirement:** `ffmpeg` with H264 support requires RPM Fusion. The script auto-enables it, but this may fail behind a proxy or on air-gapped systems.

**matugen on Fedora:** available from the `avengemedia/danklinux` COPR repository. The installer auto-enables it and installs `matugen` via DNF.

### 2.3 CRLF / dos2unix Failure

If CRLF line endings are detected and `dos2unix` auto-install fails, the installer **aborts** with:

```text
[FATAL] Line ending normalization step failed. Aborting installer.
```

**Fix:** Install `dos2unix` manually, or answer `n` to the CRLF prompt to skip normalization.

### 2.4 Failed Packages Log

Failed packages are logged to:

```text
$XDG_CACHE_HOME/caelestia-kde/failed_packages.txt
```

The installer does **not** abort on package failure — it logs and continues. Check this file after installation if something doesn't work.

---

## 3. Runtime Issues — Shell

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

### 3.3.2 Black Window in Screen Center (xwaylandvideobridge) ([#1006](https://github.com/ladybug-me/caelestia-kde/issues/1006))

On systems where `xwaylandvideobridge` autostarts (such as Fedora KDE), an opaque black floating window can appear in the center of the display at startup and reappear whenever clicking the desktop.

**Cause:**
`xwaylandvideobridge` creates an idle dummy X11 helper window (`ContentsWindow`, painted `Qt::black` with `setOpacity(0)`). On some builds (e.g., Fedora), this window is flagged as a dialog (`types 32`). Because Caelestia's `caelestia-dialogs` rule centers all dialogs (`placement 5`) and `caelestia-opacity` forces inactive opacity to 95% on `types 33` (`Normal | Dialog`), KWin centered the bridge helper window and rendered it at 95% opacity above Quickshell's bottom layer. When focused, the window reverted to its native 0% active opacity (disappearing), but returned to 95% opacity as soon as focus shifted back to the desktop.

Because KWin evaluates rules top-to-bottom and resolves attribute conflicts by **first match wins**, specific application rules must precede general catch-all rules in `[General] rules=` to prevent general rules from overriding them.

**Fix:**
Re-apply the Caelestia window rules to write the `caelestia-xwaylandvideobridge` rule ahead of general rules in `~/.config/kwinrulesrc`:

```bash
bash scripts/04a-window-rules.sh
```

The rule uses substring matching (`wmclassmatch 2`), omits `types` (matching both Dialog and Normal window types), enforces `placement 0` (NoPlacement to prevent centering), forces 0% active and inactive opacity, and marks the window to stay below others while skipping taskbars, pagers, and window switchers.

### 3.3.3 Shell Crash-Loops When MangoHud Is Enabled Session-Wide ([#940](https://github.com/ladybug-me/caelestia-kde/issues/940))

With `MANGOHUD=1` set for the whole session (common on gaming distributions, e.g. in
`~/.config/environment.d/`), the shell dies seconds after it starts and
`caelestia-shell.service` restarts it in a loop — the "What's new" window reappears each
time and shortcuts stop working.

**Cause:**
MangoHud installs an implicit Vulkan layer, which the loader adds to *every* process in
the session. QtMultimedia's FFmpeg backend creates a Vulkan device for hardware decode as
soon as a `MediaPlayer` exists, and MangoHud crashes inside `vkCreateDevice`. The
backtrace ends in `libMangoHud.so` ← `vkCreateDevice` ← `libavutil` ←
`libffmpegmediaplugin.so`, and the same crash happens outside the shell with
`MANGOHUD=1 qml6 player.qml`.

**Fix:**
The shell's unit opts out of MangoHud with `Environment=DISABLE_MANGOHUD=1`, so the layer
is never loaded into the shell while games keep their overlay. That is shipped since this
change; an existing install gets it by re-running:

```bash
bash scripts/10-autostart.sh
```

For an older install, the same thing without touching the shell:

```ini
# ~/.config/systemd/user/caelestia-shell.service.d/no-mangohud.conf
[Service]
Environment=DISABLE_MANGOHUD=1
```

**Verify:**
```bash
systemctl --user show -p NRestarts --value caelestia-shell.service   # stays at 0
journalctl --user -u caelestia-shell.service | grep -c core-dump     # no new entries
```

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

---

### 3.9 Copy/Paste Crashes Krita or Inkscape (cliphist.service)

Krita crashes when a selection is copied and pasted inside the document, while
pasting an image copied from another application works. Inkscape crashes on
copy/paste of anything. Stopping the clipboard service stops the crashes:

```bash
systemctl --user stop cliphist.service   # the crash should go away with it
systemctl --user start cliphist.service
pgrep -a wl-clip-persist                 # confirms the helper below is running
```

The unit runs three helpers: two `wl-paste --watch cliphist store` watchers and
`wl-clip-persist`. The watchers only read the clipboard, so they cannot disturb
it. `wl-clip-persist` does: it reads **every** MIME type of a new selection into
memory and then re-offers the clipboard itself, so the application that copied no
longer owns the selection.

Applications that put a process-private payload on the clipboard expect to read
it back out of their own clipboard object. Krita serialises raw `KisNode*`
pointers into `application/x-krita-node-internal-pointer` and hands the payload
straight back to `dynamic_cast` on paste as long as the pid in it is its own
(`KisMimeData::tryLoadInternalNodes`); Inkscape does the same for
`image/x-inkscape-svg`. Once `wl-clip-persist` re-offers the payload, the
pointers are stale and the paste dies in `__dynamic_cast`.

The unit therefore passes `--all-mime-type-regex` to `wl-clip-persist`, which
makes it leave alone any selection event that offers one of those private
formats. `wl-clip-persist` handles an event only when **every** MIME type it
offers matches the filter, so a selection carrying both a private format and,
say, `text/plain` is skipped whole: the watchers still add it to the clipboard
history, but it no longer survives the application it was copied from.
Selections offering only public formats persist as before; the install keeps that
list in `~/.local/bin/caelestia-cliphist`, next to the flag that reads it.

On an install older than the fix, or if you run your own clipboard setup, pass
the same flag yourself:

```bash
wl-clip-persist --clipboard regular \
    --all-mime-type-regex '(?i)^(?!(?:application/x-krita-|image/x-inkscape-svg)).+'
```

Any other application that crashes when pasting its own content while the
service runs belongs to the same class: report it so its format can be added to
the filter.

### 3.10 Launcher Search Mode Finds Nothing

The launcher's system-wide search (`>search <query>`) is powered by KDE's
KRunner, which reaches files, places, web shortcuts, the dictionary, unit and
currency conversion and settings modules. KRunner's D-Bus service only exposes
UI control methods, so the shell talks to the library instead, and the bridge is
built only when the development package is present:

```bash
pacman -Q kf6-krunner          # Arch: the runtime is usually already there
pacman -S kf6-krunner          # headers + CMake config the bridge needs
```

If `>search` shows nothing at all while `>calc` still works, the shell was
compiled without it. Check what the installed plugin was built against:

```bash
ldd ~/.local/lib/qt6/qml/Caelestia/lib/libcaelestia-services.so | grep -i runner
```

No `libKF6Runner` line means the plugin predates KRunner or was built on a
machine without the headers; reinstall the shell after installing the package.
A build with KRunner gets `search` in the launcher's action list, and
`KRunnerBridge.available` is `false` without it, so the mode simply has no
results rather than erroring.

Empty results with the bridge in place usually mean the runner itself is not
enabled. Turn the relevant one on in *System Settings → Search → Plasma Search*
(in particular *Files* for Baloo), and check that the file index exists:

```bash
balooctl6 status                # "indexing" or "idle" is healthy
```

Results that say *Search DuckDuckGo for …* are web searches: KRunner's *Web
Search Keywords* runner offers the configured engine once nothing else matches,
and search mode adds the same row itself when KRunner has not. The engine is
KDE's choice, stored as `DefaultWebShortcut` in `~/.config/kuriikwsfilterrc`;
with no such file the built-in default applies, which is DuckDuckGo. Providers
ship with `kio` as `/usr/share/kf6/searchproviders/*.desktop`, and the value is
the *file name* of the provider (`google`, `duckduckgo`, …) rather than one of
the aliases on its `Keys=` line. Those aliases only apply to what you type, so
`ddg:cats` searches directly whichever engine is configured.

Pick the engine in *Nexus → Apps → Web search engine*, from KDE's own page in
*System Settings → Search → Web Search Keywords* (`kcmshell6 kcm_webshortcuts`),
or set it once:

```bash
kwriteconfig6 --file kuriikwsfilterrc --group General --key DefaultWebShortcut google
```

Until Baloo has an index the web row is often the only match for a filename, which makes the shortcut look
like a bug rather than a fallback.

### 3.11 The Calendar Agenda Stays Empty

The agenda reads iCalendar (`.ics`) sources; the shell has no PIM stack of its own.
It lives in the clock popout — hover the clock or click it. The month grid marks the
days that have events, and the list under it shows the day you have selected: click
any day to see its events, with times and locations. If the popout says
*No calendars yet*, nothing is configured: click that row, or go to
*Nexus → Services → Calendars & agenda*. For Google Calendar the address is
**Settings → the calendar → "Secret address in iCal format"**; Nextcloud, Fastmail
and KOrganizer all hand out an equivalent export link, and a local `.ics` path works
too.

If the popout does not appear at all, the *Calendar popout* switch is off in
*Nexus → Panels → Clock* — it is on by default, but a `shell.json` written before
that default may still carry `bar.popouts.clock: false`.

If sources are configured but no events appear:

```bash
# What the shell runs, and what it gets back
python3 ~/.config/quickshell/caelestia/scripts/calendar_events.py \
  --days 14 --source 'Work=https://calendar.google.com/…/basic.ics'
```

* `No time zone found with key …` means the system tz database is missing — install
  `tzdata`.
* A `[[errors]]` entry names the source that failed; the others still load, so one
  bad link cannot empty the agenda.
* Recurring events are expanded here, and only `DAILY`, `WEEKLY`, `MONTHLY` and
  `YEARLY` rules are understood. A calendar relying on exotic `BY*` combinations will
  show the master event and its plain recurrences, not every exception.
* Fetched URLs are cached for five minutes under `~/.cache/caelestia/calendar`, and the
  cache is revalidated with the calendar's `ETag` rather than downloaded again. The
  agenda re-reads on its own every five minutes and whenever the popout is opened, so
  an edit in Google shows up within a few minutes; *Refresh* in Nexus forces a re-fetch.
* The address Google hands out is **read only**: the shell can show the calendar, not
  write to it. Editing stays in Google Calendar or whatever client you already use.

### 3.12 Focus Sessions Turn Notifications Off at the Wrong Time

A focus session is a window (days plus start and end) during which the shell turns
Do Not Disturb on itself. A window whose end is before its start runs overnight and
belongs to the day it started on — `22:00–07:00` on a Monday covers Tuesday morning.

* If DND will not clear, check whether a session is still running:
  *Nexus → Notifications → Focus sessions* names the window and the time it ends.
* Turning DND off by hand during a session keeps it off until the window ends; the
  shell only clears a DND it turned on itself.
* An app that should still reach you goes in *Allowed through*; the name has to match
  the application name the notification carries, which is what
  `notify-send -a <name>` and most messaging apps set.

### 3.13 Shell Text Does Not Follow the System Text Size

The shell draws with its own type tokens, so KDE's font size does not reach it
unless *Nexus → Accessibility → Follow system text size* is on (it is by default).
With it on, the shell reads `[General] font` from `~/.config/kdeglobals` and uses its
point size as the scale, against a 10 pt base:

```bash
kreadconfig6 --file kdeglobals --group General --key font   # e.g. "Noto Sans,11,-1,5,…"
```

An absent key means KDE is running its default, which is the 10 pt base, so the shell
stays at 100%. If a different size is wanted in the shell alone, switch the toggle off
and use *Font scale* instead.

### 3.14 Magnifier, Colour Filters or Screen Reader Do Nothing

Those are not shell features: the magnifier, colour inversion and colour-blindness
correction are **KWin effects**, so the shell can only load or unload them, and the
shortcuts and filter choice live in *System Settings → Accessibility*. Check what
KWin reports:

```bash
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded zoom
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.listOfEffects | tr ',' '\n' | grep -i colour
```

The screen reader is Orca, which has to be installed (`orca` on Arch, `gnome-orca`
elsewhere). The page reports it as missing rather than offering a button that cannot
work.

### 3.15 Displays Page Is Empty or Changes Do Not Stick

Nexus reads and writes the screen layout through **KScreen**, the same component System
Settings uses, so what it shows is the real layout and every change is applied by KScreen
rather than by the shell:

```bash
kscreen-doctor -j | head -20        # what the page reads
kscreen-doctor output.eDP-1.scale.1.5   # what the page runs for a change
```

If the page shows the "no kscreen-doctor" note, the package is missing (`kscreen` on
Arch, `kscreen5`/`libkscreen` elsewhere). A change that reverts after a moment means KScreen
rejected it — for example disabling the only enabled output, which the enabled switch
refuses to do on purpose. Rotation is reported by KScreen as a bit flag (1 none, 2 left,
4 upside down, 8 right), so the page names it before showing it.

Input (pointer, touchpad, keyboard) is deliberately not duplicated here: those settings are
applied by Plasma's KCMs, so the page opens them rather than keeping a second copy that
would drift.

### 3.16 A Startup Program Does Not Run

Log-in programs are XDG autostart desktop files. The shell lists `~/.config/autostart` and
every `XDG_CONFIG_DIRS` directory (usually `/etc/xdg/autostart`), and switches a *system*
entry off by keeping a copy of its own in `~/.config/autostart` with `Hidden=true` — the same
mechanism System Settings uses, so the two never disagree about what starts:

```bash
python3 ~/.config/quickshell/caelestia/scripts/autostart.py --list
grep -H Hidden ~/.config/autostart/*.desktop
```

A program that shows as enabled but never starts usually has an `Exec` line that needs a full
path, or an entry restricted with `OnlyShowIn=` to a desktop the session does not advertise.
Removing the user's copy (`--remove NAME`, or the bin icon in Nexus, which only appears for
entries the user owns) restores whatever the package shipped.

---

## 4. Runtime Issues — Lock Screen

### 4.1 Lock Screen Greeter Diagnostic

The Caelestia lock screen runs as a native KDE Plasma 6 shell package (`caelestia.desktop`), loaded directly by KDE's `kscreenlocker_greet`.

**Diagnostic commands:**
```bash
# Verify Caelestia shell package is configured
kreadconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage"
# Expected output: caelestia.desktop

# Verify greeter files exist in local plasma shells directory
ls -la ~/.local/share/plasma/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml

# Test and run the greeter in a window (non-blocking test)
/usr/lib/kscreenlocker_greet --testing
```

| Symptom | Cause | Solution |
|---|---|---|
| Stock Breeze lock screen appears | `ShellPackage` reset after KDE update or theme switch. | Caelestia autostart (`caelestia-autostart.sh`) automatically self-heals this at next login if `caelestia.desktop` is present. To restore immediately in session: `kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop" && kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" --delete`. |
| Lock screen fails or crashes | Greeter files missing or corrupted in `~/.local/share/plasma/shells/`. | Re-deploy via `BUNDLE_DIR=. ./scripts/08-build-shell.sh` or `cp -r src/kde/shells/caelestia.desktop ~/.local/share/plasma/shells/`. |
| Lock screen shows wallpaper error | Legacy `PlasmaApplicationWallpaper` left in `kscreenlockerrc`. | Reset WallpaperPlugin: `kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image"`. |
| Profile picture missing | `~/.face` does not exist and no system user avatar set. | Place your avatar image at `~/.face` or configure an avatar in KDE System Settings → Users. |

---

## 5. Configuration Issues

### 5.1 Darkly Theme Not Applied

| Symptom | Cause |
|---|---|
| Plasma style unchanged | `APPLY_DARKLY` was set to `false` in the configuration menu |
| Window decorations missing | The installer tries `org.kde.darkly` library, falls back silently to `org.kde.breeze` |
| `lookandfeeltool --apply "Darkly"` failed | The `darkly` package may not be installed (AUR/COPR/prebuilt packages) |

**Manual apply:**
```bash
kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" --key "library" "org.kde.darkly"
kwriteconfig6 --file kwinrc --group "org.kde.kdecoration2" --key "theme" "@darkly"
qdbus6 org.kde.KWin /KWin reconfigure
```

### 5.2 KDE OSD Still Showing

The tweak script disables OSD in `plasmarc`, `kdeglobals`, `plasmanotifyrc`, `powerdevilrc`, and `kmixrc`. If OSD still appears:

```bash
systemctl --user restart plasma-plasmashell
```

Some KDE versions (6.1 vs 6.2) may use slightly different config keys.

### 5.3 Wrong Number of Virtual Desktops

The installer configures **5 desktops** when it runs, and only then: a system update never touches the count. A count you chose yourself — anything other than KWin's default of `1` — is left alone even on an install.

- To apply the 5 desktops again, set the count back to `1` (or remove `Number` from the `[Desktops]` group) and run the installer: `bash scripts/setup.sh`, or `caelestia install` on a packaged install
- The uninstaller resets the desktop count to `1`

### 5.4 Keyboard Shortcut Conflicts

Caelestia's `GlobalShortcut` system uses `kglobalacceld`. When it registers a shortcut that conflicts with another app, it "steals" the binding and records it in:

```text
${XDG_CONFIG_HOME:-~/.config}/caelestia/stolen-shortcuts.json
```

**If shortcuts are missing or wrong:**
```bash
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/stolen-shortcuts.json"
systemctl --user status plasma-kglobalaccel.service
```

A file an older version left at `~/.config/caelestia/` because it ignored `XDG_CONFIG_HOME` is not read any more. If you set `XDG_CONFIG_HOME` somewhere other than `~/.config`, remove that leftover by hand.

If `keyd` is active and manages Meta+1..5, the tweak script skips KWin bindings for those combos to avoid conflicts.

## 6. Network & Proxy Issues

### 6.1 Package Repository Problems

The installer does not change mirror lists or refresh package repositories as a separate step. If package installation fails, check that your distribution's configured repositories are reachable and refresh them using the distribution's normal tools before retrying.

### 6.2 Git / Submodule Failures

The submodule `src/dots` is critical. If it cannot be fetched:

```text
[ERR] src/dots is still empty, and the installer cannot deploy without it.
```

Step 02a checks the submodule has content and fetches it again by other means before reporting this: a normal update, then a sync of the recorded URL followed by another update, then a forced update, and finally a plain clone of the URL `.gitmodules` records. So this message means all four were attempted and every one failed, which is usually a network that cannot reach GitHub or a checkout that cannot be written to.

This is a **hard failure** - the installer cannot proceed past config deployment. Fetch it by hand and re-run the step:

```bash
git -C ~/caelestia-kde submodule update --init --recursive src/dots
bash ~/caelestia-kde/scripts/02a-submodules.sh
```

The shared folder mounted at `/mnt/hgfs/` is read-only, so an install run from there cannot fetch anything: clone the repository to a writable directory first.

**Behind a proxy?**
```bash
git config --global http.proxy http://proxy:port
git config --global https.proxy http://proxy:port
export GIT_SSL_NO_VERIFY=1
```

### 6.3 AUR Builds Fail Behind Proxy

`makepkg -si` downloads sources from various URLs. Set proxy environment variables before running `setup.sh`:
```bash
export http_proxy=http://proxy:port
export https_proxy=http://proxy:port
export ALL_PROXY=http://proxy:port
```

---

## 7. KDE & Plasma Specific Issues

### 7.1 Legacy qs-kwin-bridge Service

The old `qs-kwin-bridge` Python daemon is now **disabled** in favor of native C++ plugins. If you see it running:
```bash
systemctl --user disable --now qs-kwin-bridge.service
```

### 7.2 xdg-desktop-portal-kde

The recording patch restarts `plasma-xdg-desktop-portal-kde` before each recording. This may fail if:
- The portal service is masked
- The user's systemd session is in a bad state

### 7.3 ydotoold (On-Screen Keyboard)

`ydotoold` needs access to `/dev/uinput`. The installer writes
`/etc/udev/rules.d/70-uinput.rules`, which tags the device for the active session
(`TAG+="uaccess"`). Nothing is added to a group, and the device stays closed to
programs running outside your session.

**If ydotoold doesn't work:**
- Check the rule exists and `/dev/uinput` is present (`sudo modprobe uinput` if not)
- Verify: `ls -la /run/user/$(id -u)/.ydotool_socket`
- Restart it: `systemctl --user restart ydotoold.service`

Installs older than this rule put your user in the `input` group instead. The
installer removes that membership when it replaces the old rule, and the change
takes effect on your next login.

### 7.4 Krohnkite Tiling Disabled on Uninstall

The uninstaller disables `krohnkiteEnabled` in `kwinrc`. If you don't have the Krohnkite KWin script installed, this setting is simply ignored.

### 7.5 KWin Script Injection Fails

The plugin injects a temporary KWin script for window tracking. If KWin scripting is disabled:
```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript
```

### 7.6 The Login Screen (Plasma Login and SDDM)

Plasma 6.6 and newer boot into Plasma Login, KDE's fork of SDDM. The two are
configured in different places, and the installer picks a branch at install time:

| | Plasma Login | SDDM |
|---|---|---|
| How to tell | `plasmalogin.service` is active/enabled | `sddm.service` is active/enabled |
| Theme | none: its greeter is a Plasma shell, and it loads no SDDM theme | `/usr/share/sddm/themes/caelestia` |
| Wallpaper | `[Greeter][Wallpaper][org.kde.image][General] Image` in `/etc/plasmalogin.conf`, pointing at a copy under the `plasmalogin` user's `wallpapers/` | `assets/background` inside the theme |
| Colors | the `plasmalogin` user's own `~/.config/kdeglobals` plus the scheme files in its `~/.local/share/color-schemes/` | `theme.conf` inside the theme |
| Sync helper | `/usr/local/bin/caelestia-greeter-sync` | `/usr/share/sddm/themes/caelestia/scripts/sync.sh` |

The greeter runs as its own system user, which cannot read your home directory, so
anything it shows has to be copied to it. That is what the sync helper does, and it
runs after every wallpaper or color change through the posthook in
`~/.config/caelestia/cli.json`. An install that switches display managers replaces
its hook rather than stacking a second one.

**The login screen shows Breeze colors or no background:**

```bash
# Which display manager is actually installed
command -v plasmalogin sddm

# Plasma Login: what the greeter is told to show
kreadconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper \
    --group org.kde.image --group General --key Image

# SDDM: which theme each config source selects, last one read wins
grep -rn "Current=" /etc/sddm.conf /etc/sddm.conf.d/ /usr/lib/sddm/sddm.conf.d/ 2>/dev/null
ls /usr/share/sddm/themes/caelestia/theme.conf

# Re-copy the wallpaper and the scheme, then log out
sudo /usr/local/bin/caelestia-greeter-sync          # Plasma Login
sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh   # SDDM
```

Both greeters read their configuration when they start, so a change is visible at
the next logout rather than immediately.

**After switching display managers:**

The step above picks its branch when it runs, so switching the machine over leaves
the greeter it is no longer using configured. Which manager the machine boots is read
from `/etc/systemd/system/display-manager.service` first, so the two units still being
enabled does not send it down the wrong branch. Switch the services over, re-run the
step, and reboot:

```bash
sudo systemctl disable plasmalogin.service    # the manager being switched away from
sudo systemctl enable sddm.service
caelestia login-screen                        # configure the manager that boots now
```

`caelestia login-screen` runs the same step the installer runs, for the display
manager the machine boots. It installs the theme in the variant that is already
there, so an install made with `SDDM_THEME_VARIANT=mini` stays on mini.

**The login screen hangs, or the greeter crash-loops:**

SDDM 0.21 and newer run the greeter binary the theme asks for: `QtVersion=6` in the
theme's `metadata.desktop` runs `sddm-greeter-qt6`, and any other value - the key
being absent included - runs the Qt 5 greeter. Arch and CachyOS build that greeter
into the `sddm` package with `qt5-declarative` only an optional dependency, so it
dies on `libQt5Quick.so.5: cannot open shared object file` with exit code 127, and
SDDM respawns it instead of drawing a login screen. Caelestia's theme is Qt 6, and
the installer selects it only after checking that the greeter it asks for exists;
when that check fails the theme is installed but left unselected, and the output
names the greeter that is missing.

```bash
# What the theme asks for, and whether that greeter is installed
grep -rn '^QtVersion' /usr/share/sddm/themes/*/metadata.desktop
command -v sddm-greeter-qt6

# What the greeter last said (the theme it was told to load, and why it stopped)
journalctl -b -u sddm --no-pager | tail -n 40
```

A machine that is already stuck on the crashing greeter comes back from a TTY
(`Ctrl+Alt+F3`) or by booting with `systemd.unit=multi-user.target`. Stop SDDM, make
the theme and the greeter agree, then start it again. A theme that asks for Qt 6 needs
`sddm-greeter-qt6`, which an SDDM older than 0.21 does not have: upgrade it, or select
a theme that matches the greeter in `[Theme] Current`. Installing `qt5-declarative` is
the other way out on Arch and CachyOS: it makes the Qt 5 greeter work for the Qt 5
themes that ask for it, which is what that optional dependency is for.

### 7.7 Installer Window Rules

The installer writes four groups into `~/.config/kwinrulesrc` in priority order:
`caelestia-xwaylandvideobridge` keeps `xwaylandvideobridge` transparent and uncentered
out of switchers and taskbars (resolving a black centered box glitch on distros like Fedora; see [issue #1006](https://github.com/ladybug-me/caelestia-kde/issues/1006)),
`caelestia-pip` keeps windows whose title matches `Picture(-| )in(-| )[Pp]icture` above others,
`caelestia-dialogs` forces centered placement on dialogs, and `caelestia-opacity` gives
normal windows and dialogs an inactive opacity of 95 percent. Specific rules are intentionally
indexed before catch-all rules because KWin evaluates rules top-to-bottom and resolves attribute
conflicts using first-match-wins. Opacity is a per-activation-state key, so a window is dimmed only
while it is not focused, and the dialog rule is the one that can disagree with a placement policy
chosen in System Settings.

A group only takes effect if the index names it. `[General] rules=` is the list KWin
loads its rule groups from, and a group that is present in the file but missing from
that list is never loaded, and is removed the next time KWin saves the file. The
installer writes the list with the user's existing rules first, followed by Caelestia's
rules in priority order, with `count` set to the number of entries, so the user's own
rules are preserved and keep precedence.

To read a value back:

```bash
kreadconfig6 --file kwinrulesrc --group caelestia-opacity --key opacityinactive
kreadconfig6 --file kwinrulesrc --group caelestia-dialogs --key placement
kreadconfig6 --file kwinrulesrc --group caelestia-pip --key above
kreadconfig6 --file kwinrulesrc --group caelestia-xwaylandvideobridge --key opacityinactive
kreadconfig6 --file kwinrulesrc --group General --key rules
```

To remove the rules, delete the four `[caelestia-...]` sections out of the file, or
delete the key that switches each group on. A group that is deleted has to leave the
index with it, or the list keeps a name whose group is gone and `count` no longer
matches it. `uninstall.sh` removes the keys, strips the four names out of the list,
rewrites `count`, and deletes both index keys once no name is left. KWin does not
watch kwinrulesrc, so the reload is not optional:

```bash
kwriteconfig6 --file kwinrulesrc --group caelestia-opacity \
    --key opacityinactiverule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-dialogs \
    --key placementrule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-pip --key aboverule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-xwaylandvideobridge \
    --key opacityinactiverule --delete
qdbus6 org.kde.KWin /KWin reconfigure
```

Those commands delete each group's `*rule` key, which is the action. The match keys
are left behind, and a group that matches but carries no action is empty as far as
KWin is concerned: it discards such a rule once a window it matches has been
withdrawn, so the residue is harmless.

A window that is already open keeps what a rule forced on it. Opacity and keep-above
are set on the window itself, so an open window stays dimmed or pinned after the rules
are gone, until it is closed and reopened or another rule forces the value back. Only
windows created after the removal start clean.

The installer always applies the rules; `APPLY_WINDOW_RULES=false` is an override
for running the step by hand (`APPLY_WINDOW_RULES=false bash ./scripts/setup.sh`).
`WINDOW_OPACITY` changes the percentage the opacity rule writes.

### 7.8 Quick Share Cannot Receive Files

Before anything else, both devices have to be on the same network. A nearby device
finds this machine through an mDNS advertisement Avahi publishes on the local link and
connects to the address it resolves, so a phone on mobile data, on another Wi-Fi
network, or on the same SSID behind AP/client isolation never reaches it, and a VPN on
this machine resolves the name to an address the other device cannot route. Nothing
here can see the other device's network, so the shell cannot tell those apart from
something broken on this machine — and discovery over Bluetooth survives the wrong
network, which is why a device that cannot be reached still appears in the list.

Sending works and receiving does not: the other device is visible and asks to send,
but no incoming-file notification appears and the transfer times out. Two things
outside the shell have to be true for an incoming connection to arrive, and both fail
silently from the shell's side — a connection that is never allowed looks exactly like
a device that never tried.

The first is the Avahi daemon. It carries the mDNS advertisement a nearby device
resolves this machine through, so without it there is nothing to connect to. The
second is the firewall. The transfer listener binds a fixed port so that a rule can be
written for it ahead of time; that port has one definition,
`shell/scripts/quickshare-port`, which the plugin build bakes into the listener and the
install step reads to open the same port on the firewall. It reaches the setup helper
as `--port`. A listener on a random port could only be opened while the shell runs,
which needs administrator rights on every start.

`scripts/06-services.sh` does both during a source install. A package install leaves
them to the shell, because a package must not enable a system daemon or open a port
behind the user's back. There, the first time Quick Share is switched on the shell
checks the system through
`<qmlconfdir>/scripts/quickshare_setup.sh --status`, and if something is missing asks
through `pkexec` to put it right. The same helper is behind **Quick Share setup** on
the Quick Share settings page (Nexus → Services → Quick Share), which is the way back
if the check was declined, if the firewall changed later, or if the report reads
`SETUP=unknown` because the rule set cannot be read without root. The row says what it
knows: where the report cannot see the port, it reports that the port could not be
checked again rather than claiming a success it cannot confirm.

To see what the machine reports:

```bash
bash ~/.config/quickshell/caelestia/scripts/quickshare_setup.sh --status --port 65000
```

The report is four lines. `AVAHI` is `active`, `inactive`, `absent` or `unknown`,
`FIREWALL` names the manager in charge (`none`, `firewalld` or `ufw`), `PORT` is
`allowed`, `blocked` or `unknown`, and `SETUP` is `ok`, `needed` or `unknown`. Only
`needed` is acted on automatically; ufw reports `PORT=unknown` because reading its
rule set needs root, and guessing there would raise a password prompt for nothing.

To do it by hand, run the helper as root:

```bash
sudo bash ~/.config/quickshell/caelestia/scripts/quickshare_setup.sh --port 65000
```

It is idempotent: it enables and starts `avahi-daemon.service` (falling back to
`avahi-daemon.socket`, which is what Debian uses) and adds the transfer port plus mDNS
to whichever of firewalld or ufw is running. What it does not touch is a hand-rolled
`nftables` or `iptables` rule set, which is invisible without root — those have to
allow inbound TCP 65000 and UDP 5353 themselves. Equivalently, by manager:

```bash
systemctl enable --now avahi-daemon.service                       # the daemon

firewall-cmd --permanent --add-port=65000/tcp                     # firewalld, with
firewall-cmd --permanent --add-service=mdns                       # mDNS for discovery
firewall-cmd --reload

ufw allow 65000/tcp                                               # ufw
ufw allow 5353/udp
```

Port 65000 rather than anything lower because it sits above Linux's default ephemeral
range (32768–60999), so the listener never collides with the local port of an outgoing
connection. If it is taken by something else, Quick Share reports that it could not
listen and stays off.

---

## 8. Post-Install Issues

### 8.1 Shell Not Visible After Install

The shell only runs at **next login**. After the summary screen, the installer asks: *"Would you like to log out now? (y/N)"*

If you chose not to log out:
1. Log out manually (`Super+Ctrl+Q` or KDE menu → Leave → Log Out)
2. Log back in
3. If the shell still doesn't appear, run: `caelestia shell -d`

### 8.2 Installer Exited Prematurely (Marker Check)

The outer `setup.sh` wrapper checks if `[installer] done (success)` appears in stderr:

| Condition | Warning |
|---|---|
| Exit 0 but elapsed < 3 seconds without marker | **"INSTALLER EXITED PREMATURELY"** |
| Exit 0 but elapsed > 3 seconds without marker | **"INSTALLER EXITED UNEXPECTEDLY"** |

### 8.3 CONFIRM_ARG Behavior

The configuration menu sets `CONFIRM_ARG` as `true`/`false`. The installer converts it per-script context:
- Some scripts use `-n "$CONFIRM_ARG"` (non-empty = auto-confirm)
- The installer writes an `[installer] done (success)` marker line to its stderr log, and `setup.sh` greps that log for it to decide whether the install succeeded (see `scripts/setup.sh`).

### 8.4 Stale Lock Files

If the script is killed with **SIGKILL** (not SIGTERM), lock files may persist:

| Lock File | Script |
|---|---|
| `${XDG_RUNTIME_DIR:-/tmp}/caelestia-setup.lock` | `setup.sh` |
| `${XDG_RUNTIME_DIR:-/tmp}/caelestia-update.lock` | `update.sh` |

**Always use Ctrl+C (SIGINT)** which is handled gracefully. Remove stale locks:
```bash
rm -f "${XDG_RUNTIME_DIR:-/tmp}/caelestia-setup.lock"
rm -f "${XDG_RUNTIME_DIR:-/tmp}/caelestia-update.lock"
```

### 8.5 Update.sh Fails

| Symptom | Cause |
|---|---|
| `git pull` fails | Uncommitted changes exist. The updater auto-stashes, but conflicts may remain. |
| Submodule update fails | Network issue or GitHub down. Retry later. |
| CMake configure fails | New dependencies added since last install. Check error output. |

### 8.6 Installer Stops After a System Upgrade

`00a-system-update.sh` upgrades the system first, and later steps compile and load the Caelestia
KWin plugin into the session that is **already running**. If the upgrade replaced `kwin`,
`plasma-workspace`, `libplasma`, `qt6-base` or `qt6-declarative`, the live session still holds the
old libraries in memory while the on-disk headers are new, so the installer stops and names the
packages that moved:

```
[ERR]   The upgrade replaced packages the running session still has loaded in memory:
[ERR]   had kwin 6.4.0-1
[ERR]   now kwin 6.4.1-1
```

This is the partial-upgrade state Arch documents as "do not keep using the session", not a broken
install. Log out and back in (or reboot) and run the installer again: the upgrade is already
applied, so nothing is downloaded twice and the remaining steps run against a session that matches
the files on disk.

Choosing **ignore** at the prompt continues anyway. The plugin build may then fail with Wayland or
ABI errors that look unrelated to the upgrade.

### 8.7 Checksums on Downloaded Artifacts

Three artifacts the installer fetches are checked against the `.sha256` published beside them. A
mismatch always means the file is not used. What happens when a release publishes no checksum at
all depends on what the artifact is for:

| Artifact | No published checksum | On mismatch |
|---|---|---|
| Prebuilt shell tarball (`08-build-shell.sh`, extracted over `$HOME`) | Warns and extracts | Builds the shell locally instead |
| Prebuilt installer binary (executed straight away) | Compiles the installer locally instead | Same |
| Prebuilt CAVA SDK (unpacked into `/usr` as root) | Warns and unpacks | Not unpacked; `libcava` comes from the repositories instead |

Messages to expect:

| Message | Meaning |
|---|---|
| `Prebuilt shell artifacts match the published checksum.` | Normal: the prebuilt archive is installed. |
| `No published checksum for ... - extracting without verification.` | The release predates checksums. The install continues. |
| `No published checksum for the prebuilt installer - compiling locally.` | The release predates checksums. The installer is built from source instead. |
| `No published checksum for ... - unpacking without verification.` | The CAVA release publishes no checksums. The SDK is unpacked anyway. |
| `No prebuilt shell artifacts published for <tag> (Qt <abi>) - falling back to a local build.` | The release carries no archive for this Qt feature version. The step builds locally instead. |
| `Checksum mismatch for ...` | The download was truncated or tampered with. That artifact is not used. |

A mismatch is not fatal for any of the three: each one has somewhere else to get what it needs,
and none of them is used in a damaged state.

The CAVA SDK is the one artifact that still installs without verification. Its releases come from
a separate repository that publishes no checksums, and refusing them would only move the same work
to the `libcava` package. Publishing an `<asset>.sha256` in that repository turns verification on
with no change here.

The archive is also only used for the revision it was built from: `main` sitting on its remote
tip, or a checkout that is exactly the released tag (an update pinned to a version). A branch, a
stale `main`, or a checkout carrying commits of its own builds locally, because the archive would
replace that tree with the release's. `main` that has moved on since its last release cannot be
told apart from that release, so it is installed as the release its `version.env` names.

---

## 9. Uninstall Issues

### 9.1 Uninstalling from the Shell

Settings > About > Uninstall Caelestia opens the uninstaller in a terminal, where it
asks for confirmation of its own. The button finds the script by looking where a
checkout is expected, in this order:

1. `$CAELESTIA_DIR/uninstall.sh`
2. `~/caelestia-kde/uninstall.sh`
3. `$(cat ~/.config/quickshell/caelestia/.checkout)/uninstall.sh`
4. `~/.config/caelestia-update/repo/uninstall.sh`
5. `~/.cache/caelestia-update-repo/uninstall.sh`

The third is the checkout the running shell was installed from, recorded by the
installer. It is what makes a clone that is not named `~/caelestia-kde` - a manual
`git clone` anywhere else - still uninstallable from here; reinstall or update once
for an install that predates that recording. It is tried after `~/caelestia-kde`
because that is where an install's backups live, and the uninstaller restores from
its own checkout's `backups/`.

A packaged install has no script, so the row names the command that removes it instead
(`sudo pacman -Rns caelestia-kde`, or the `dnf`/`apt-get` equivalent).

### 9.2 No Backups Available

Backups are stored in `$BUNDLE_DIR/backups/YYYYMMDD_HHMMSS/`. If you moved or deleted the repository, backups are gone.

### 9.3 konsave Restore Fails

If the `.knsv` archive is corrupted or konsave can't be installed:
- Falls back to manual restore of individual config files
- If `python3 -m venv` fails (missing `python3-venv`), theme data can't be restored

**Expected warning when restoring a Caelestia backup:**
> *"The selected backup contains Caelestia configurations. Restoring this backup will NOT revert to a clean KDE desktop!"*

### 9.4 Shell RC Files Not Cleaned

The uninstaller uses state files (`shellrc/bashrc.state`, etc.) to determine whether to restore or remove shell config files. If these are missing (older installer version), a fallback `sed` cleanup removes `QML2_IMPORT_PATH` and `CAELESTIA_LIB_DIR` lines.

### 9.5 The Login Shell Is Not Changed Back

The installer only changes the login shell to `fish` when it can record the previous one in `backups/YYYYMMDD_HHMMSS/previous_shell.txt`. The uninstaller only reverses that with the same file. With no backup there is no record that the shell was ever changed, so it is left exactly as it is and the run reports:

> *"No shell backup was recorded, so the login shell (/usr/bin/fish) is left as it is."*

### 9.6 Package Removal Leaves Dependencies

Package removal is optional. It uses `yay -Rns` / `dnf remove` which does NOT remove:
- Dependencies pulled in automatically (unless `-s` handles them)
- Packages installed outside the defined lists
- `base-devel` or build tools that existed before install

### 9.6 Legacy Input Group Membership

Installs from before the `/dev/uinput` rule moved to `TAG+="uaccess"` added the
user to the `input` group. The installer removes that membership when it finds the
old `/etc/udev/rules.d/80-uinput.rules`, and the uninstaller runs
`sudo gpasswd -d $USER input`. Either way it takes effect on next login.

### 9.7 What the Uninstaller Keeps

The uninstaller removes the install and its last traces, but keeps what is the
user's own:

- `~/.config/caelestia/shell.json`, `keybinds.json` and `cli.json` - the shell's
  settings, so a reinstall keeps them. `stolen-shortcuts.json` and
  `stolen-screen-edges.json` are removed: they are crash recovery that only the
  running shell can act on, and with the shell gone they would strand the KDE
  shortcuts it took.
- `~/.config/caelestia-update/` and `~/.cache/caelestia-update-repo` - the updater's
  checkout and cache. Remove them yourself with the command in [10.1](#101-fixing-caelestia-updater-recommended).

---

## 10. Update Issues

### 10.1 Fixing caelestia updater (Recommended)

By deleting the build cache and the update checker cache:

```bash
rm -rf ~/.config/caelestia-update/repo ~/.cache/caelestia-update-repo
```

**Note:** This will have the updater clone the repo again which takes time according to your internet speed. Hence, the logs might seem stuck or tell you to restart the process, but just wait for it to finish.

### 10.2 Using update.sh

You can simply run `bash update.sh` in the cloned repo folder (~/caelestia-kde) to update to latest version.

### 10.3 Install latest version from repo

Run the following command to simply install the latest shell using installer.
```bash
curl -fsSL https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/install.sh | sh
```

- If it gives an error due to already present `~/caelestia-kde` directory in your pc, then remove that directory first and then run the above command. **Make sure to copy the `backups/` folder somewhere and then put it back here after installation completes.**

---

## 11. Diagnostic Commands Reference

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
| Krita/Inkscape crashes on copy/paste | `systemctl --user stop cliphist.service` stops the crash; update Caelestia so `wl-clip-persist` runs with the `--all-mime-type-regex` filter (see 3.9) |
