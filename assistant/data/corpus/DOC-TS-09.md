id: DOC-TS-09
title: 9. Uninstall Issues
source: docs/TROUBLESHOOTING.md — section 9 (Uninstall Issues)
tags: uninstall, backups, konsave, restore, rc files, dependencies, input group, failed patches

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

### 9.5 Input Group Membership Persists

The uninstaller runs `sudo gpasswd -d $USER input`. This only works if the user was added to the group during installation, and takes effect on next login.

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
