# Lock screen architecture

How the Caelestia lock screen is packaged, drawn, and authenticated on Plasma 6.

![The Caelestia lock screen](../../assets/lockscreen-screenshot.png)

## Why a Plasma shell package

`kscreenlocker_greet` owns the lock session and authentication. Caelestia plugs into that process as a `Plasma/Shell` KPackage at `~/.local/share/plasma/shells/caelestia.desktop/`, rather than running a nested compositor or a Wayland proxy. `[Shell] ShellPackage=caelestia.desktop` in `~/.config/plasmashellrc` makes the greeter load it instead of the stock shell.

The greeter renders in QtQuick inside KWin's compositor, so the lock screen is a composited surface with no extra process between it and the display.

## Authentication

`authenticator` is KDE's ScreenLocker backend. The greeter talks to it directly for password, grace-lock and fingerprint handling.

The backend keeps one prompt open until the password answers it. Since the kscreenlocker 6.8 PAM rework, a second `startAuthenticating()` while that prompt is live is treated as a failed login. [`AuthHandler.qml`](../../src/kde/shells/caelestia.desktop/contents/lockscreen/components/AuthHandler.qml) tracks `promptPending` and never restarts authentication while a prompt (echo-off or echo-on) waits. The heartbeat and key-press paths only start a conversation when none is live, and a scan that did not match runs beside the password prompt instead of ending it.

Neither `busy` nor the prompt strings can stand in for `promptPending`: `busy` is false while a prompt waits, `prompt` and `promptForSecret` keep their last value after the conversation ends, and they also change once with no prompt behind them when the backend resets its authenticator.

## Component structure

The greeter source lives in `src/kde/shells/caelestia.desktop/`:

```text
src/kde/shells/caelestia.desktop/
├── metadata.json                          # KPackage manifest required by kpackagetool6 / plasmashell.
│                                          # Declares KPackageStructure=Plasma/Shell so the package is
│                                          # recognized as a greeter shell, not a plugin or applet.
└── contents/
    └── lockscreen/
        ├── LockScreen.qml                 # Main shell entry wrapper (exposes `locked` to kscreenlocker)
        ├── LockScreenUi.qml               # Root UI layout, scaling, wallpaper blur, & palette
        ├── components/
        │   ├── ClockWidget.qml            # Stacked hour/minute clock & formatted date
        │   ├── GreetingPill.qml           # Time-based greeting pill with weather/time icon
        │   ├── ProfileAvatar.qml          # ~/.face avatar with M3 pentagon clip and fallback
        │   ├── PasswordPill.qml           # Password input with animated M3 shapes & fingerprint icon
        │   ├── WeatherCard.qml            # Weather forecast, temperatures, and condition icon
        │   ├── CaelestiafetchCard.qml     # System information card with Caelestia logo & palette dots
        │   ├── MediaCard.qml              # MPRIS media player with rounded album art and playback controls
        │   ├── ResourcesCard.qml          # CPU, RAM, and Disk resource meters with live temp badge
        │   ├── NotifDock.qml              # Categorized notification dock with expandable groups
        │   ├── NotifSync.qml              # The dock's live snapshot: polling, clear-all and the game's DND hold
        │   └── ShellCall.qml              # One caelestia-shell-ipc call, stdout only
        └── scripts/
            └── sysinfo.py                 # system info fetch script
```

## Blur and radii

KWin does not apply compositor background blur to out-of-process greeter windows. The greeter sources the in-process `wallpaper` item through `FastBlur` (radius 64) instead.

The blurred wallpaper is mapped onto the container (`lockBg`) and the layout regions through a live `ShaderEffectSource`, clipped by an `OpacityMask` that follows `bgRadius`. Card widgets use translucent surfaces (`Qt.rgba(..., 0.55)`).

`bgRadius` is 42 px, scaled with screen height. `bgMargin` is 16 px, and card corners use `bgRadius - bgMargin` (26 px at the default).

## Avatar

[`ProfileAvatar.qml`](../../src/kde/shells/caelestia.desktop/contents/lockscreen/components/ProfileAvatar.qml) prefers `~/.face`. When that is absent it falls back to the system account picture (`kscreenlocker_userImage`) and then to the Material Symbols user icon.

## Layout

Landscape is the default: weather, Caelestiafetch and media on the left; clock, avatar and password pill in the centre; resources and the notification dock on the right. Portrait collapses to one centred column.

## Notification sync

The dock never reads the shell's persisted `notifs.json`. That file is a debounced copy of the live model and trails it by 3–10 s, which made the lock screen disagree with the desktop notification page.

`components/NotifSync.qml` owns the dock's data. It polls `notifs list` every 2 s while notifications are shown and holds the snapshot the page hands to `NotifDock`. The shell answers with `{ quiet, items }`: its live list through the same `toPlainList()` it persists, plus whether popups are quiet. Notifications that arrive, expire or are cleared on the desktop show up or vanish here within a couple of seconds.

Clear-all runs `notifs clear`, so the desktop page empties with it.

Do-not-disturb stays the shell's, held by name. The dino game claims `notifs setDndHold lockGame true` while it runs and releases the hold afterwards. Holds are kept apart from the user's own switch, so a game ending can neither switch off a do-not-disturb the user set nor one a focus session is holding.

Every call goes through `components/ShellCall.qml`, which returns stdout alone. The greeter cannot see the shell's models, and a non-UTF-8 locale used to put Qt's warning on stdout in front of the JSON.

## Deployment

The greeter is deployed during the shell build ([`scripts/08-build-shell.sh`](../../scripts/08-build-shell.sh)). [`scripts/02-packages.sh`](../../scripts/02-packages.sh) only sets up the Python tooling and matugen the build needs.

```bash
# Manual installation
mkdir -p ~/.local/share/plasma/shells/
cp -r src/kde/shells/caelestia.desktop ~/.local/share/plasma/shells/
kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop"
```

## Testing

The UI can be tested in a non-blocking window without locking the session:

```bash
/usr/lib/kscreenlocker_greet --testing
```

[`tests/test_lockscreen_auth_loop.sh`](../../tests/test_lockscreen_auth_loop.sh) drives the real [`AuthHandler.qml`](../../src/kde/shells/caelestia.desktop/contents/lockscreen/components/AuthHandler.qml) through the PySide6 harness in [`tests/qml/lockscreen_auth/`](../../tests/qml/lockscreen_auth/). The harness stands in for `authenticator` with kscreenlocker's PAM semantics: a prompt stays open until it is answered, a concurrent `Authenticate()` is refused, and `respond()` without a pending prompt is dropped. It runs in the isolated suite and skips when PySide6 is not installed:

```bash
tests/run-tests.sh --suite isolated test_lockscreen_auth_loop
python3 tests/qml/lockscreen_auth/run.py A B C F G H I D   # A idle, B first attempt, C retry, F typing, G failed scan, H authenticator reset, I echo-on prompt, D after 15 s idle
```

## Uninstalling

To return to the stock KDE Breeze lock screen:

```bash
# Reset the shell package to KDE's default
kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" --delete

# Restore the default Breeze greeter theme
kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" "org.kde.breeze.desktop"

# Optional: remove the local shell files
rm -rf ~/.local/share/plasma/shells/caelestia.desktop
```

[`./uninstall.sh`](../../uninstall.sh) does the same.
