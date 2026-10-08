id: DOC-TS-08
title: 8. Post-Install Issues
source: docs/TROUBLESHOOTING.md — section 8 (Post-Install Issues)
tags: post-install, shell not visible, installer exited prematurely, confirm_arg, stale lock files, update.sh fails, partial upgrade, packages replaced in memory, prebuilt shell, checksum
synonyms: disk space, ccache size, free disk space used by the shell, stale lock

### 8.1 Shell Not Visible After Install

The shell only runs at **next login**. After the summary screen, the installer asks: *"Would you like to log out now? (y/N)"*

If you chose not to log out:
1. Log out manually (`Super+Ctrl+Q` or KDE menu → Leave → Log Out)
2. Log back in
3. If the shell still doesn't appear, run: `caelestia shell -d`

### 8.2 Installer Exited Prematurely (Marker Check)

The outer `setup.sh` wrapper checks if `[installer] done (success)` appears in stderr:

| Condition | Warning |
|---|---|
| Exit 0 but elapsed < 3 seconds without marker | **"INSTALLER EXITED PREMATURELY"** |
| Exit 0 but elapsed > 3 seconds without marker | **"INSTALLER EXITED UNEXPECTEDLY"** |

### 8.3 CONFIRM_ARG Behavior

The configuration menu sets `CONFIRM_ARG` as `true`/`false`. The installer converts it per-script context:
- Some scripts use `-n "$CONFIRM_ARG"` (non-empty = auto-confirm)
- The installer writes an `[installer] done (success)` marker line to its stderr log, and `setup.sh` greps that log for it to decide whether the install succeeded (see `scripts/setup.sh`).

### 8.4 Stale Lock Files

If the script is killed with **SIGKILL** (not SIGTERM), lock files may persist:

| Lock File | Script |
|---|---|
| `${XDG_RUNTIME_DIR:-/tmp}/caelestia-setup.lock` | `setup.sh` |
| `${XDG_RUNTIME_DIR:-/tmp}/caelestia-update.lock` | `update.sh` |

**Always use Ctrl+C (SIGINT)** which is handled gracefully. Remove stale locks:
```bash
rm -f "${XDG_RUNTIME_DIR:-/tmp}/caelestia-setup.lock"
rm -f "${XDG_RUNTIME_DIR:-/tmp}/caelestia-update.lock"
```

### 8.5 Update.sh Fails

| Symptom | Cause |
|---|---|
| `git pull` fails | Uncommitted changes exist. The updater auto-stashes, but conflicts may remain. |
| Submodule update fails | Network issue or GitHub down. Retry later. |
| CMake configure fails | New dependencies added since last install. Check error output. |

### 8.6 Installer Stops After a System Upgrade

`00a-system-update.sh` upgrades the system first, and later steps compile and load the Caelestia
KWin plugin into the session that is **already running**. If the upgrade replaced `kwin`,
`plasma-workspace`, `libplasma`, `qt6-base` or `qt6-declarative`, the live session still holds the
old libraries in memory while the on-disk headers are new, so the installer stops and names the
packages that moved:

```
[ERR]   The upgrade replaced packages the running session still has loaded in memory:
[ERR]   had kwin 6.4.0-1
[ERR]   now kwin 6.4.1-1
```

This is the partial-upgrade state Arch documents as "do not keep using the session", not a broken
install. Log out and back in (or reboot) and run the installer again: the upgrade is already
applied, so nothing is downloaded twice and the remaining steps run against a session that matches
the files on disk.

Choosing **ignore** at the prompt continues anyway. The plugin build may then fail with Wayland or
ABI errors that look unrelated to the upgrade.

### 8.7 Prebuilt Shell Download Is Rejected

`08-build-shell.sh` extracts the release tarball straight over `$HOME`, so it first checks the
download against the `.sha256` published beside it:

| Message | Meaning |
|---|---|
| `Prebuilt shell artifacts match the published checksum.` | Normal: the prebuilt archive is installed. |
| `No published checksum for ... - extracting without verification.` | The release predates checksums. The install continues. |
| `No prebuilt shell artifacts published for <tag> (Qt <abi>) - falling back to a local build.` | The release carries no archive for this Qt feature version. The step builds locally instead. |
| `Checksum mismatch for ...` | The download was truncated or tampered with. The step falls back to building the shell locally. |

A mismatch is not fatal: the installer builds from source instead, which takes longer but cannot
unpack a damaged tree into `~/.local/lib/qt6/qml`.

The archive is also only used for the revision it was built from: `main` sitting on its remote
tip, or a checkout that is exactly the released tag (an update pinned to a version). A branch, a
stale `main`, or a checkout carrying commits of its own builds locally, because the archive would
replace that tree with the release's. `main` that has moved on since its last release cannot be
told apart from that release, so it is installed as the release its `version.env` names.
