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
| `[FATAL] Failed to build the Caelestia installer` | General CMake/make error | The failure output prints the last 60 log lines and the log's full path (a fresh `/tmp/caelestia-build-log.*` file) - read that file |
| Compiler error about modern C++ features | GCC older than 10 | Ensure GCC 10+ is installed: `g++ --version` |
| Exit 139 (SIGSEGV) at runtime | C++ bug in the TUI | The failure output prints the stderr log's full path (a fresh `/tmp/caelestia-installer-err.*` file) - read that file |
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

**matugen on Fedora:** there is no package for it, and it is what generates the palette. The installer reports it when it is missing; `cargo install matugen` fixes it.

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
| Lock screen fails or crashes | Greeter files missing or corrupted in `~/.local/share/plasma/shells/`. | Re-deploy via `BUNDLE_DIR=. ./scripts/02-packages.sh` or `cp -r src/kde/shells/caelestia.desktop ~/.local/share/plasma/shells/`. |
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

The installer configures exactly **5 desktops**. If you had a different count before:
- Re-run `scripts/09-system-tweaks.sh` to re-apply
- The uninstaller resets desktop count to `1`

### 5.4 Keyboard Shortcut Conflicts

Caelestia's `GlobalShortcut` system uses `kglobalacceld`. When it registers a shortcut that conflicts with another app, it "steals" the binding and records it in:

```text
~/.config/caelestia/stolen-shortcuts.json
```

**If shortcuts are missing or wrong:**
```bash
rm -f ~/.config/caelestia/stolen-shortcuts.json
systemctl --user status plasma-kglobalaccel.service
```

If `keyd` is active and manages Meta+1..5, the tweak script skips KWin bindings for those combos to avoid conflicts.

### 5.5 Terminal Sequence Bleeding (Garbled Output)

If ANSI escape sequences leak from the `caelestia` CLI into your terminal:

```bash
cat $XDG_CACHE_HOME/caelestia-kde/failed_patches.txt
```

If `Caelestia CLI Theme Sequence Patch` appears in the failed list, re-run:
```bash
bash scripts/09-system-tweaks.sh
```

---

## 6. Network & Proxy Issues

### 6.1 Pacman Mirror Ranking Fails

On CachyOS, the installer uses the native `cachyos-rate-mirrors` command, which ranks both Arch and CachyOS repositories. Other Arch-based systems use `reflector` as a fallback. Fedora refreshes its configured DNF metadata and Debian-based systems refresh their configured APT indexes; neither needs mirror-list rewriting during installation. Failure modes:
- **Offline:** Mirror ranking fails and the existing mirror lists are kept
- **cachyos-rate-mirrors unavailable:** CachyOS mirror ranking is skipped and the existing mirror lists are kept
- **reflector not installed:** On non-Cachy Arch systems, it is auto-installed via `pacman -Sy reflector`; if that fails, ranking is skipped
- **DNF or APT refresh fails:** Fedora/Debian package installation continues and reports the package-manager error later if the configured sources remain unavailable

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

### 7.7 Installer Window Rules

The installer writes three groups into `~/.config/kwinrulesrc`. `caelestia-opacity`
gives normal windows and dialogs an inactive opacity of 95 percent,
`caelestia-dialogs` forces centered placement on dialogs, and `caelestia-pip` keeps
windows whose title matches `Picture(-| )in(-| )[Pp]icture` above others. Opacity is
a per-activation-state key, so a window is dimmed only while it is not focused, and
the dialog rule is the one that can disagree with a placement policy chosen in
System Settings.

A group only takes effect if the index names it. `[General] rules=` is the list KWin
loads its rule groups from, and a group that is present in the file but missing from
that list is never loaded, and is removed the next time KWin saves the file. The
installer writes the list as the union of the entries that were already in it, every
group the file holds and its own three names, with `count` set to the number of
entries, so the user's own rules are named alongside ours and keep their order.

To read a value back:

```bash
kreadconfig6 --file kwinrulesrc --group caelestia-opacity --key opacityinactive
kreadconfig6 --file kwinrulesrc --group caelestia-dialogs --key placement
kreadconfig6 --file kwinrulesrc --group caelestia-pip --key above
kreadconfig6 --file kwinrulesrc --group General --key rules
```

To remove the rules, delete the three `[caelestia-...]` sections out of the file, or
delete the key that switches each group on. A group that is deleted has to leave the
index with it, or the list keeps a name whose group is gone and `count` no longer
matches it. `uninstall.sh` removes the keys, strips the three names out of the list,
rewrites `count`, and deletes both index keys once no name is left. KWin does not
watch kwinrulesrc, so the reload is not optional:

```bash
kwriteconfig6 --file kwinrulesrc --group caelestia-opacity \
    --key opacityinactiverule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-dialogs \
    --key placementrule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-pip --key aboverule --delete
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

### 9.1 No Backups Available

Backups are stored in `$BUNDLE_DIR/backups/YYYYMMDD_HHMMSS/`. If you moved or deleted the repository, backups are gone.

### 9.2 konsave Restore Fails

If the `.knsv` archive is corrupted or konsave can't be installed:
- Falls back to manual restore of individual config files
- If `python3 -m venv` fails (missing `python3-venv`), theme data can't be restored

**Expected warning when restoring a Caelestia backup:**
> *"The selected backup contains Caelestia configurations. Restoring this backup will NOT revert to a clean KDE desktop!"*

### 9.3 Shell RC Files Not Cleaned

The uninstaller uses state files (`shellrc/bashrc.state`, etc.) to determine whether to restore or remove shell config files. If these are missing (older installer version), a fallback `sed` cleanup removes `QML2_IMPORT_PATH` and `CAELESTIA_LIB_DIR` lines.

### 9.4 Package Removal Leaves Dependencies

Package removal is optional. It uses `yay -Rns` / `dnf remove` which does NOT remove:
- Dependencies pulled in automatically (unless `-s` handles it)
- Packages installed outside the defined lists
- `base-devel` or build tools that existed before install

### 9.5 Legacy Input Group Membership

Installs from before the `/dev/uinput` rule moved to `TAG+="uaccess"` added the
user to the `input` group. The installer removes that membership when it finds the
old `/etc/udev/rules.d/80-uinput.rules`, and the uninstaller runs
`sudo gpasswd -d $USER input`. Either way it takes effect on next login.

### 9.6 Failed Patches Tracking

Failed patches are logged to:
```text
$XDG_CACHE_HOME/caelestia-kde/failed_patches.txt
```

Possible entries:
- `Caelestia CLI Hyprctl Mock Patch`
- `Caelestia CLI Record/Dolphin Patch`
- `Caelestia CLI Theme Sequence Patch`

These are **cosmetic** — the shell works without them, but certain features (screenshot, recording, terminal colors) may be degraded.

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

# View failed patches log
cat $XDG_CACHE_HOME/caelestia-kde/failed_patches.txt 2>/dev/null

# View installer build log (the path is printed when the build fails;
# setup.sh names it /tmp/caelestia-build-log.XXXXXX)
cat /tmp/caelestia-build-log.* 2>/dev/null | tail -60

# View installer stderr log (same: the exact file is printed on failure)
cat /tmp/caelestia-installer-err.* 2>/dev/null
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
| Installer compiles but flashes/exits | The failure output names the stderr log it captured (a `/tmp/caelestia-installer-err.*` file) |
| Recording not working | Verify `gpu-screen-recorder` is installed |
| Screenshot not working | Verify `spectacle` is installed |
