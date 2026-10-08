id: DOC-ARCH-KWIN
title: KWin port architecture (native backend)
source: docs/architecture/kwin_port_architecture.md
tags: kwin, bridge, kwinactivewindowbridge, kwinworkspacestate, plasma-window-management, wayland, globalshortcut, kglobalaccel, hyprctl, workspace tracker, qlocalsocket, window list, api
synonyms: kwin bridge, what is the kwin bridge, hyprctl replacement native plugins, kwinactivewindowbridge kwinworkspacestate globalshortcut, window tracking backend

This document covers the C++ plugin backend and the API available to QML components.



---

## 1. Architectural Evolution: The Native Backend

### The Legacy Approach
Previously, the KDE port relied on a "fake Hyprland" wrapper architecture:
1. **KWin JS Script** (`main.js`): Ran continuously in KWin, pushing window data over D-Bus.
2. **Python Daemon** (`qs-kwin-bridge.py`): A background service that listened to these D-Bus signals.
3. **Mock `hyprctl`**: A fake Python mock returning JSON formatted exactly like Hyprland's native output.

**The Problem**: This involved too many IPC hops, was prone to lagging, required a background daemon, and heavily restricted the shell from using KDE's native capabilities.

### The Interim Port
Initially, the port ripped out the Python daemon and used decoupled `QProcess` tasks executing `qdbus6` to inject temporary KWin scripts and manage windows. While more reliable, it still relied heavily on D-Bus and external processes.

### The Current Native Wayland Approach
The current architecture communicates directly with KWin and Wayland via native **C++ Quickshell Plugins**, utilizing pure Wayland protocols and optimized IPC for maximum performance and reliability:

1. **`KWinActiveWindowBridge` (C++ / Wayland Protocol)**
   - Binds directly to the `plasma-window-management` Wayland protocol via `PlasmaWindows`.
   - Tracks active windows, global window lists, and manages window states natively without D-Bus overhead or KWin script injection.
2. **`KWinWorkspaceState` (C++ / D-Bus & Local Sockets)**
   - Interfaces with KDE Plasma's Virtual Desktop Manager over optimized D-Bus calls.
   - Handles **Workspace Swipe Tracking** for trackpads via a native `QLocalSocket` tracking server (`caelestia-workspace-tracker`).
3. **`GlobalShortcut` (C++)**
   - Standardizes system-wide keyboard shortcuts in C++, routing through KDE's `kglobalaccel` seamlessly.

---

## 2. Developer API Reference (QML)

The following native C++ singletons and components are exposed to QML to interact with KDE natively.

### `KWinActiveWindowBridge` (Singleton)
Provides real-time information about active windows, monitors, and the global window list natively via Plasma Window Management.

**Properties:**
* `activeWindow` (`QVariantMap`): The currently focused window.
  * Fields: `address` (String uuid), `title` (String), `class` (String appId), `fullscreen` (Boolean), `maximized` (Boolean).
* `activeOutputName` (`QString`): The name of the monitor/output where the active window resides.
* `windowList` (`QVariantList` of `QVariantMap`): An array containing all active windows across the system.
  * Each map contains: `address`, `title`, `class`, `floating`, `fullscreen`, `x`, `y`, `width`, `height`.

**Methods (Invokables):**
* `void focusWindow(const QString &address)`: Brings the specified window to the front and focuses it.
* `void closeWindow(const QString &address)`: Gracefully requests the specified window to close.
* `void minimizeWindow(const QString &address)`: Minimizes the specified window.
* `void maximizeWindow(const QString &address, bool horz = true, bool vert = true)`: Maximizes the window.
* `void setMaximized(const QString &address, bool maximized)`: Sets or unsets the maximized state.
* `void setFullscreen(const QString &address, bool fullscreen)`: Sets or unsets the fullscreen state.
* `void raiseWindow(const QString &address)`: Raises the window to the top of the stack.
* `void setWindowProperty(const QString &address, const QString &property, bool enable)`: Toggles legacy states.
* `void setWindowDesktop(const QString &address, int desktopId)`: Moves window to desktop (-1 for current, -2 for all).
* `void setActiveOutputName(const QString &outputName)`: Manually sets the active output tracker.
* `void refreshWindows()`: Kept for backward compatibility.

### `KWinWorkspaceState` (Singleton)
Provides real-time tracking of KDE Plasma virtual desktops (workspaces) and trackpad swipe gestures.

**Properties:**
* `activeId` (`int`): The ID of the currently active virtual desktop (1-indexed).
* `workspaces` (`QVariantList` of `QVariantMap`): A list of all virtual desktops.
  * Each map contains: `id` (String UUID), `name` (String), `index` (Integer 1-based), `active` (Boolean).
* `swipeOffset` (`double`): Real-time fractional offset representing a trackpad swipe in progress (for animations).

**Methods (Invokables):**
* `void switchTo(const QString& id)`: Switches the active workspace to the provided desktop UUID, ID, or name.
* `void createWorkspace(const QString& name = "")`: Creates a new virtual desktop.
* `void removeWorkspace(const QString& id)`: Removes the specified virtual desktop.
* `void setDesktop(int desktopId)`: Switches the current desktop workspace by 1-based index.
* `void nextDesktop()`: Switches to the next adjacent desktop, wrapping around at the end.
* `void previousDesktop()`: Switches to the previous adjacent desktop, wrapping around at the beginning.

### `GlobalShortcut` (Component)
A QML component used to register global keyboard shortcuts through KDE's native `kglobalaccel` system.

**Properties:** `name`, `key` (semicolon-separated multi-key), `description`
**Signal:** `activated()`

### `KeybindsModel` & `GlobalShortcutDispatcher` (Singletons)
- **`GlobalShortcutDispatcher`**: Singleton relay for cross-instance signals and the central **collision index** (`key → friendly label`), backed by `stolen-shortcuts.json`.
- **`KeybindsModel`**: `QAbstractListModel` singleton that loads defaults, merges user overrides from `~/.config/caelestia/keybinds.json`, and drives the Nexus shortcut manager UI.

> **Full documentation** — shortcut theft, conflict resolution, crash-safe recovery, the diff-based update logic, and the Nexus UI integration are all covered in detail in **[`docs/shortcut_architecture.md`](shortcut_architecture.md)**.

---

## 3. How Shortcuts are Loaded (`Shortcuts.qml`)

All keyboard shortcuts in Caelestia are declared inside `Shortcuts.qml` under `shell/modules/` using the `CustomShortcut` QML wrapper under `shell/components/misc/`.

The `CustomShortcut` wrapper dynamically inspects the environment at startup:
- **Hyprland**: loads `Quickshell.Hyprland.GlobalShortcut`; bindings come from `hyprland.conf`.
- **KDE (KWin)**: loads `Caelestia.GlobalShortcut`, registering directly with KDE's global shortcut daemon.

See [`docs/shortcut_architecture.md`](shortcut_architecture.md) for full details on the shortcut loading pipeline, Nexus manager, and user override persistence.
