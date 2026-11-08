# Shortcut system architecture

How a key combination in Caelestia reaches an action, and what happens to a key
KDE was already using.

```text
[ QML UI (Shortcuts.qml, Nexus) ]
              │
              ▼
[ GlobalShortcut (C++ / QML) ]
              │ registers keys & handles conflicts
              ▼
[ GlobalShortcutDispatcher ]  <──  [ KeybindsModel ]
  (Tracks stolen keys)             (Loads user settings)
```

## `GlobalShortcut`

`GlobalShortcut` binds one hotkey to one action through KDE's `kglobalaccel`.
Two behaviours are worth knowing about.

**Taking a key from another application.** If the requested combination already
belongs to a KDE application (Spectacle on `Print`, for example), Caelestia takes
it over and records the original owner. When the shortcut is changed or removed,
the original binding goes back to that application.

**Surviving a crash.** Every stolen key is written to
`${XDG_CONFIG_HOME:-~/.config}/caelestia/stolen-shortcuts.json` as soon as it is
taken. The shell deletes that file when it exits normally, so a file left on disk
means the previous session never got the chance to give the keys back. The first
shortcut lookup of the next start reads the file, returns every recorded key to
its owning application, and removes it. Restoration goes through `gdbus` calls to
`org.kde.KGlobalAccel.setShortcutKeys`, because the key belongs to another
component and `kglobalaccel` will not move it for the shell from inside the
process.

## `GlobalShortcutDispatcher`

The singleton both sides of a conflict meet at. `GlobalShortcut` reports a stolen
key to it, and it answers `collisionForKey(portableKeyString)`: that is what lets
the shortcut manager mark a row and name the application it would displace.

## `KeybindsModel`

`KeybindsModel` is a `QAbstractListModel` that decides which bindings are active:

1. Defaults come from `keybindsdefaults.hpp`.
2. User overrides come from `${XDG_CONFIG_HOME:-~/.config}/caelestia/keybinds.json`.
3. The merged result drives `Shortcuts.qml` and the Nexus shortcut manager.

## Declaring a shortcut

Shell shortcuts are declared in `Shortcuts.qml` with `CustomShortcut` from
`shell/components/misc/`. The wrapper picks a backend at startup: Hyprland's
`Quickshell.Hyprland.GlobalShortcut` with bindings from `hyprland.conf`, or
`Caelestia.GlobalShortcut` registering directly with `kglobalaccel`.

The Nexus shortcut manager reads the same model. Rows are grouped by category, a
captured key is written back through `KeybindsModel`, and a row whose combination
is taken shows the conflicting application on hover.
