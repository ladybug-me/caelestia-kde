// Contrast maths for the palette generator.
//
// The scheme files are written for the shell's own components, not for text on a
// page: a role that reads fine inside a popout can sit below the ratio a
// paragraph needs. So every pair the stylesheet paints is measured here, and a
// role that misses its floor is moved until it clears it.
//
// Moving happens in oklab, the space the stylesheet mixes in, so a value derived
// here and a value derived by `color-mix(in oklab, …)` agree.
//
// The direction is never assumed. A role is mixed towards white and towards black
// and the smallest move that clears the floor against every surface it is painted
// on wins, which is what makes one function serve both a dark palette that needs
// its accent lighter and a light palette that needs the same accent darker.

const WHITE = { l: 1, a: 0, b: 0 };
const BLACK = { l: 0, a: 0, b: 0 };

const STEP = 0.05;
const MAX_MIX = 0.9;

function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
}

/** `#rrggbb` to three 0-255 channels. Throws on anything else. */
export function toRgb(hex) {
    const match = /^#([0-9a-fA-F]{6})$/.exec(hex.trim());
    if (!match) throw new Error(`Not a six digit hex colour: ${hex}`);
    const value = parseInt(match[1], 16);
    return { r: (value >> 16) & 0xff, g: (value >> 8) & 0xff, b: value & 0xff };
}

function toHex({ r, g, b }) {
    const channel = (value) => clamp(Math.round(value), 0, 255).toString(16).padStart(2, '0');
    return `#${channel(r)}${channel(g)}${channel(b)}`;
}

function toLinear(channel) {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}

function fromLinear(channel) {
    const value = channel <= 0.0031308 ? channel * 12.92 : 1.055 * channel ** (1 / 2.4) - 0.055;
    return value * 255;
}

function toOklab(hex) {
    const { r, g, b } = toRgb(hex);
    const lr = toLinear(r);
    const lg = toLinear(g);
    const lb = toLinear(b);

    const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
    const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
    const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);

    return {
        l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
        a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
        b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    };
}

function fromOklab({ l, a, b }) {
    const lp = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3;
    const mp = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3;
    const sp = (l - 0.0894841775 * a - 1.291485548 * b) ** 3;

    return toHex({
        r: fromLinear(4.0767416621 * lp - 3.3077115913 * mp + 0.2309699292 * sp),
        g: fromLinear(-1.2684380046 * lp + 2.6097574011 * mp - 0.3413193965 * sp),
        b: fromLinear(-0.0041960863 * lp - 0.7034186147 * mp + 1.707614701 * sp),
    });
}

/** `t` is the weight of `to`: 0 returns `from`, 1 returns `to`. */
export function mixOklab(from, to, t) {
    const a = toOklab(from);
    const b = typeof to === 'string' ? toOklab(to) : to;
    return fromOklab({
        l: a.l + (b.l - a.l) * t,
        a: a.a + (b.a - a.a) * t,
        b: a.b + (b.b - a.b) * t,
    });
}

export function relativeLuminance(hex) {
    const { r, g, b } = toRgb(hex);
    return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);
}

/** WCAG 2 contrast ratio, 1 to 21. */
export function contrastRatio(a, b) {
    const one = relativeLuminance(a);
    const two = relativeLuminance(b);
    return (Math.max(one, two) + 0.05) / (Math.min(one, two) + 0.05);
}

/**
 * The colour closest to `hex` that clears `floor` against every one of
 * `backgrounds`, or the best it can do when nothing clears it.
 */
export function ensureContrast(hex, backgrounds, floor = 4.5, { maxMix = MAX_MIX } = {}) {
    const surfaces = backgrounds.filter(Boolean);
    if (surfaces.length === 0) return hex;
    if (surfaces.every((surface) => contrastRatio(hex, surface) >= floor)) return hex;

    let best = hex;
    let bestWorst = Math.min(...surfaces.map((surface) => contrastRatio(hex, surface)));

    for (let t = STEP; t <= maxMix + 1e-9; t += STEP) {
        for (const target of [WHITE, BLACK]) {
            const candidate = mixOklab(hex, target, t);
            const worst = Math.min(...surfaces.map((surface) => contrastRatio(candidate, surface)));
            if (worst >= floor) return candidate;
            if (worst > bestWorst) {
                best = candidate;
                bestWorst = worst;
            }
        }
    }

    return best;
}
