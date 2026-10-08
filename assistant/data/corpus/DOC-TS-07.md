id: DOC-TS-07
title: 7. KDE & Plasma Specific Issues
source: docs/TROUBLESHOOTING.md — section 7 (KDE & Plasma Specific Issues)
tags: kde, plasma, plasmalogin, plasmalogin.service, sddm.service, kwin, qs-kwin-bridge, xdg-desktop-portal, portals, ydotoold, krohnkite, kwin script injection, login screen, sddm, window rules, installer window rules

### 7.1 Legacy qs-kwin-bridge Service

The old `qs-kwin-bridge` Python daemon is now **disabled** in favor of native C++ plugins. If you see it running:
```bash
systemctl --user disable --now qs-kwin-bridge.service
```

### 7.2 xdg-desktop-portal-kde

The recording patch restarts `plasma-xdg-desktop-portal-kde` before each recording. This may fail if:
- The portal service is masked
- The user's systemd session is in a bad state

### 7.3 ydotoold (On-Screen Keyboard)

`ydotoold` needs access to `/dev/uinput`. The installer:
1. Creates `/etc/udev/rules.d/80-uinput.rules`
2. Adds user to `input` group
3. Creates sudoers NOPASSWD rule

**If ydotoold doesn't work:**
- Re-login (group changes take effect on next login)
- Verify: `groups $USER` should include `input`
- Verify: `ls -la /run/user/$(id -u)/.ydotool_socket`

### 7.4 Krohnkite Tiling Disabled on Uninstall

The uninstaller disables `krohnkiteEnabled` in `kwinrc`. If you don't have the Krohnkite KWin script installed, this setting is simply ignored.

### 7.5 KWin Script Injection Fails

The plugin injects a temporary KWin script for window tracking. If KWin scripting is disabled:
```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript
```

### 7.6 The Login Screen (Plasma Login and SDDM)

Plasma 6.6 and newer boot into Plasma Login, KDE's fork of SDDM. The two are
configured in different places, and the installer picks a branch at install time:

| | Plasma Login | SDDM |
|---|---|---|
| How to tell | `plasmalogin.service` is active/enabled | `sddm.service` is active/enabled |
| Theme | none: its greeter is a Plasma shell, and it loads no SDDM theme | `/usr/share/sddm/themes/caelestia` |
| Wallpaper | `[Greeter][Wallpaper][org.kde.image][General] Image` in `/etc/plasmalogin.conf`, pointing at a copy under the `plasmalogin` user's `wallpapers/` | `assets/background` inside the theme |
| Colors | the `plasmalogin` user's own `~/.config/kdeglobals` plus the scheme files in its `~/.local/share/color-schemes/` | `theme.conf` inside the theme |
| Sync helper | `/usr/local/bin/caelestia-greeter-sync` | `/usr/share/sddm/themes/caelestia/scripts/sync.sh` |

The greeter runs as its own system user, which cannot read your home directory, so
anything it shows has to be copied to it. That is what the sync helper does, and it
runs after every wallpaper or color change through the posthook in
`~/.config/caelestia/cli.json`. An install that switches display managers replaces
its hook rather than stacking a second one.

**The login screen shows Breeze colors or no background:**

```bash
# Which display manager is actually installed
command -v plasmalogin sddm

# Plasma Login: what the greeter is told to show
kreadconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper \
    --group org.kde.image --group General --key Image

# SDDM: which theme each config source selects, last one read wins
grep -rn "Current=" /etc/sddm.conf /etc/sddm.conf.d/ /usr/lib/sddm/sddm.conf.d/ 2>/dev/null
ls /usr/share/sddm/themes/caelestia/theme.conf

# Re-copy the wallpaper and the scheme, then log out
sudo /usr/local/bin/caelestia-greeter-sync          # Plasma Login
sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh   # SDDM
```

Both greeters read their configuration when they start, so a change is visible at
the next logout rather than immediately.

### 7.7 Installer Window Rules

The installer writes three groups into `~/.config/kwinrulesrc`. `caelestia-opacity`
gives normal windows and dialogs an inactive opacity of 95 percent,
`caelestia-dialogs` forces centered placement on dialogs, and `caelestia-pip` keeps
windows whose title matches `Picture(-| )in(-| )[Pp]icture` above others. Opacity is
a per-activation-state key, so a window is dimmed only while it is not focused, and
the dialog rule is the one that can disagree with a placement policy chosen in
System Settings.

A group only takes effect if the index names it. `[General] rules=` is the list KWin
loads its rule groups from, and a group that is present in the file but missing from
that list is never loaded, and is removed the next time KWin saves the file. The
installer writes the list as the union of the entries that were already in it, every
group the file holds and its own three names, with `count` set to the number of
entries, so the user's own rules are named alongside ours and keep their order.

To read a value back:

```bash
kreadconfig6 --file kwinrulesrc --group caelestia-opacity --key opacityinactive
kreadconfig6 --file kwinrulesrc --group caelestia-dialogs --key placement
kreadconfig6 --file kwinrulesrc --group caelestia-pip --key above
kreadconfig6 --file kwinrulesrc --group General --key rules
```

To remove the rules, delete the three `[caelestia-...]` sections out of the file, or
delete the key that switches each group on. A group that is deleted has to leave the
index with it, or the list keeps a name whose group is gone and `count` no longer
matches it. `uninstall.sh` removes the keys, strips the three names out of the list,
rewrites `count`, and deletes both index keys once no name is left. KWin does not
watch kwinrulesrc, so the reload is not optional:

```bash
kwriteconfig6 --file kwinrulesrc --group caelestia-opacity \
    --key opacityinactiverule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-dialogs \
    --key placementrule --delete
kwriteconfig6 --file kwinrulesrc --group caelestia-pip --key aboverule --delete
qdbus6 org.kde.KWin /KWin reconfigure
```

Those commands delete each group's `*rule` key, which is the action. The match keys
are left behind, and a group that matches but carries no action is empty as far as
KWin is concerned: it discards such a rule once a window it matches has been
withdrawn, so the residue is harmless.

A window that is already open keeps what a rule forced on it. Opacity and keep-above
are set on the window itself, so an open window stays dimmed or pinned after the rules
are gone, until it is closed and reopened or another rule forces the value back. Only
windows created after the removal start clean.

The installer always applies the rules; `APPLY_WINDOW_RULES=false` is an override
for running the step by hand (`APPLY_WINDOW_RULES=false bash ./scripts/setup.sh`).
`WINDOW_OPACITY` changes the percentage the opacity rule writes.
