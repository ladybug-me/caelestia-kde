# AUR packaging

One package. It was planned as two, a shell and a CLI, and the split does not
survive contact with the code: the command's helpers are the shell's own seams
(`caelestia-shell-ipc` is meaningless without it), the palette it generates comes
from templates and a scheme catalogue that belong to the shell, and the QML calls
the command by name. One package is also the argument the lock screen got: nothing
in it can drift from the shell it locks or the command it calls.

| Package | State | Notes |
| --- | --- | --- |
| `caelestia-kde` | written, waiting on the next release | the shell, the `caelestia` command and its helpers, the palette data, the Plasma lock screen, the workspace-tracker effect, autostart |
| `caelestia-cli-kde` | not needed | the command ships in the shell package. The name stays free in case the command ever earns a life without the shell |

The package is named for the port rather than for one thing inside it. The shell is the
largest part of the payload, but the lock screen, the KWin effect and the command ship
in the same install, and `caelestia-shell-kde` said otherwise. Renaming was still free
when it happened (2026-09-13): `caelestia-kde`, `caelestia-shell-kde` and
`caelestia-cli-kde` all return `resultcount` 0 on the AUR, so nothing needs a replace
entry and no user's helper knows the old name.

## What the package installs

- the shell tree, the Caelestia QML plugin and M3Shapes, through the shell's own
  CMake install: `/etc/xdg/quickshell/caelestia`, `/usr/lib/qt6/qml`,
  `/usr/lib/caelestia`. That is the system layout upstream's package uses, so
  quickshell finds it with no per-user copy;
- `src/bin/*` into `/usr/bin`: `caelestia` and the seven helpers it drives. They
  are one surface, and the dispatcher runs its siblings from its own directory;
- `src/matugen/` and `src/schemes/` into `/usr/share/caelestia`. `caelestia-color`
  looks for them in `$CAELESTIA_DATA_DIR`, `$CAELESTIA_LIB_DIR`,
  `~/.local/lib/caelestia` and `/usr/share/caelestia`, in that order, so no
  environment variable is needed;
- `src/kde/shells/caelestia.desktop` into `/usr/share/plasma/shells`: the lock
  screen is a Plasma shell package rather than a Quickshell module, so the shell's
  CMake knows nothing about it;
- the workspace-tracker KWin effect, built here against this machine's Plasma
  because it links KWin's ABI;
- autostart: `/usr/bin/caelestia-autostart`, the systemd user unit it runs under,
  and nothing else. The unit is not enabled by the package - packages cannot enable a
  user's units - so `caelestia install` does it once.

It declares `provides=('caelestia-shell')` and
`conflicts=('caelestia-shell' 'caelestia-shell-git')`. That is honest: the QML
interface and the config directory are the same, and the community packages that
require `caelestia-shell` do so optionally, so nothing breaks.

It ships one font, the shell's own: `shell/assets/google-sans-flex`, which
`GSFLoader.qml` loads for the default family. Every other family comes from the system,
and the ones the defaults name are in the optdepends (`ttf-rubik-vf` for the clock and
the workspace label, `ttf-cascadia-code-nerd` for the mono style). That is upstream's
arrangement, and it is why nothing downloads a font any more: the step that fetched the
Apple families into `~/.local/share/caelestia/assets/fonts` is gone, and
`08-build-shell.sh` reclaims what an older install left in that directory and in the
shell tree, about 300 MiB in each.

It no longer depends on `caelestia-cli`. The color pipeline belongs to this
project now - `caelestia-color` generates the palette with matugen, applies it and
fans it out - so what the package needs from outside is `matugen` and `python`,
not another caelestia.


## Updates in a packaged install

The shell's Update page runs `caelestia-update`, and that helper decides what to do
from the directory it was installed in: `/usr/bin` is a package's, `~/.local/bin` is
the installer's. A packaged install therefore goes to the package manager instead of
doing the work below it - no repository is cloned and no second shell is built into
`~/.config` and `~/.local`, where pacman would know nothing about it and which needs
cmake, make and git that the package does not require.

So updating from the shell in a packaged install runs `pacman -Syu`, prints the line
that finishes the job (`sudo pacman -Syu caelestia-kde`, or a rebuild of the AUR
package) and asks for a log out. `caelestia-check-updates` still compares the installed
version against the project's newest tag, which is what the Update row reports from -
that is why `git` is a dependency.


## Reusable path fixes a package needs

A system install puts the shell somewhere other than `$HOME`. Done on
2026-09-12:

- `Paths.bin(name)` in `shell/utils/Paths.qml` resolves a command through
  `CAELESTIA_BIN_DIR`, falling back to `~/.local/bin`. `Recorder.qml`,
  `RegionSelection.qml` and `UpdateChecker.qml` use it, and the source install's
  autostart script exports the variable the same way the package's does.
- `PluginsPage.qml`, `AppearancePage.qml`, `Toggles.qml` and `PluginLoader.qml`
  reach `restart_shell.sh` and `list-plugins.sh` through
  `Quickshell.shellPath("scripts/...")`, which follows the shell wherever it is
  installed.
- `LockScreenUi.qml` resolves the IPC helper inside the command it runs, because
  kscreenlocker inherits neither the session environment nor its PATH: the helper
  is looked up with `~/.local/bin` in front, which covers the package's
  `/usr/bin` and a source install's copy.

The two items this list used to end with are covered as well: the environment
file at `~/.config/environment.d/caelestia.conf` carries `CAELESTIA_BIN_DIR` into
the session and into the user manager, so `caelestia-shell-ipc` finds the shell
config, and the update-checker unit resolves its helper from that same variable
instead of a hardcoded `$HOME`.

## Installing

The package owns everything under `/usr` and `/etc`. What it cannot do is the
data only a user's files can hold, so installing is two steps:

    yay -S caelestia-kde
    caelestia install

`caelestia install` runs the same step scripts a checkout's installer runs, for the
user's half only: the config files, the KDE settings, the user services, the
environment, the enablement of the shell's unit (a package cannot enable a user's
units) and the wallpaper state. It is idempotent, and `caelestia update` on
a packaged install runs the package manager and then it again.

### Removing it

    systemctl --user disable caelestia-shell.service
    pacman -Rns caelestia-kde

The unit and its launcher belong to the package, so they go with it. The enable link
does not: `systemctl --user enable` writes it under
`~/.config/systemd/user/graphical-session.target.wants/`, which pacman neither owns nor
removes, and a link with the unit's name is enough for systemd to count the unit as
enabled however dead its target is - it would keep trying to start a shell the package
has just deleted. Disabling first is the clean order. If the package is already gone,
that command still clears the link; if it does not, deleting the dangling link under that
directory does, and a checkout's `uninstall.sh` does both for a source install.

What stays is the user's own state, which the package never owned: `~/.config/caelestia`,
the session environment at `~/.config/environment.d/caelestia.conf`, the autostart state
under `~/.local`, and the sudoers drop-in at `/etc/sudoers.d/caelestia-sddm-sync` that
lets the login screen follow the wallpaper. Deleting those is what removes the last trace
of the install. There is no uninstall command, and upstream has none either: removal
belongs to whoever installed the files, which for a package is pacman.


## Publishing

The AUR repository for a package is the package directory itself. For
`caelestia-kde`:

    git clone ssh://aur@aur.archlinux.org/caelestia-kde.git
    cp packaging/aur/caelestia-kde/* caelestia-kde/
    cd caelestia-kde
    makepkg --printsrcinfo > .SRCINFO
    git add PKGBUILD .SRCINFO caelestia-autostart caelestia-shell.service
    git commit -m "update to 2.4.3"
    git push

Updating for a release:

1. bump `pkgver` and reset `pkgrel=1`;
2. point the source at the new tarball. It is already named after `pkgver`, so the URL
   follows the bump on its own, but the first `sha256sums` entry does not: the tarball
   does not exist until the tag is pushed and `build-source` has attached it. Push the
   tag, then take the hash from that job's summary (`sha256sum` is printed beside the
   size) or download the `.sha256` it attaches, and put it in. A `SKIP` in the meantime
   is what the file ships with: `prepare()` refuses to build while it is there, and a
   wrong hash stops the build with "Integrity checks
   (sha256) differ";
3. the other two `sha256sums` entries are the files beside the PKGBUILD, so run
   `makepkg -g` to refresh them if any of them changed;
4. check the tag still has everything `package()` copies by name: `src/bin/*`,
   `src/matugen/`, `src/schemes/`, `src/kde/shells/caelestia.desktop`,
   `shell/kwin-effects/workspace-tracker`, and for the user's half `scripts/`,
   `src/dots/`, `src/dots-extra/`, `src/yet-another-monochrome-icon-set/`,
   `shell/assets/wallpaper.webp` and `assets/org.quickshell.desktop`. A missing path
   fails the build rather than shipping a package with a silent hole in it, which
   is why they are named. No version file is among them: the version the shell and
   the command report is compiled into `/usr/lib/caelestia/version` from the same
   `-DVERSION=$pkgver` the build is given, so there is nothing to keep in step;
5. regenerate `.SRCINFO` before pushing.

The source is the tarball the release job attaches, not a clone of the tag. The tree
carries two submodules, so a clone makes every build download them as well; the tarball
is about 40 MiB, with the submodules inlined at the commits the tag pins and `REVISION`
written, which is what the compiled helper reports from a tree with no `.git` to ask.
The Apple fonts the tree used to ship are still reachable in the repository's history,
so a fresh clone of the repository carries them whatever the tree holds.
Upstream does the same thing for the same reason.

To build before a tag exists, use `packaging/aur/makepkg-from-checkout.sh`. It builds
the same tarball from the checkout - same exclusions, same submodules, same `REVISION`
- hashes it, and runs `makepkg` on a staged copy of the PKGBUILD that points at it, so
this is the real package build and not a variant of it:

    packaging/aur/makepkg-from-checkout.sh -si

The version the shell reports is still `pkgver`, so that is for testing the flow rather
than for a release. It stages in `~/.cache/caelestia-aur` rather than `/tmp`, because
makepkg builds the whole shell there.

`makepkg` cannot run on the Windows host this repo is developed on, so a build
has to be tried on an Arch machine or a container before the first push.
