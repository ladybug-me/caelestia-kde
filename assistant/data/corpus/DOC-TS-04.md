id: DOC-TS-04
title: 4. Runtime Issues — Lock Screen
source: docs/TROUBLESHOOTING.md — section 4 (Runtime Issues — Lock Screen)
tags: lock screen, lockscreen, greeter, breeze, kscreenlockerrc, plasmashellrc, shell package, kreadconfig6, kwriteconfig6
synonyms: breeze lock screen shows instead of caelestia

### 4.1 Lock Screen Greeter Diagnostic

The Caelestia lock screen runs as a native KDE Plasma 6 shell package (`caelestia.desktop`), loaded directly by KDE's `kscreenlocker_greet`.

**Diagnostic commands:**
```bash
# Verify Caelestia shell package is configured
kreadconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage"
# Expected output: caelestia.desktop

# Verify greeter files exist in local plasma shells directory
ls -la ~/.local/share/plasma/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml

# Test and run the greeter in a window (non-blocking test)
/usr/lib/kscreenlocker_greet --testing
```

| Symptom | Cause | Solution |
|---|---|---|
| Stock Breeze lock screen appears | `ShellPackage` reset after KDE update or theme switch. | Caelestia autostart (`caelestia-autostart.sh`) automatically self-heals this at next login if `caelestia.desktop` is present. To restore immediately in session: `kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop" && kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" --delete`. |
| Lock screen fails or crashes | Greeter files missing or corrupted in `~/.local/share/plasma/shells/`. | Re-deploy via `BUNDLE_DIR=. ./scripts/02-packages.sh` or `cp -r src/kde/shells/caelestia.desktop ~/.local/share/plasma/shells/`. |
| Lock screen shows wallpaper error | Legacy `PlasmaApplicationWallpaper` left in `kscreenlockerrc`. | Reset WallpaperPlugin: `kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "org.kde.image"`. |
| Profile picture missing | `~/.face` does not exist and no system user avatar set. | Place your avatar image at `~/.face` or configure an avatar in KDE System Settings → Users. |
