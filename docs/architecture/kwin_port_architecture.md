# KWin port architecture

The C++ plugin behind the shell's KWin integration, and the API it exposes to QML.

![The Caelestia shell](../../assets/shell-screenshot.png)

## Why the plugin exists

The port began with a "fake Hyprland" layer: a KWin script that pushed window data over D-Bus, a Python daemon that listened, and a mock `hyprctl` that returned Hyprland-shaped JSON. Every window operation crossed two process boundaries, and the shell saw little of KDE's own API.

An interim version dropped the daemon and ran `qdbus6` through `QProcess` to inject temporary KWin scripts. That removed one hop, but window state still arrived over D-Bus and depended on external processes.

The current plugin talks to KWin and Wayland in-process:

- `KWinActiveWindowBridge` binds the `plasma-window-management` Wayland protocol through `PlasmaWindows`. It tracks the active window, the global window list and window states without D-Bus round trips or script injection.
- `KWinWorkspaceState` reads the virtual desktop manager over D-Bus and follows trackpad swipes through a `QLocalSocket` server (`caelestia-workspace-tracker`).
- `GlobalShortcut` registers system-wide keys with `kglobalaccel` from C++.

## QML API

The C++ singletons below are exposed to QML as `Caelestia.*`.

### KWinActiveWindowBridge

Real-time window, monitor and window-list state from Plasma Window Management.

Properties:

- `activeWindow` (`QVariantMap`): the focused window. Fields: `address` (string UUID), `title`, `class` (app id), `fullscreen`, `maximized`.
- `activeOutputName` (`QString`): the output the active window is on.
- `windowList` (`QVariantList`): every window. Each map carries `address`, `title`, `class`, `floating`, `fullscreen`, `x`, `y`, `width`, `height`.

Methods:

- `focusWindow(address)`
- `closeWindow(address)`
- `minimizeWindow(address)`
- `maximizeWindow(address, horz = true, vert = true)`
- `setMaximized(address, maximized)`
- `setFullscreen(address, fullscreen)`
- `raiseWindow(address)`
- `setWindowProperty(address, property, enable)`: toggles legacy states.
- `setWindowDesktop(address, desktopId)`: `-1` for the current desktop, `-2` for all.
- `setActiveOutputName(outputName)`
- `refreshWindows()`: kept for backward compatibility.

### KWinWorkspaceState

Virtual desktops and trackpad swipe state.

Properties:

- `activeId` (`int`): the active desktop, 1-based.
- `workspaces` (`QVariantList`): each map carries `id` (string UUID), `name`, `index` (1-based) and `active`.
- `swipeOffset` (`double`): the fractional offset of a swipe in progress, for animations.

Methods:

- `switchTo(id)`: accepts a UUID, an id or a name.
- `createWorkspace(name = "")`
- `removeWorkspace(id)`
- `setDesktop(desktopId)`: 1-based index.
- `nextDesktop()` / `previousDesktop()`: wrap at the ends.

### GlobalShortcut

Registers a shortcut through `kglobalaccel`.

Properties: `name`, `key` (semicolon-separated multi-key), `description`.
Signal: `activated()`.

### KeybindsModel and GlobalShortcutDispatcher

- `GlobalShortcutDispatcher` relays signals between instances and keeps the collision index (`key → friendly label`), backed by `stolen-shortcuts.json`.
- `KeybindsModel` is a `QAbstractListModel` that loads defaults, merges overrides from `${XDG_CONFIG_HOME:-~/.config}/caelestia/keybinds.json`, and drives the Nexus shortcut manager.

Full detail on stealing, conflicts, crash recovery, the diff-based update and the Nexus UI is in [`shortcut_architecture.md`](shortcut_architecture.md).

## How shortcuts load

`Shortcuts.qml` under `shell/modules/` declares every built-in shortcut through the `CustomShortcut` wrapper in `shell/components/misc/`. The wrapper checks the environment at startup:

- Hyprland loads `Quickshell.Hyprland.GlobalShortcut`, with bindings from `hyprland.conf`.
- KWin loads `Caelestia.GlobalShortcut`, which registers with KDE's global shortcut daemon.

See [`shortcut_architecture.md`](shortcut_architecture.md) for the loading pipeline and the override file.
