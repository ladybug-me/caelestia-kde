# Shortcut system architecture

How a key sequence reaches a Caelestia action, and what happens when KDE already owns the key.

## Overview

```text
[ QML UI (Shortcuts.qml, Nexus) ]
              │
              ▼
[ GlobalShortcut (C++ / QML) ]
              │ registers keys & handles conflicts
              ▼
[ GlobalShortcutDispatcher ]  <──  [ KeybindsModel ]
  (tracks stolen keys)             (loads user settings)
```

- `GlobalShortcut` registers one shortcut.
- `GlobalShortcutDispatcher` owns the collision index.
- `KeybindsModel` loads defaults, applies user overrides, and feeds the Nexus list.

## GlobalShortcut

Binds a key sequence such as `Meta+P` to an action through KDE's `kglobalaccel`.

When another KDE app owns the sequence (Spectacle and `Print`, for example), Caelestia takes it over temporarily. Changing or removing the Caelestia shortcut gives the sequence back to the app that owned it.

## GlobalShortcutDispatcher

A singleton coordinator. It tracks which keys are currently taken from other apps, exposes that state to the UI, and writes the recovery record before it takes a key.

## KeybindsModel

Loads defaults from `keybindsdefaults.hpp`, applies overrides from `${XDG_CONFIG_HOME:-~/.config}/caelestia/keybinds.json`, and updates the UI when the set changes.

## Crash recovery

A stolen key would otherwise stay stolen if the shell crashed. Every takeover is recorded in `${XDG_CONFIG_HOME:-~/.config}/caelestia/stolen-shortcuts.json` before it happens. A normal exit restores the keys and deletes the file; on the next start, a file left behind is replayed and removed.

## Nexus manager

The Shortcuts page groups shortcuts by category: Shell, Applications, Workspaces, Screenshot & Recording, and Window Tiling. A conflict shows a red dot and names the app whose key was taken. A shortcut can be recaptured or reset to its default.

## Files

| File | Purpose |
| --- | --- |
| `globalshortcut.hpp` / `.cpp` | Binds, steals and restores shortcuts |
| `keybindsmodel.hpp` / `.cpp` | User settings and the model behind the UI |
| `keybindsdefaults.hpp` | Default key combinations |
| `Shortcuts.qml` | Where the shell declares its shortcuts |
| `keybinds.json` | User overrides |
| `stolen-shortcuts.json` | Crash-recovery record |
