<div align="center">

<img src="assets/logo.svg" width="64" alt="Caelestia logo" />

# caelestia-kde

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793d1?logo=arch-linux&logoColor=white&style=for-the-badge&labelColor=101418)](https://archlinux.org)
[![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white&style=for-the-badge&labelColor=101418)](https://fedoraproject.org)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white&style=for-the-badge&labelColor=101418)](https://ubuntu.com)
[![KDE Plasma](https://img.shields.io/badge/Plasma_6-1D99F3?logo=kde&logoColor=white&style=for-the-badge&labelColor=101418)](https://kde.org/plasma-desktop)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-9bd0cc?style=for-the-badge&labelColor=101418)](LICENSE)

</div>

<!-- markdownlint-disable-next-line MD034 -- a bare URL is what GitHub turns into an inline video player -->
https://github.com/user-attachments/assets/38b24e7f-fdd9-43db-872b-8c0ac23a44fd

> [!NOTE]
> This repo is the KDE Plasma port of [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell).
> Upstream runs on Hyprland; the port runs the same shell on KWin and Plasma. For the original
> Hyprland dotfiles, see [`caelestia-dots/caelestia`](https://github.com/caelestia-dots/caelestia).

## Installation

**Requirements:** Arch-based, Fedora, or Debian/Ubuntu - KDE Plasma 6 on Wayland, Qt 6.9+

```bash
curl -fsSL https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/install.sh | sh
```

### Updating

- **Installer TUI:** run the installer and choose *Update*
- **GUI:** Nexus -> Updates -> select branch -> Install Updates
- **CLI:** `bash update.sh` and choose `main` (stable) or `dev` (bleeding edge)

Shell settings are preserved across updates.

### Uninstalling

Choose *Uninstall* from the installer TUI, or run:

```bash
bash ./uninstall.sh
```

## For forks

Every update and prebuilt-artifact path reads the repository owner from the
environment, so a fork is self-contained without patching URLs:

- `CAELESTIA_REPO_OWNER` (default `ladybug-me`) - the GitHub owner of the
  repositories cloned and pulled for source and updates: the
  `caelestia-update` shadow clone, the `caelestia-check-updates` queries and
  the Nexus Updates page. (`install.sh` takes a full clone URL via
  `CAELESTIA_REPO`.)
- `CAELESTIA_PREBUILT_OWNER` (default `ladybug-me`) - the GitHub owner of the
  published release artifacts: the prebuilt installer TUI, the prebuilt shell
  archive, the bundled fonts and the CAVA SDK. Forks that do not publish
  binaries leave this at the default.

For example, a fork published as `example/caelestia-kde` that only carries
source changes exports `CAELESTIA_REPO_OWNER=example` and keeps
`CAELESTIA_PREBUILT_OWNER` at the default, so binaries keep coming from the
releases they were built from. The variables are plain environment variables;
export them in the session that runs the installer or the update.

The installer persists whatever owners the installing session resolved into
`~/.config/environment.d/caelestia.conf` and the Plasma session environment, so
the shell's systemd unit, the update-checker timer and the Nexus Updates page
all see the same source the install came from - not just terminals. Re-running
the installer or an update refreshes those lines to the newly exported values.

## Keybinds

| Shortcut | Action |
| --- | --- |
| `Super` | App launcher |
| `Super + /` | Keybind cheatsheet |
| `Super + Enter` | Terminal |
| `Super + Tab` | Overview |
| `Super + 1-5` | Switch workspace |
| `Super + B` | Notification sidebar |
| `Super + V` | Clipboard history |
| `Super + Shift + S` | Screenshot |
| `Super + Shift + A` | Google Lens |
| `Super + Shift + D` | Text recognition |
| `Super + Ctrl + S` | Screen recorder |
| `Super + Shift + C` | Color picker |
| `Super + Shift + V` | Emoji selector |

## Configuring

Open Nexus (`Super`, then `>Settings`).

- Appearance: wallpaper, colors, fonts, and the wallpaper slideshow
- Panels: every bar element, dashboard, launcher, sidebar and overview
- Desktop: window rules, the context menu, Krohnkite
- Shortcuts: rebind any built-in shortcut, or add a command shortcut
- Plugins: browse the store, or install a plugin you built yourself

Set the wallpaper from Appearance. The stock KDE wallpaper manager does not drive
the color scheme, so using it leaves the shell on stale colors.

Settings are written to `~/.config/caelestia/shell.json`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Widgets not appearing | Log out and back in, or run `caelestia shell -d` |
| Colors not applying | Run `caelestia scheme set -n dynamic`, or `caelestia wallpaper -f <image>`. See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#34-colors-not-applying) |
| Install failed mid-way | Re-run `bash ./scripts/setup.sh` |
| Full reset needed | See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

For detailed logs, enable Debug Mode in Nexus -> About -> Advanced, then run
`caelestia shell -l`. Bug reports and questions go to
[GitHub Issues](https://github.com/ladybug-me/caelestia-kde/issues).

## Repository layout

```
installer/     TUI installer and the per-distro package lists
  tui/         C++ TUI source and its CMakeLists
  data/        menu.json, theme.json, tui.version
  distro/      per-distro package installation (arch, debian, fedora)
scripts/       install/update pipeline: the numbered steps and their shared lib/
src/           files copied onto the system, plus the vendored submodules
shell/         the QML shell and its C++ QML plugin
docs/          guides, plus design notes under docs/architecture/
tests/         bash tests for the step-script helpers
tools/         repo maintenance scripts, never shipped
assets/        the logo and screenshots used by the docs
.github/       workflows, issue and PR templates, CI checks
```

<a href="https://www.star-history.com/?repos=ladybug-me%2Fcaelestia-kde&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ladybug-me/caelestia-kde&type=date&theme=dark&legend=top-left&sealed_token=NFI4jXcoZAI26MlGX2jEasHMRd1PIS09clm_CVDS7SFGajH3wiHlN72P8WzuOQT2k2F71ZOCGl_xoy8eVpWlWtA0ACY3koK0NIS1-vLecN0vbvYgrZDN9kp8sQn7NT2xPNeilgrmzYWTzgdQYgskaDMGophAKmy6r6LUfQj8iFjy-Gunuqnte3EY14fX" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ladybug-me/caelestia-kde&type=date&legend=top-left&sealed_token=NFI4jXcoZAI26MlGX2jEasHMRd1PIS09clm_CVDS7SFGajH3wiHlN72P8WzuOQT2k2F71ZOCGl_xoy8eVpWlWtA0ACY3koK0NIS1-vLecN0vbvYgrZDN9kp8sQn7NT2xPNeilgrmzYWTzgdQYgskaDMGophAKmy6r6LUfQj8iFjy-Gunuqnte3EY14fX" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=ladybug-me/caelestia-kde&type=date&legend=top-left&sealed_token=NFI4jXcoZAI26MlGX2jEasHMRd1PIS09clm_CVDS7SFGajH3wiHlN72P8WzuOQT2k2F71ZOCGl_xoy8eVpWlWtA0ACY3koK0NIS1-vLecN0vbvYgrZDN9kp8sQn7NT2xPNeilgrmzYWTzgdQYgskaDMGophAKmy6r6LUfQj8iFjy-Gunuqnte3EY14fX" />
 </picture>
</a>

## Credits

- [caelestia-dots/shell](https://github.com/caelestia-dots/shell) and the [Caelestia dotfiles](https://github.com/caelestia-dots/caelestia) by [@soramanew](https://github.com/soramanew) - the design language, shell and dotfiles this port is built on
- [ladybug-me](https://github.com/ladybug-me) - KDE port lead
- [0xSolanaceae](https://github.com/0xSolanaceae) - Head maintainer
- [Bali10050](https://github.com/Bali10050/Darkly) - Darkly Qt
- [wrymt](https://github.com/wrymt/darkly-gtk) - Darkly GTK
- [Haidir](https://bitbucket.org/dirn-typo/yet-another-monochrome-icon-set) - icon set
- [dim-ghub](https://github.com/dim-ghub/caelestia-shell) - v2.0.0 features
  
## License

GPL-3.0-or-later - see [LICENSE](LICENSE).
