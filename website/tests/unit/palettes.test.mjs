import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { TEXT_FLOORS, buildPalettes } from '../../scripts/gen-palettes.mjs';
import { contrastRatio } from '../../scripts/lib/contrast.mjs';
import { SITE_ROLES, missingRoles, parseSchemeFile, readSchemes } from '../../scripts/lib/schemes.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..', '..');
const schemesDir = join(repoRoot, 'src', 'schemes');

const built = buildPalettes({ schemesDir });

describe('parseSchemeFile', () => {
    it('reads role/hex pairs in the format the scheme files use', () => {
        const roles = parseSchemeFile('primary 9bd0cc\nonPrimary 0d4845\n', 'test');
        expect(roles).toEqual({ primary: '#9bd0cc', onPrimary: '#0d4845' });
    });

    it('rejects a line it cannot read rather than dropping it', () => {
        expect(() => parseSchemeFile('primary 9bd0cc\ngarbage\n', 'test')).toThrow(/expected "role hex"/);
        expect(() => parseSchemeFile('primary nope\n', 'test')).toThrow(/not a six digit hex/);
        expect(() => parseSchemeFile('primary 9bd0cc\nprimary 0d4845\n', 'test')).toThrow(/duplicate role/);
        expect(() => parseSchemeFile('\n\n', 'test')).toThrow(/no roles/);
    });

    it('tolerates CRLF, which the vendored files are normalised away from', () => {
        expect(parseSchemeFile('primary 9bd0cc\r\n', 'test')).toEqual({ primary: '#9bd0cc' });
    });
});

describe('the tree of shipped schemes', () => {
    const { brand, others } = readSchemes(schemesDir);

    it('finds the brand palette and the rest of the names', () => {
        expect(brand.id).toBe('caelestia');
        expect(brand.flavours.map((flavour) => flavour.id)).toContain('default');
        expect(others.length).toBeGreaterThan(5);
    });

    it('carries every role the site exposes, in both modes of the brand palette', () => {
        const defaultFlavour = brand.flavours[0];
        expect(missingRoles(defaultFlavour.modes.dark)).toEqual([]);
        expect(missingRoles(defaultFlavour.modes.light)).toEqual([]);
    });

    it('gives every flavour at least one mode', () => {
        for (const scheme of [brand, ...others]) {
            for (const flavour of scheme.flavours) {
                expect(Object.keys(flavour.modes).length).toBeGreaterThan(0);
            }
        }
    });
});

describe('the generated stylesheet', () => {
    it('has a rule for every palette and every mode it ships', () => {
        for (const palette of built.index.palettes) {
            for (const mode of palette.modes) {
                expect(built.css).toContain(`[data-palette='${palette.id}'][data-mode='${mode}']`);
            }
        }
    });

    it('falls back to the brand palette on :root, so a missing role still resolves', () => {
        expect(built.css).toMatch(/:root \{/);
        expect(built.css).toMatch(/:root\[data-mode='light'\]/);
        // `success` is not in the vendored palettes; it must come from the root.
        expect(built.css).toMatch(/--success:/);
        expect(built.index.palettes.some((palette) => palette.name === 'catppuccin')).toBe(true);
    });

    it('paints code blocks from the palette, not from a fixed theme', () => {
        expect(built.css).toContain('--astro-code-token-keyword: var(--term-5)');
        expect(built.css).toContain('--astro-code-foreground: var(--code-text)');
    });

    it('defines a swatch for both modes of every palette, so the picker needs no data payload', () => {
        for (const palette of built.index.palettes) {
            expect(built.css).toContain(`:root[data-mode='dark'] .swatch[data-palette='${palette.id}']`);
            expect(built.css).toContain(`:root[data-mode='light'] .swatch[data-palette='${palette.id}']`);
        }
    });

    it('gives each swatch its own colours as values, not as references', () => {
        // A `var(--primary)` inside the swatch would resolve against the palette
        // in force, so every swatch in the grid would show the same colour.
        const block = built.css.match(
            /:root\[data-mode='dark'\] \.swatch\[data-palette='catppuccin-mocha'\] \{([^}]*)\}/,
        );
        expect(block).toBeTruthy();
        expect(block[1]).toMatch(/--swatch-primary: #[0-9a-f]{6}/);
        expect(block[1]).not.toContain('var(');
    });
});

describe('the generated index', () => {
    it('lists the palettes with the levels the shell CLI uses', () => {
        const { palettes } = built.index;
        const catppuccin = palettes.filter((palette) => palette.name === 'catppuccin');

        expect(catppuccin.length).toBeGreaterThan(1);
        expect(catppuccin.every((palette) => palette.id.startsWith('catppuccin-'))).toBe(true);
        expect(catppuccin.map((palette) => palette.flavour)).toContain('mocha');
    });

    it('builds the command that reproduces the choice in the shell', () => {
        const palette = built.index.palettes.find((entry) => entry.id === 'catppuccin-mocha');
        expect(palette?.commands.dark).toBe('caelestia scheme set -n catppuccin -f mocha -m dark');
    });

    it('defaults to the brand palette in dark mode', () => {
        expect(built.index.default.palette).toBe('caelestia-default');
        expect(built.index.default.mode).toBe('dark');
        expect(built.index.palettes.find((palette) => palette.brand)?.modes).toContain('dark');
    });

    it('exposes a role set the palettes can actually satisfy, bar the ones the brand carries', () => {
        // Nothing in the site may depend on a role no palette has: `primaryDim`
        // is the one role only the brand palette carries, and tokens.css derives
        // it for the others.
        const carriers = Object.keys(SITE_ROLES).filter((role) => role !== 'primaryDim');
        const brandRoles = readSchemes(schemesDir).brand.flavours[0].modes.dark;
        expect(carriers.every((role) => role in brandRoles)).toBe(true);
        expect(built.warnings.every((warning) => warning.includes('primaryDim'))).toBe(true);
    });
});

describe('the generated files on disk', () => {
    it('are what the generator produces', () => {
        const css = readFileSync(join(here, '..', '..', 'src', 'styles', 'generated', 'palettes.css'), 'utf8');
        const json = JSON.parse(readFileSync(join(here, '..', '..', 'src', 'data', 'palettes.json'), 'utf8'));
        expect(css).toBe(built.css);
        expect(json).toEqual(built.index);
    });
});

/** Every palette rule in the generated stylesheet, with the hex roles it sets. */
function paletteRules(css) {
    return [...css.matchAll(/^([^@\n][^{\n]*)\{([^}]*)\}/gm)]
        .filter(([, selector]) => !selector.includes('.swatch'))
        .map(([, selector, body]) => {
            const roles = {};
            for (const [, property, value] of body.matchAll(/(--[a-z-]+):\s*(#[0-9a-f]{6})/g)) {
                roles[property] = value;
            }
            return { selector: selector.trim(), roles };
        });
}

describe('the contrast floors', () => {
    // One rule per pair the stylesheet paints. A theme file is written for the
    // shell's own components, so a role that reads fine in a popout can be under
    // the ratio a paragraph needs, and the generator is what closes the gap.
    it('ships no pair below the floor it is painted at', () => {
        const failures = [];

        for (const { selector, roles } of paletteRules(built.css)) {
            for (const [role, floor, surfaces] of TEXT_FLOORS) {
                const foreground = roles[SITE_ROLES[role]];
                if (!foreground) continue;

                for (const surface of surfaces) {
                    const background = roles[SITE_ROLES[surface]];
                    if (!background) continue;

                    const ratio = contrastRatio(foreground, background);
                    if (ratio < floor) {
                        failures.push(
                            `${selector}: ${role} on ${surface} is ` +
                                `${ratio.toFixed(2)}, needs ${floor} (${foreground} on ${background})`,
                        );
                    }
                }
            }
        }

        expect(failures).toEqual([]);
    });

    it('moves a role rather than shipping the palette as written', () => {
        // The floors are only worth anything if something failed them: a palette
        // set that needed no adjustment would mean the list above went stale.
        expect(built.adjustments.length).toBeGreaterThan(0);
    });
});

describe('the custom properties the stylesheets read', () => {
    it('are all declared, so no rule paints with a property that does not exist', () => {
        const stylesDir = join(here, '..', '..', 'src');

        const files = [];
        const walk = (dir) => {
            for (const entry of readdirSync(dir, { withFileTypes: true })) {
                const path = join(dir, entry.name);
                if (entry.isDirectory()) walk(path);
                else if (/\.(css|astro)$/.test(entry.name)) files.push(path);
            }
        };
        walk(stylesDir);

        const declared = new Set();
        const read = new Map();
        for (const file of files) {
            const source = readFileSync(file, 'utf8');
            for (const [, property] of source.matchAll(/(--[a-z0-9-]+)\s*:/g)) declared.add(property);
            for (const [, property] of source.matchAll(/var\((--[a-z0-9-]+)/g)) {
                if (!read.has(property)) read.set(property, file);
            }
        }

        // Astro's Font component writes this one into the document at build time.
        declared.add('--font-sans');

        const undeclared = [...read.keys()].filter((property) => !declared.has(property));
        expect(undeclared.map((property) => `${property} (${read.get(property)})`)).toEqual([]);
    });
});
