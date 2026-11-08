# Lock screen architecture

How Caelestia's lock screen replaces the stock Plasma greeter, and what the pieces
inside `src/kde/shells/caelestia.desktop/` do.

![The Caelestia lock screen](../../assets/lockscreen-screenshot.png)

## A Plasma shell package

`kscreenlocker_greet` runs the lock screen session and owns authentication. It
loads a shell package — the same mechanism the desktop uses — so Caelestia
supplies a `Plasma/Shell` KPackage, and `plasmashellrc` points the greeter at it:

```ini
[Shell]
ShellPackage=caelestia.desktop
```

The package is deployed to
`~/.local/share/plasma/shells/caelestia.desktop/`.

Because the greeter renders in-process under KWin, the UI is QtQuick on the
compositor's GPU; a nested Wayland proxy would compose it in software instead.
Authentication is the greeter's own backend (`authenticator`): PAM, its error
reporting, grace locks, and fingerprint readers.

## Components

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

## Blur

A Wayland greeter gets no compositor background blur, so the lock screen blurs
its own copy of the wallpaper. The greeter already has the desktop wallpaper as
an in-process item, so `LockScreenUi.qml` runs it through `FastBlur` with a
radius of 64 and maps the result onto the background container (`lockBg`) and the
layout regions with a `ShaderEffectSource` clipped by an `OpacityMask` that
matches the container's corner radius. Card widgets sit on translucent surfaces
(`Qt.rgba(..., 0.55)`) over that backdrop.

## Sizes

All three constants scale with `lockHeight / 1080`:

| Constant | Value at 1080p | Use |
|---|---|---|
| `bgRadius` | 42 | Outer background container |
| `bgMargin` | 16 | Padding between the container and the cards |
| `cardRadius` | 26 (`bgRadius - bgMargin`) | Card widgets |

## Avatars

`ProfileAvatar.qml` prefers `~/.face` from the home directory, falls back to the
system account picture (`kscreenlocker_userImage`), and falls back again to the
Material Symbols person icon.

## Layout

Landscape is a three-column layout: weather, caelestiafetch and media on the
left; clock, avatar and password pill in the centre; resources and the
notification dock on the right. Portrait collapses to a single centred column.

## Notifications

The dock does not read the shell's persisted `notifs.json`. That file is a
debounced copy of the live model and trails it by three to ten seconds, which
made the lock screen disagree with the desktop notification page.

`components/NotifSync.qml` owns the dock's data instead. While notifications are
on screen it runs `notifs list` every two seconds, and the page passes the
snapshot to `NotifDock`. The shell answers with `{ quiet, items }` — its live list
through the same `toPlainList()` it persists, plus whether popups are quiet — so
a notification arriving, expiring or being cleared on the desktop appears or
disappears here within a couple of seconds. Clear-all runs `notifs clear`, which
empties the desktop page with it.

Do-not-disturb stays the shell's, held by name. The dino game claims
`notifs setDndHold lockGame true` while it runs and releases that hold when it
ends, and the shell keeps holds apart from the user's own switch: a game ending
can neither clear a do-not-disturb the user set nor one a focus session holds.

Every call goes through `components/ShellCall.qml`, which returns stdout alone. The
greeter cannot read the shell's models, and under a non-UTF-8 locale Qt put its own
warning on stdout ahead of the JSON.

## Deploying and testing

[`scripts/08-build-shell.sh`](../../scripts/08-build-shell.sh) deploys the
greeter; [`scripts/02-packages.sh`](../../scripts/02-packages.sh) only installs
the Python tooling and matugen the build needs.

```bash
# By hand
mkdir -p ~/.local/share/plasma/shells/
cp -r src/kde/shells/caelestia.desktop ~/.local/share/plasma/shells/
kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop"
```

The greeter can be run in a window without locking the session:

```bash
/usr/lib/kscreenlocker_greet --testing
```

## Reverting

[`uninstall.sh`](../../uninstall.sh) does all three of these; by hand:

```bash
# Back to the stock shell package
kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" --delete

# Back to the Breeze greeter theme
kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" "org.kde.breeze.desktop"

# Remove the local package copy
rm -rf ~/.local/share/plasma/shells/caelestia.desktop
```
