# The named schemes

The palettes behind `caelestia scheme set -n catppuccin` and the rest: one file per name,
flavour and mode, holding `role hex` pairs. They are copied from the upstream Caelestia CLI,
which is where they come from and where they are maintained.

- Source: `https://github.com/caelestia-dots/cli`, path `src/caelestia/data/schemes`
- Commit: `6b84ee5090ec50f36aa1a53990d57ab0013925a0`
- Vendored: 2026-09-12
- Licence: GPL-3.0, the same as this repository

Copied unmodified except for the line endings: upstream ships these files with CRLF, which the
repository's own file hygiene check rejects, so they were normalized to LF. Content is unchanged,
which was checked by hashing every file against the upstream copy with the carriage returns
stripped and comparing the result.

Do not edit them here. They belong to upstream, and an edit becomes a silent divergence; refresh
instead.

    git clone --depth 1 https://github.com/caelestia-dots/cli /tmp/caelestia-cli
    # copy src/caelestia/data/schemes over this directory, then normalize the line
    # endings and update the commit above

## The format

One `role hex` pair per line, with the hex digits and no `#`. 110 keys in the files that ship
today: the Material You roles in the casing this port speaks (`surfaceContainer`, not
`surface_container`), the 16 terminal colors as `term0` to `term15`, the Catppuccin names, the
`k` colors the KDE side uses, and `success` with its three companions.

The casing is the reason this directory exists at all. `shell/services/Colours.qml` and the
scheme template in `src/matugen` both speak that casing, so a named scheme can be read straight
out of a file, while the generated one has to be translated from matugen's names. That mapping is
read out of the template rather than repeated, so a role added there is a role these files can
carry.

Not every name has every flavour, and not every flavour has both modes. `caelestia scheme list`
and the command's own mode fallback report the mode a flavour actually has rather than failing.

## Who reads it

`caelestia scheme list`, `scheme get` and `scheme set` in `src/bin/caelestia-color`, which is
installed with the shell. It also feeds the fan-out for a named scheme: the file is translated
into the render data matugen needs, so GTK, Qt, the terminals and the rest are themed from a
named palette the same way they are from a generated one.

`src/bin/caelestia-color` looks for this directory under `$CAELESTIA_DATA_DIR`,
`$CAELESTIA_LIB_DIR` and `/usr/share/caelestia`. The `08-build-shell` step installs it into the
first of those.
