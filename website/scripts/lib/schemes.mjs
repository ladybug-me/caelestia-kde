// Reads the shell's named scheme files (`src/schemes/<name>/<flavour>/<mode>.txt`)
// into the shape the site needs.
//
// The files are the same ones `caelestia scheme set -n <name> -f <flavour>` reads,
// so a palette added upstream shows up on the site without touching site code. The
// parser is deliberately strict: a malformed line is an error rather than a
// silently dropped role, because a missing role would surface as an unstyled
// element rather than a build failure.
//
// The three levels are the CLI's own `caelestia-color scheme list` levels: a name
// (`catppuccin`), a flavour (`mocha`) and a mode (`dark`). Scheme files do not all
// ship both modes, and a flavour is either a colour treatment (`hard`, `soft`) or
// the palette's own naming (`mocha`, `dawn`).

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const MODES = ['dark', 'light'];

// Human labels for the flavours that ship today. Anything else falls back to a
// title-cased id, so a new flavour still renders sensibly.
const LABELS = {
    caelestia: 'Caelestia',
    catppuccin: 'Catppuccin',
    darkgreen: 'Dark Green',
    dracula: 'Dracula',
    everblush: 'Everblush',
    everforest: 'Everforest',
    gruvbox: 'Gruvbox',
    nord: 'Nord',
    oldworld: 'Old World',
    onedark: 'One Dark',
    rosepine: 'Rosé Pine',
    shadotheme: 'Shado',
    solarized: 'Solarized',
    tokyonight: 'Tokyo Night',
};

/**
 * The roles the site consumes, mapped to the CSS custom property each one is
 * exposed as. A subset of the 110 keys in the scheme files: the Material You
 * roles the shell's own components use, plus the terminal colours the code
 * blocks are painted from.
 */
export const SITE_ROLES = {
    background: '--bg',
    onBackground: '--on-bg',
    surface: '--surface',
    surfaceDim: '--surface-dim',
    surfaceBright: '--surface-bright',
    surfaceContainerLowest: '--surface-container-lowest',
    surfaceContainerLow: '--surface-container-low',
    surfaceContainer: '--surface-container',
    surfaceContainerHigh: '--surface-container-high',
    surfaceContainerHighest: '--surface-container-highest',
    onSurface: '--on-surface',
    surfaceVariant: '--surface-variant',
    onSurfaceVariant: '--on-surface-variant',
    outline: '--outline',
    outlineVariant: '--outline-variant',
    inverseSurface: '--inverse-surface',
    inverseOnSurface: '--inverse-on-surface',
    shadow: '--shadow',
    scrim: '--scrim',
    surfaceTint: '--surface-tint',
    primary: '--primary',
    primaryDim: '--primary-dim',
    onPrimary: '--on-primary',
    primaryContainer: '--primary-container',
    onPrimaryContainer: '--on-primary-container',
    secondary: '--secondary',
    secondaryContainer: '--secondary-container',
    onSecondaryContainer: '--on-secondary-container',
    tertiary: '--tertiary',
    tertiaryContainer: '--tertiary-container',
    onTertiaryContainer: '--on-tertiary-container',
    error: '--error',
    errorContainer: '--error-container',
    onErrorContainer: '--on-error-container',
    success: '--success',
    successContainer: '--success-container',
    text: '--code-text',
    subtext1: '--code-subtext',
    overlay0: '--code-overlay',
};

export const TERM_ROLES = Array.from({ length: 16 }, (_, i) => `term${i}`);

/** Flavour id -> label, with a title-cased fallback for anything new. */
export function labelFor(id) {
    if (LABELS[id]) return LABELS[id];
    return id
        .replace(/[_-]+/g, ' ')
        .replace(/([a-z])([A-Z])/g, '$1 $2')
        .replace(/^./, (c) => c.toUpperCase());
}

/**
 * Parses one `role hex` per line file. The hex digits carry no `#`, which is
 * the format `src/schemes/README.md` documents.
 */
export function parseSchemeFile(text, source = '<scheme>') {
    const roles = {};
    const lines = text.split(/\r?\n/);

    lines.forEach((raw, index) => {
        const line = raw.trim();
        if (!line || line.startsWith('#')) return;

        const parts = line.split(/\s+/);
        if (parts.length !== 2) {
            throw new Error(`${source}:${index + 1}: expected "role hex", got ${JSON.stringify(raw)}`);
        }

        const [role, hex] = parts;
        if (!/^[0-9a-fA-F]{6}$/.test(hex)) {
            throw new Error(`${source}:${index + 1}: ${role} is not a six digit hex colour: ${hex}`);
        }
        if (role in roles) {
            throw new Error(`${source}:${index + 1}: duplicate role ${role}`);
        }

        roles[role] = `#${hex.toLowerCase()}`;
    });

    if (Object.keys(roles).length === 0) {
        throw new Error(`${source}: no roles found`);
    }

    return roles;
}

/**
 * Reads every name under `schemesDir`. The brand palette is returned separately
 * because it is the site's default and the one the shell's own documentation
 * points at.
 */
export function readSchemes(schemesDir) {
    if (!existsSync(schemesDir)) {
        throw new Error(
            `No scheme directory at ${schemesDir}. Run from the website directory with the repository checked out.`,
        );
    }

    const names = readdirSync(schemesDir, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
        .sort();

    if (names.length === 0) {
        throw new Error(`No palettes under ${schemesDir}`);
    }

    const schemes = names.map((id) => {
        const flavours = readdirSync(join(schemesDir, id), { withFileTypes: true })
            .filter((entry) => entry.isDirectory())
            .map((entry) => entry.name)
            .sort()
            .map((flavour) => {
                const modes = {};
                for (const mode of MODES) {
                    const file = join(schemesDir, id, flavour, `${mode}.txt`);
                    if (!existsSync(file)) continue;
                    modes[mode] = parseSchemeFile(readFileSync(file, 'utf8'), `${id}/${flavour}/${mode}.txt`);
                }
                if (Object.keys(modes).length === 0) {
                    throw new Error(`${id}/${flavour} has neither dark.txt nor light.txt`);
                }
                return { id: flavour, label: labelFor(flavour), modes };
            });

        if (flavours.length === 0) {
            throw new Error(`Palette ${id} has no flavour directories`);
        }

        return { id, label: labelFor(id), flavours };
    });

    const brand = schemes.find((scheme) => scheme.id === 'caelestia');
    if (!brand) {
        throw new Error('The brand palette (src/schemes/caelestia) is missing');
    }

    return {
        brand,
        others: schemes.filter((scheme) => scheme.id !== 'caelestia'),
    };
}

/** The roles a scheme does not carry, so callers can fail loudly. */
export function missingRoles(roles, wanted = Object.keys(SITE_ROLES)) {
    return wanted.filter((role) => !(role in roles));
}
