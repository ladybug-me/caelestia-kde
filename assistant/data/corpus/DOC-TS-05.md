id: DOC-TS-05
title: 5. Configuration Issues
source: docs/TROUBLESHOOTING.md — section 5 (Configuration Issues)
tags: configuration, darkly, theme, window decoration, osd, virtual desktops, kglobalaccel, shortcut conflicts, stolen shortcuts, terminal, garbled output
synonyms: shortcuts stopped working, osd keeps showing, wrong number of desktops

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
