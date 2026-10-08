id: DOC-TS-02
title: 2. Dependency & Package Issues
source: docs/TROUBLESHOOTING.md — section 2 (Dependency & Package Issues)
tags: packages, pacman, yay, aur, fedora, copr, dnf, rpm fusion, matugen, dos2unix, crlf, failed_packages.txt, quickshell-git, libcava

### 2.1 Arch Linux / yay Failures

| Issue | Cause |
|---|---|
| `yay` fails to install | Network issues, AUR down, or PKGBUILD changes. The script (`installer/distro/arch/packages.sh`) retries individually and falls back to `makepkg -si`. |
| `pacman` errors during install | The script uses `-Sy --noconfirm` (refresh DB) then `-S --needed --noconfirm`. If the system update step (`00a-system-update.sh`) was skipped, partial upgrades can cause conflicts. |

**AUR packages used by Caelestia:**

| AUR Package | Failure Symptoms |
|---|---|
| `quickshell-git` | Shell won't start; autostart fails with exit 127 |
| `matugen` | `caelestia wallpaper` and `caelestia scheme` fail with "matugen is not installed". It is in Arch's `extra`, so it is not an AUR package; it is listed here because nothing themes without it. |
| `darkly` | KDE theme won't apply |

### 2.2 Fedora / COPR Failures

| Package | COPR / Source | Known Issues |
|---|---|---|
| `quickshell-git` | `errornointernet/quickshell` | COPR may be out of date |
| `gpu-screen-recorder` | `brycensranch/gpu-screen-recorder-git` | May need `ffmpeg` from RPM Fusion |
| `app2unit` | `celestelove/app2unit` | Falls back to `make install` |
| `libcava` | Prebuilt release asset / `celestelove/libcava` | Downloads prebuilt SDK from release; falls back to COPR |
| `starship` | `atim/starship` | Stable, rarely fails |
| `wl-clip-persist` | `leloubil/wl-clip-persist` | Needed for clipboard persistence |

**RPM Fusion requirement:** `ffmpeg` with H264 support requires RPM Fusion. The script auto-enables it, but this may fail behind a proxy or on air-gapped systems.

**matugen on Fedora:** there is no package for it, and it is what generates the palette. The installer reports it when it is missing; `cargo install matugen` fixes it.

### 2.3 CRLF / dos2unix Failure

If CRLF line endings are detected and `dos2unix` auto-install fails, the installer **aborts** with:

```text
[FATAL] Line ending normalization step failed. Aborting installer.
```

**Fix:** Install `dos2unix` manually, or answer `n` to the CRLF prompt to skip normalization.

### 2.4 Failed Packages Log

Failed packages are logged to:

```text
$XDG_CACHE_HOME/caelestia-kde/failed_packages.txt
```

The installer does **not** abort on package failure — it logs and continues. Check this file after installation if something doesn't work.
