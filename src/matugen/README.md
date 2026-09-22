# Matugen as the color pipeline

What `caelestia wallpaper` and `caelestia scheme` run, and how the palette reaches the applications that take theirs from a file. The work behind it is on the ticket [Owning the color pipeline](../../docs/wayfinder/parity/tickets/owning-the-color-pipeline.md).

`scheme.json.tmpl` is the palette the shell reads. `templates/` holds the theming fan-out, vendored from [matugen-themes](https://github.com/InioX/matugen-themes) with its provenance in `templates/README.md`. There is no config file here: `src/bin/caelestia-color` writes one per run, because which targets are on is the user's setting and matugen takes a config per invocation.

## Why matugen

It generates Material You palettes from an image or a single color, using the same specification upstream's `python-materialyoucolor` implements, and it writes files through a template engine. That covers generation and, when the templates are written, the theming fan-out to terminals, GTK, Qt and the rest, which today lives in the upstream CLI's `theme.py`.

It is packaged in Arch's `extra`, and it is GPL-2.0-or-later, which combines with our GPL-3.0-or-later. Carrying the upstream CLI instead would force this package to `GPL-3.0-only`.

## The contract this template has to hit

`shell/services/Colours.qml` reads `$XDG_STATE_HOME/caelestia/scheme.json`:

- `name`, `flavour`, `mode` and `variant` are plain strings, trimmed on read;
- `intensity` is the saturation the palette was rendered at, a number. Absent reads as 1, which is what matugen produced, so a scheme written before the knob existed is not a change of look;
- `colours` holds the roles. Each key becomes `m3<Key>` on the QML side, so the file carries `primary`, not `m3primary`. Keys beginning with `term` are used as they are, which is how `term0` to `term15` arrive;
- a value is the hex digits only. `Colours.qml` prepends the `#` itself, which is why the template asks for `hex_stripped` and not `hex`;
- a key that is absent leaves the shell's built-in default in place, so the template can grow instead of landing complete.

## Verified on Arch, matugen 4.2.0

Rendered against a real wallpaper on the CachyOS VM, end to end, with no errors:

- the role keywords are snake_case, 50 of them. This template uses 49, and every one renders;
- `{{ colors.<role>.default.hex_stripped }}` gives hex without the `#`, which is what the shell wants. Every value in the rendered file is exactly six characters;
- `{{ mode }}` renders `light` or `dark`, so the mode comes from matugen rather than from the command;
- `{{ base16.base00.default.hex_stripped }}` through `base0f` render the 16 `term` colors, so the terminals come from the same run;
- `--import-json-string '{"name":"dynamic","flavour":"default","variant":"tonalspot"}'` makes `{{ name }}`, `{{ flavour }}` and `{{ variant }}` resolve. The command supplies the metadata, matugen supplies the colors;
- the rendered file parses and carries 65 color keys: 49 roles plus 16 terminals.

One correction the run forced: the five `*_paletteKeyColor` roles the shell declares do not exist in
matugen's role list, so the template omits them. The reason first written down here - that nothing
reads them - was wrong: the palette manager the shell loads reads `m3primary_paletteKeyColor`. They
are folded in after the render now, which the section below describes.

## The wallpaper picks the variant

`wallpaper -f` and `wallpaper -p` ask the wallpaper which mode and variant to use unless `--no-smart`
says otherwise. The mode is matugen's own `--mode smart`, which resolves to light or dark during the
render and is read back out of the rendered file, so it is the one that is really in effect.

The variant cannot be done that way. matugen's `scheme-smart` makes that choice too, but it does not
say which scheme type it used, and the variant is written into scheme.json and read by the shell to
name the palette. So the command measures the wallpaper with the same colourfulness
formula upstream used - Hasler and Süsstrunk's, over the image scaled into 128x128 with the nearest
filter, which is the thumbnail upstream measured - and hands matugen a concrete type. Under 10 is
neutral, under 20 is content, above is tonal spot. ffmpeg does the decoding, because this port
already needs it for video wallpapers.

Checked against upstream's own implementation on the same six wallpapers: every one picked the same
variant, and the palette matches a direct render of the type the scheme is filed under. Without
ffmpeg there is nothing to measure, so matugen chooses and the name is a guess; the command says so
when that happens.

## What the command wires up

The generated config carries one `[templates.*]` block per enabled target, and `caelestia-color`
keeps the table that says which template writes where. A target is enabled by a key in
`~/.config/caelestia/cli.json`, the file the installer already writes:

| Key | Writes |
| --- | --- |
| `theme.enableKde` | `~/.local/share/color-schemes/Matugen.colors` |
| `theme.enableKvantum` | `~/.config/Kvantum/matugen/matugen.kvconfig` and `.svg`, and selecting that theme |
| `theme.enableKonsole` | `~/.local/share/konsole/Matugen.colorscheme`, and pointing the profiles at it |
| `theme.enableQt` | `~/.config/qt5ct/colors/matugen.conf`, the same for qt6ct |
| `theme.enableGtk` | `~/.config/gtk-3.0/colors.css`, `~/.config/gtk-4.0/colors.css` |
| `theme.enableTerm` | `~/.cache/caelestia/terminal-sequences`, then every shell pty |
| `theme.enableBtop` | `~/.config/btop/themes/matugen.theme` |
| `theme.enableCava` | `~/.config/cava/themes/matugen` |
| `theme.enableDiscord` | the two Vesktop themes |
| `theme.enableSpicetify` | `~/.config/spicetify/Themes/Sleek/color.ini` |
| `theme.enableZed` | `~/.config/zed/themes/matugen.json` |
| `theme.enableFuzzel`, `enableRofi`, `enableFoot`, `enableKitty` | their own color files |
| `theme.enableVscode` | `~/.cache/matugen/vscode-colors` and its `.json` |
| `theme.enableStarship` | `~/.config/starship.toml`, off unless asked for |

The keys upstream defined keep upstream's meaning, including that an absent key means on; the rest
are ours and default the same way, except `enableStarship` and Papirus. A target that writes
nothing today because the application is not installed is still written, which is what upstream
did and costs a file in a directory that already exists.

Two things cannot be a template. The terminal sequences go to the ptys that are running a shell,
and only those: writing escape sequences into a pty whose foreground process is something else
feeds them to that program as input. That guard used to live in `scripts/09-system-tweaks.sh`,
which patched the upstream CLI's `theme.py` in place; it is now part of `caelestia-color` and the
patch step is gone. Spicetify is told to re-read its theme, if it is installed.

## Applying the palette

A file on disk is not a theme. KDE reads a color scheme when one is applied to it, so the command
applies it after every change, and it is now the only thing that does:

- Plasma, through `plasma-apply-colorscheme`. That tool prints "already set" and does nothing when
the name it is handed is the one in effect, so the palette is written under two names and applied
under whichever is not current: `Matugen` and `Matugen Alt`, both carrying the palette that was just
generated. The pair is what makes a change look like a change of name, and it is why System Settings
lists two Material You entries.
- Konsole, which reads a scheme of its own with `R,G,B` per entry. matugen has no template for that
format, so the command renders it from the palette and points the profiles that exist at it.
- Kvantum, by selecting the theme the fan out just wrote, `matugen`, in
`~/.config/Kvantum/kvantum.kvconfig`. Selecting it is idempotent, and it is also how a fresh install
picks the generated theme over the one the dotfiles ship.

An accent color in `kdeglobals` is removed as part of this. Plasma rewrites the focus, link and
selection colors from it, on top of the scheme it has just been given, which would quietly replace
part of the palette with a color picked at some other time. The scheme carries the accent instead.

The two hooks the installer registers still run, with the environment upstream gave them: after
every color change `theme.postHook` with `SCHEME_NAME`, `SCHEME_FLAVOUR`, `SCHEME_MODE`,
`SCHEME_VARIANT` and `SCHEME_COLOURS`, and after every `wallpaper -f` `wallpaper.postHook` with
`WALLPAPER_PATH` and `THUMBNAIL_PATH` as well. This port does not downscale a wallpaper, so
`THUMBNAIL_PATH` is the wallpaper itself where upstream handed over a 128px thumbnail.

`~/.config/caelestia/templates/` is rendered the same way too, into
`$XDG_STATE_HOME/caelestia/theme/`. Those files are written against upstream's `{{ role.hex }}`
syntax rather than matugen's, so they are rendered by the command instead of by a template: the
SDDM theme the installer registers is one of them, and the greeter reads the result.

## The palette will look different

Accepted on 2026-09-12 rather than compensated for. Against the same wallpaper and the same scheme
type, matugen's surfaces come out lighter than the current pipeline's and its accents brighter and
more saturated: background `101417` against `0b0f11`, primary `92cef5` against `a6cbe6`. matugen
follows the specification; the CLI post-processes its result.

Reproducing that adjustment, and tuning these roles back inside the template with matugen's filters,
were both considered and rejected: each leaves us maintaining a transform derived by
reverse-engineering someone else's post-processing. The release notes carry the change when it
ships.

What was not rejected is the same transform under the user's own hand, because the 2024
specification took the chroma out of the vibrant variant and the people who picked it noticed
(issue #791). `caelestia scheme set -i` scales the saturation of the palette a render produced,
which is chroma with the tone left alone, in a range of 0 to 2: 0 leaves a grey palette at the
tones it already had, 1 is matugen's own output byte for byte, and 2 is as far as the accents go
before they flatten into one hue. It is off by default, so the palette a fresh install gets is the
accepted one above.

It lives in `scheme.json` beside the variant rather than in the CLI's config, because every
re-derive - `wallpaper -f`, the login reseed, the login screen's own `scheme set` - starts by
reading the scheme in effect, so the factor travels with it and none of those callers has to know
about it. `shell/services/Colours.qml` reads it from the same file, which is what the slider on
Nexus's Advanced Colors page is bound to; that page re-renders when the slider is let go rather
than as it is dragged. A named scheme records the factor but is not scaled: its file is the
palette.

Scaling it costs a second render. matugen writes the fan out from its own palette, and that is not
the palette the intensity asks for, so at any intensity but the default the palette is rendered
once, scaled, and handed back to matugen as data for a second run that writes the fan out - the way
a named scheme is fed in. Without that, the shell would be themed at the user's intensity while the
terminals, GTK, Qt and the scheme Plasma is applied stayed at matugen's. At the default intensity,
which is what every install is on until somebody moves the slider, one pass still does everything.

## Still open

- Papirus folder icons are not themed. The template needs a `colors_to_compare` list and a `compare_to`, and tinting folders needs sudo, so it stays out until there is a story for that.
- `enableStarship` is off by default: the template renders a whole `starship.toml`, which would replace a file the user owns. Turn it on in `cli.json` to have it written.
- The flavour `hard` for a dynamic scheme is accepted and ignored. It darkened the surfaces in the upstream pipeline, and matugen has no equivalent.
- Chromium-family policy files, nvtop, htop, Warp and Pandora were themed by the upstream CLI and have no template here. Hyprland is not part of a KDE port.
- The palette difference against the pipeline this replaces is measured and accepted, and is recorded in the ticket.

## The roles matugen cannot name

A generated scheme is not only what a render produces. Four families of role are read by something
here and have no matugen keyword, so the command folds them in after the render:

- the five palette key colors, `primary_paletteKeyColor` and its four companions. The Material
  palette key color is tone 50 of its palette, and matugen prints the palettes in `--json` but a
  template cannot ask for one shade by name - the shades are keyed by number and the template
  language takes no index. So `palettes.json.tmpl` dumps all of them, and the command picks tone
  50 out of each. These matter more than they look: `shell/services/Colours.qml` reads
  `m3primary_paletteKeyColor` out of the loaded palette, and the greeter's template reads it too;
- `success`, `onSuccess`, `successContainer` and `onSuccessContainer`, read by the toasts, the
  weather and the palette manager. Upstream hand-picked these rather than deriving them, and its
  values are used here so a generated scheme and a shipped one agree on what success looks like;
- `text`, which the greeter's template asks for. It is on surface, under a Catppuccin name.

The rest of upstream's extra roles are deliberately not carried, because nothing in this repository
reads them: the `k` colors, the Catppuccin names other than `text`, and the `Dim` variants. A role
that only exists to match upstream's file would be a row of numbers maintained for nobody.

A named scheme needs none of this: its file carries 110 roles already, `success` and `text` among
them, and it is written out as it is.

## Trying it

`caelestia-color` leaves the config it generated in place, which is the thing to read when a target does not change:

    $XDG_STATE_HOME/caelestia/matugen/config.toml

Feeding it to matugen by hand renders the same palette without touching anything:

    matugen image /path/to/wallpaper.jpg --config ~/.local/state/caelestia/matugen/config.toml \
        --source-color-index 0 --mode dark --type scheme-tonal-spot --dry-run

`--dry-run` prints the rendered files instead of writing them. Leave `--source-color-index` off and matugen asks which color to use, which needs a terminal.
