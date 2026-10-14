import { Hct } from '@material/material-color-utilities';
import { describe, expect, it } from 'vitest';

import { ROLES, scaleChroma, themeProperties } from '../../src/lib/palettes/dynamic';

const SOURCE = 0xff7b4c9e; // A wallpaper-ish purple.

const chromaOf = (hex: string): number => Hct.fromInt(Number.parseInt(hex.slice(1), 16)).chroma;
const toneOf = (hex: string): number => Hct.fromInt(Number.parseInt(hex.slice(1), 16)).tone;

describe('scaleChroma', () => {
    it("leaves the colour alone at the engine's own intensity", () => {
        expect(scaleChroma(SOURCE, 1)).toBe(SOURCE);
    });

    it('drains the chroma at zero without touching the tone', () => {
        const grey = scaleChroma(SOURCE, 0);
        expect(Hct.fromInt(grey).chroma).toBeLessThan(3);
        // Tone survives the round trip; hue is meaningless once chroma is gone.
        expect(Hct.fromInt(grey).tone).toBeCloseTo(Hct.fromInt(SOURCE).tone, 0);
    });

    it('takes the accents further at two, and keeps the hue', () => {
        const before = Hct.fromInt(SOURCE);
        const after = Hct.fromInt(scaleChroma(SOURCE, 2));
        expect(after.chroma).toBeGreaterThan(before.chroma);
        expect(after.hue).toBeCloseTo(before.hue, 0);
    });

    it('is monotonic, so the slider never reverses direction', () => {
        let previous = -1;
        for (const intensity of [0, 0.5, 1, 1.5, 2]) {
            const chroma = Hct.fromInt(scaleChroma(SOURCE, intensity)).chroma;
            expect(chroma).toBeGreaterThan(previous);
            previous = chroma;
        }
    });
});

describe('themeProperties', () => {
    const properties = themeProperties(SOURCE);

    it('produces every role the site exposes, for both modes', () => {
        for (const mode of ['dark', 'light'] as const) {
            for (const [role, property] of Object.entries(ROLES)) {
                expect(properties[mode][property], `${mode} ${role} (${property})`).toMatch(/^#[0-9a-f]{6}$/);
            }
        }
    });

    it("fills the site's own roles from the scheme", () => {
        for (const property of ['--code-text', '--code-subtext', '--code-overlay']) {
            expect(properties.dark[property]).toMatch(/^#[0-9a-f]{6}$/);
        }
    });

    it('gives the terminal colours, so code blocks follow the wallpaper', () => {
        for (let index = 0; index < 16; index += 1) {
            expect(properties.dark[`--term-${index}`]).toMatch(/^#[0-9a-f]{6}$/);
        }
    });

    it('makes a light scheme that is actually lighter than the dark one', () => {
        expect(toneOf(properties.light['--surface'])).toBeGreaterThan(toneOf(properties.dark['--surface']));
    });

    it("takes the source colour's hue into the primary role", () => {
        const primary = Hct.fromInt(Number.parseInt(properties.dark['--primary'].slice(1), 16));
        expect(primary.hue).toBeCloseTo(Hct.fromInt(SOURCE).hue, 0);
    });

    it('answers the same way twice, so a rebuild does not shuffle the palette', () => {
        expect(themeProperties(SOURCE)).toEqual(properties);
    });
});

describe('intensity', () => {
    it('is the whole point of the control: zero is a grey palette at the same tones', () => {
        const grey = themeProperties(SOURCE, 0);
        expect(chromaOf(grey.dark['--primary-container'])).toBeLessThan(5);
        expect(chromaOf(grey.dark['--tertiary'])).toBeLessThan(5);
        // The palette is greyer, not darker: the tones are the same.
        expect(toneOf(grey.dark['--surface'])).toBeCloseTo(toneOf(themeProperties(SOURCE).dark['--surface']), 0);
    });

    it('scales the accents up as it is turned up', () => {
        const plain = themeProperties(SOURCE, 1);
        const louder = themeProperties(SOURCE, 2);
        expect(chromaOf(louder.dark['--primary-container'])).toBeGreaterThan(
            chromaOf(plain.dark['--primary-container']),
        );
        expect(chromaOf(louder.dark['--tertiary'])).toBeGreaterThan(chromaOf(plain.dark['--tertiary']));
    });

    it('leaves the surfaces near-neutral at every setting', () => {
        for (const intensity of [0, 1, 2]) {
            expect(chromaOf(themeProperties(SOURCE, intensity).dark['--surface'])).toBeLessThan(20);
        }
    });
});
