# Contributing to Caelestia

We're glad you're here! This guide covers everything you need to start contributing.

## Quick start

```bash
git clone https://github.com/ladybug-me/caelestia-kde ~/caelestia-kde
cd ~/caelestia-kde
bash scripts/setup.sh  # Full install - do this at least once
```

Make your changes in the cloned repo, test them (see below), then open a PR. That's it.

## What makes a good PR?

> [!WARNING]
> Only PRs to **dev** branch are accepted!

- **One thing at a time.** If you have three features, send three PRs - it's much faster to review.
- **Keep your personal config out.** Don't include your wallpaper path, custom keybinds, or local settings.
- **Experimental features off by default.** If it's flashy or niche, add a config toggle and default it to `false`.
- **Big ideas? Open an issue first.** It saves you from writing code we might not be able to accept.

## Where stuff lives

| Area | Directory | Tech |
| ------ | ----------- | ------ |
| Shell UI (launcher, bar, notifications, etc.) | `shell/` | QML + Quickshell |
| Lock screen greeter (Plasma 6 shell) | `src/kde/shells/caelestia.desktop/` | QML + KDE ScreenLocker |
| KWin plugin (window management, shortcuts) | `shell/plugin/` | C++ |
| TUI installer | `installer/tui/` | C++ |
| Installer theme & menus | `installer/data/theme.json`, `installer/data/menu.json` | JSON |
| Install step scripts | `scripts/` | Bash |
| User-facing update scripts | `src/bin/` | Bash |

## Development workflow

### Build configuration

Builds are configured by CMake presets, not by flags repeated in each script:

- `shell/CMakePresets.json` - `dev`, `source-offline`, `package-offline`, `release`, `runtime`, `sanitizers`
- `installer/tui/CMakePresets.json` - `dev`, `release`, `sanitizers`

`make build` uses the shell's `dev` preset and CI runs the rest, so the
configuration you build with and the one CI builds with come from the same file.
A preset that builds offline needs `make fetch-dependencies` once first.

The packages the shell build needs are declared in
`packaging/build-dependencies.json`. Its `arch` column is what CI installs; the
Fedora and Debian columns may only name packages
`installer/distro/<distro>/packages.sh` already installs, so the manifest cannot
introduce a name nothing else has installed from. An empty list means no package
is named for that distribution yet. `make test-repo` checks all of it.

### For QML / shell changes

Edit files in `~/.config/quickshell/caelestia/`. Restart the shell.

```bash
# Restart the shell cleanly
~/.config/quickshell/caelestia/scripts/restart_shell.sh

# View live logs
caelestia-shell-ipc log
```

**Editor setup:**

- Run `touch ~/.config/quickshell/caelestia/.qmlls.ini` for QML language server support
- In VS Code, install the "Qt Qml" extension and set the `qmlls` path to `/usr/bin/qmlls6`


### For C++ plugin changes

```bash
make build                       # Configure and compile with the developer preset
bash scripts/08-build-shell.sh   # Compile and install them into your session
bash shell/scripts/restart_shell.sh  # Restart to pick up the new .so
```

The build keeps one core free and runs at a lower priority so the session stays
usable. Set `CAELESTIA_BUILD_JOBS` to override the job count.

### For Lock screen changes

The lock screen is a native KDE Plasma 6 shell package located in `src/kde/shells/caelestia.desktop/`.

```bash
# Copy the files to the local Plasma shells directory
mkdir -p ~/.local/share/plasma/shells/
cp -r src/kde/shells/caelestia.desktop ~/.local/share/plasma/shells/

# Set the shell package (if not already set)
kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop"

# Test the lock screen safely in an interactive window (without locking your session)
/usr/lib/kscreenlocker_greet --testing
```

### For installer changes

```bash
make installer                                # Compile with the developer preset
./installer/build/caelestia-install "$PWD"    # Run from the repo root (use with care!)
```

The installer reads `installer/data/theme.json` and `installer/data/menu.json`
relative to its bundle directory, which is the executable's own directory unless
you pass one as the first argument. That is why the run above passes `$PWD`;
`setup.sh` copies the binary to the repo root instead, where no argument is
needed.

Adding, removing or reordering a step means bumping `installer/data/tui.version`.
The step table is compiled into the TUI binary, and `scripts/setup.sh` keys on that
number alone: it downloads the prebuilt binary published for the version, and
otherwise reuses a local binary whose stamp matches it. Both paths can hand you a
binary built before your change, and then the new step silently never runs on a
fresh install. Bumping makes the prebuilt lookup miss, so the installer compiles
the tree instead, and the next release publishes the matching binary.

### For translation changes

```bash
tools/update-translations.sh          # refresh every catalog
tools/update-translations.sh es       # start a new one (Spanish here)
```

Translate `shell/translations/caelestia_<code>.ts`, rebuild the shell, then pick
the language in Nexus -> Language & region. See
[Translations](../docs/translations.md) for the full guide.

### For creating plugins

Head to [caelestia-kde-plugins](https://github.com/ladybug-me/caelestia-kde-plugins) for the plugin templates and guidelines.

## Code style (the short version)

**QML:**

- Spaces between operators: `if (condition) {` not `if(condition){`
- Prefer early returns: `if (!ok) return;` over deep nesting
- Group related properties with blank lines
- Import order: QtQuick -> Qt -> Quickshell -> Caelestia -> qs.components -> qs.services -> qs.modules
- Run `python3 shell/scripts/qml-lint-conventions.py` - it catches most issues

**Shell scripts:**

- Use `set -euo pipefail` at the top
- Prefer `[[ ]]` over `[ ]`
- Quote variables: `"$VAR"` not `$VAR`
- Run `shellcheck` on your scripts

## Security

- When calling shell commands from QML, pass arguments as an array - never
  concatenate strings:

  ```js
  // Good
  Quickshell.execDetached(["bash", "-c", "echo \"$1\"", "--", myVar])
  // Bad
  Quickshell.execDetached(["bash", "-c", "echo " + myVar])
  ```

- Use `Paths.runtimeTemp("filename")` for temporary files - not hardcoded `/tmp/` paths.

## Architecture docs

- [Brand rules](../docs/brand.md) - the name, palette, logo and voice every user-facing change must follow
- [KWin port architecture](../docs/architecture/kwin_port_architecture.md) - C++ plugin design and QML APIs
- [Lock screen architecture](../docs/architecture/lockscreen_architecture.md) - native Plasma 6 greeter design and component structure
- [Translations](../docs/translations.md) - i18n pipeline and how to add a language

## Stuck?

Open a [Discussion](https://github.com/ladybug-me/caelestia-kde/discussions) or ask in an issue - we're happy to help.
