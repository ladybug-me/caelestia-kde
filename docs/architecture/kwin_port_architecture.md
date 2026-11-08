# KWin port architecture

The C++ plugin that gives the shell KDE's windows, desktops and shortcuts, and the
API it exposes to QML.

![The Caelestia shell](../../assets/shell-screenshot.png)

## What the plugin replaced

The port went through two earlier shapes.

The first was a "fake Hyprland" wrapper: a KWin JavaScript script pushed window
data over D-Bus, a Python daemon (`qs-kwin-bridge.py`) listened to it, and a mock
`hyprctl` returned that data in Hyprland's JSON shape. Three processes and two
protocols sat between a window changing and the bar noticing, and the shell could
only see what the script chose to forward.

The second removed the daemon but kept the process boundary: `QProcess` tasks ran
`qdbus6` to inject temporary KWin scripts and drive windows. Fewer moving parts,
still a D-Bus round trip and a script compilation per operation.

Both existed to speak Hyprland's interface to a compositor that has its own.

## What the plugin is now

The shell links a Quickshell plugin that talks to KWin and Wayland directly.

| Component | Talks to | Owns |
|---|---|---|
| `KWinActiveWindowBridge` | `plasma-window-management` (Wayland) | The active window, the window list, per-window actions |
| `KWinWorkspaceState` | KDE's virtual desktop manager over D-Bus, plus a `QLocalSocket` server | Desktops, the active desktop, trackpad swipe progress |
| `GlobalShortcut` | `kglobalaccel` | One registered shortcut, and the conflict bookkeeping behind it |

`KWinActiveWindowBridge` binds the `plasma-window-management` protocol through
`plasma-windows`, so window state arrives as protocol events rather than as
injected scripts. `KWinWorkspaceState` runs a small `QLocalSocket` server named
`caelestia-workspace-tracker` that the workspace-tracker KWin effect connects to,
which is where the fractional `swipeOffset` used by the swipe animations comes
from.

Shortcut registration, collision detection and crash recovery have their own
page: [shortcut_architecture.md](shortcut_architecture.md).

## QML API

### `KWinActiveWindowBridge`

| Property | Type | Meaning |
|---|---|---|
| `activeWindow` | map | The focused window, in the field set below |
| `activeOutputName` | string | Output the active window is on; writable |
| `windowList` | list of maps | Every window the protocol reports |
| `pendingFocusAddress` | string | Address a focus request is waiting on |
| `highlightedAddress` | string | Address currently highlighted |

Each window map carries `address`, `pid`, `title`, `class`, `x`, `y`, `width`,
`height`, `fullscreen`, `maximized`, `minimized`, `focused`, `floating`,
`output`, and a `workspace` map of `id` and `uuid`.

| Method | Effect |
|---|---|
| `focusWindow(address)` | Focus the window |
| `closeWindow(address)` | Ask the window to close |
| `minimizeWindow(address)` | Minimize it |
| `maximizeWindow(address, horz, vert)` | Maximize on the given axes |
| `raiseWindow(address)` | Raise it to the top of the stack |
| `setMaximized(address, maximized)` | Set or clear the maximized state |
| `setFullscreen(address, fullscreen)` | Set or clear fullscreen |
| `setWindowProperty(address, property, enable)` | Toggle a legacy boolean state |
| `setWindowDesktop(address, desktopId)` | Move to a desktop: `-1` current, `-2` all |
| `sendToOutput(address, outputName)` | Move the window to an output |
| `highlightWindow(address)` / `clearHighlight()` | Draw and clear the overview highlight |
| `windowsForWorkspace(workspace, includeOnAllWorkspaces)` | The window list filtered to one desktop |
| `cursorOutputName()` | Output under the cursor |
| `setActiveOutputName(outputName)` | Set the active output tracker by hand |
| `refreshWindows()` | Re-read the window list |

### `KWinWorkspaceState`

| Property | Type | Meaning |
|---|---|---|
| `activeId` | int | Active desktop, 1-indexed |
| `activeByOutput` | map | Active desktop per output |
| `workspaces` | list of maps | Each desktop as `id` (UUID), `name`, `index` (1-based), `active` |
| `rows` | uint | Rows the desktop grid lays out in |
| `swipeOffset` | double | Fractional swipe progress for animations |
| `swipeOffsetByOutput` | map | The same, per output |
| `showingDesktop` | bool | Whether show-desktop is engaged |

| Method | Effect |
|---|---|
| `switchTo(id, output)` | Switch to a desktop by UUID, id or name |
| `setDesktop(desktopId)` | Switch by 1-based index |
| `nextDesktop()` / `previousDesktop()` | Step, wrapping at the ends |
| `createWorkspace(name)` | Add a desktop |
| `removeWorkspace(id)` | Remove a desktop |
| `indexForId(id)` / `uuidForIndex(index)` | Convert between the two identifiers |
| `setShowingDesktop(showing)` | Engage or leave show-desktop |

### `GlobalShortcut`

`name`, `key` (a semicolon-separated sequence) and `description`, plus the
`activated()` signal. Registered as `Caelestia.GlobalShortcut` for QML.

### `KeybindsModel` and `GlobalShortcutDispatcher`

`GlobalShortcutDispatcher` is the relay for cross-instance signals and holds the
collision index (`key` to friendly label) that backs `stolen-shortcuts.json`.
`KeybindsModel` merges `keybindsdefaults.hpp` with the user's
`${XDG_CONFIG_HOME:-~/.config}/caelestia/keybinds.json` and drives the Nexus
shortcut manager.

## Where shortcuts are declared

`Shortcuts.qml` under `shell/modules/` declares every shell shortcut through
`CustomShortcut` in `shell/components/misc/`. The wrapper picks its backend at
startup: `Quickshell.Hyprland.GlobalShortcut` on Hyprland with bindings from
`hyprland.conf`, or `Caelestia.GlobalShortcut` registering with KDE's global
shortcut daemon. [shortcut_architecture.md](shortcut_architecture.md) covers the
loading pipeline, the manager and how overrides are persisted.
