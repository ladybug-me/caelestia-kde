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
| TUI installer and install steps | `installer/` | Rust |
| Steps not ported yet | `scripts/` | Bash |
| User-facing update scripts | `src/bin/` | Bash |

## Development workflow

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
make build-shell   # Recompiles and installs the plugins
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
cargo test --manifest-path installer/Cargo.toml          # unit and process tests
cargo clippy --manifest-path installer/Cargo.toml --all-targets -- -D warnings
cargo fmt --manifest-path installer/Cargo.toml
cargo build --release --manifest-path installer/Cargo.toml   # Linux only
```

These need the newest stable Rust: `rust-version` in `installer/Cargo.toml` names the
release the crate tracks, and an older toolchain refuses the build.

The installer is a Rust crate at `installer/`, and it is Linux-only: the wizard, the
step runner and the credential all use unix facilities. Everything that is portable
(the CLI, the step table, the menu tree, the screens, the runner) is covered by
`cargo test` on any host, and the screens are asserted through ratatui's test
backend, so a layout change is caught without a terminal.

The theme, the Configure menu and the step table are Rust source, not data files, so
adding an option or a step is an ordinary edit and the compiler checks its shape.
`installer/data/tui.version` survives only as the marker that ties a published binary
to the checkout it belongs to: `scripts/setup.sh` downloads the asset for that version
and refuses a binary that reports a different one. Bump it whenever the step table or
the wizard's contract changes, so a stale binary cannot run new scripts.

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
