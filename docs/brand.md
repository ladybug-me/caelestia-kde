# Brand rules

The name, palette, logo and voice every user-facing change must follow. This
page stands alone; when it and a component disagree, this page wins and the
component needs the fix.

## The name

- **Caelestia** - one word, capital C, in prose and UI titles ("Caelestia
  installer", "Install Caelestia").
- **caelestia** - lowercase for everything a shell has to type: the `caelestia`
  CLI, `caelestia-install`, `caelestia-update`, the config tree
  `~/.config/quickshell/caelestia/`, the state directory, unit and D-Bus names.
- **caelestia-kde** - the repository and package name, because the port runs on
  KDE Plasma. In user-facing text it is still just Caelestia; never "Caelestia
  KDE" or "CaelestiaKDE".

## The logo

The mark lives in two places that must stay identical:

- `assets/logo.svg` - the copy README and the docs use.
- `shell/assets/logo.svg` - the copy the shell itself renders.

Ship it as SVG; do not recolor, outline, rotate or put it on a busy background.
Where a raster is unavoidable, keep it large enough that the strokes survive.

## Color

The shell is **dynamic color**: matugen derives the whole scheme from the user's
wallpaper, and the shell reads it through the colour scheme and font tokens -
never a hex literal. A user-facing change that hardcodes a color (QML or C++)
breaks every wallpaper but its author's, so it does not ship.

Two places use a fixed palette on purpose:

- The installer TUI (all terminals, no wallpaper): `installer/data/theme.json`
  defines it - surface `#0a0f0f`, primary `#9bd0cc`, accent `#6ae5e1`, on
  surface `#dce8e6`, secondary `#b0ccc9`, muted `#6d7876`, warning `#e8c87a`,
  error `#fa746f`. Reuse those names; a new state reuses the nearest role
  instead of a new hex.
- The lock screen and SDDM themes follow the same dark-teal family so the
  session looks like one product from lock to unlock.

## Typography

| Face | Where it is used |
| --- | --- |
| SF Pro | The shell's default UI face (bundled under `shell/assets/fonts/`) |
| Google Sans Flex | SDDM themes and the lock screen clock (shipped beside the theme) |
| SF Mono, CaskaydiaCove NF (Cascadia Nerd) | Monospace faces, selectable in Nexus |
| JetBrains Mono Nerd, Rubik | Installed as system fonts by the per-distro package lists |
| Material Symbols Rounded | Every icon glyph in the shell |

Sizing, weight and letter spacing come from the shared font tokens
(`Tokens.font.*`), not per-component literals - the same text role should look
the same everywhere it appears.

Icons are Material Symbols Rounded for actions, plus the monochrome
`yet-another-monochrome-icon-set` for the shell's own file-type and status
art. Do not mix a third icon family in.

## Voice

Short, plain, honest. Terminal messages keep the installer's log prefixes and
case - `[INFO]`, `[OK]`, `[WARN]`, `[ERR]` - one sentence each, no exclamation
marks, no emoji in the TUI. UI text says what a thing does ("Restart the
shell"), not what it is ("Shell restart utility"). When something fails, name
the failing thing and the next action the user can take; the TROUBLESHOOTING
doc carries the long explanations.

English is the source language: every user-facing string goes through `qsTr()`
(see [translations.md](translations.md) for the catalogue workflow).
