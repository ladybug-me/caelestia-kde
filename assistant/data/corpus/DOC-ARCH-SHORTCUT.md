id: DOC-ARCH-SHORTCUT
title: Shortcut system architecture
source: docs/architecture/shortcut_architecture.md
tags: shortcuts, globalshortcut, keybinds, keybindsmodel, globalshortcutdispatcher, stolen shortcuts, kglobalaccel, conflicts, rebind
synonyms: how shortcuts are registered, shortcut stealing recovery

This document provides a simplified overview of how the Caelestia shortcut system works, from the backend C++ components to the QML frontend.

---

## 1. High-Level Overview

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

- **`GlobalShortcut`**: Registers a single shortcut.
- **`GlobalShortcutDispatcher`**: A central hub that tracks shortcut collisions.
- **`KeybindsModel`**: Manages user-configured overrides and default bindings.

---

## 2. Core Components

### `GlobalShortcut`

This handles binding a hotkey (like `Meta+P`) to an action. It uses KDE's `kglobalaccel` under the hood.

**Key Features:**
- **Key Conflict Resolution:** If you try to use a shortcut that another KDE app is already using (like Spectacle using `Print`), Caelestia will temporarily "steal" it.
- **Smart Restoration:** If you change or remove a Caelestia shortcut, any stolen shortcuts are automatically given back to their original KDE apps.

### `GlobalShortcutDispatcher`

A singleton that acts as the central coordinator.
- **Collision Index:** It keeps track of which keys are currently "stolen" from other apps.
- This allows the UI to easily show a warning (like a red dot) if a shortcut conflicts with another app.

### `KeybindsModel`

Manages saving and loading your shortcut preferences.
1. Loads defaults from `keybindsdefaults.hpp`.
2. Applies user customizations from `~/.config/caelestia/keybinds.json`.
3. Communicates with the UI to update the list of active shortcuts.

---

## 3. Crash Recovery (Safety First)

If the shell crashes or is force-killed, we don't want your KDE shortcuts to be permanently broken because we stole them and never gave them back.

**How it works:**
1. Whenever Caelestia steals a shortcut, it immediately writes this to a recovery file: `~/.config/caelestia/stolen-shortcuts.json`.
2. When the shell closes normally, it restores the shortcuts and deletes the file.
3. If the shell crashes, the file remains on disk. On the **next startup**, Caelestia reads this file, restores all the stolen shortcuts, and cleans up.

---

## 4. User Interface (QML)

### Defining Shortcuts (`Shortcuts.qml`)
Shortcuts are defined using a `CustomShortcut` component. It automatically detects if you are running KDE (KWin) or Hyprland and uses the correct backend.

### Nexus Shortcut Manager
The Nexus settings panel is where users manage their shortcuts:
- **Groups:** Organizes shortcuts into categories (Shell, Apps, etc.).
- **Collision Blinker:** Shows a red warning dot if a key sequence conflicts with an existing KDE app. Hovering shows which app was overridden.
- **Editing:** Users can capture new keystrokes or reset back to default settings.

---

## 5. Important Files

| File | Purpose |
|---|---|
| `globalshortcut.hpp / .cpp` | Core logic for binding, stealing, and restoring shortcuts. |
| `keybindsmodel.hpp / .cpp` | Manages user settings and feeds data to the UI. |
| `keybindsdefaults.hpp` | The default key combinations. |
| `Shortcuts.qml` | Where all shell shortcuts are declared. |
| `keybinds.json` | Where user overrides are saved. |
| `stolen-shortcuts.json` | Crash recovery file. |
