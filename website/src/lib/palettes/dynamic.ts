/**
 * The wallpaper-derived palette.
 *
 * Mirrors what the shell does when the wallpaper changes: one source colour,
 * expanded into a full scheme, applied to every surface at once.
 *
 * Two choices worth knowing about:
 *
 *   - The scheme is built from the **content** variant of the Material You
 *     algorithm rather than the tonal-spot default. Content keeps the source's
 *     own chroma in the accent palettes, which is what makes the intensity
 *     control mean anything: at 0 the palette is grey at the same tones, at 1 it
 *     is the wallpaper's saturation, at 2 it is as far as those tones can hold.
 *     The shell's own engine (matugen, in Rust) scales the palette the same way;
 *     the two agree in shape rather than byte for byte, which is why the site
 *     shows the idea and the picker ships the shell's own files.
 *   - The 2021 spec is pinned. The 2025 revision fixes chroma per variant and
 *     ignores the source's, which would make the slider inert.
 *
 * One deliberate omission: no tone/variant picker. The port retired it from its
 * own UI, so the site does not offer what the desktop does not.
 */

import { Hct, SchemeContent, hexFromArgb } from '@material/material-color-utilities';

/**
 * Scheme role -> CSS custom property. The role names are Material's; the
 * properties are the ones the shell exposes, so the two can be compared.
 */
export const ROLES: Record<string, string> = {
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
};

/**
 * The site's own roles, taken from the closest thing the scheme has. `success`
 * has no Material role at all and keeps the brand palette's value; it only
 * carries the copy button's confirmation state.
 */
const DERIVED: Record<string, string> = {
    '--code-text': 'onSurface',
    '--code-subtext': 'onSurfaceVariant',
    '--code-overlay': 'outline',
};

/**
 * Terminal colours for code blocks. A wallpaper has no terminal, so the scheme's
 * own accents stand in: the block recolours with the wallpaper instead of
 * keeping the previous palette's syntax colours.
 */
const TERM_SOURCES: string[] = [
    'onSurfaceVariant',
    'error',
    'tertiary',
    'tertiaryContainer',
    'primary',
    'secondary',
    'primaryContainer',
    'onSurface',
    'outline',
    'error',
    'tertiary',
    'tertiaryContainer',
    'primary',
    'secondary',
    'primaryContainer',
    'onSurface',
];

export type ThemeProperties = { dark: Record<string, string>; light: Record<string, string> };
export type ThemeMode = keyof ThemeProperties;

/**
 * Scales a colour's chroma while keeping its hue and tone.
 *
 * This is the shell's intensity: 1 is what the colour engine produced, 0 is a
 * grey palette at the same tones, and 2 is as far as the accents go. Named
 * palettes are their own files and are not scaled, so the shell applies this
 * only to a wallpaper-derived palette — and so does the site.
 */
export function scaleChroma(argb: number, intensity: number): number {
    if (intensity === 1) return argb;
    const hct = Hct.fromInt(argb);
    return Hct.from(hct.hue, hct.chroma * intensity, hct.tone).toInt();
}

/**
 * The custom properties for a scheme built from one source colour, split by mode
 * so the applier writes only the set in force.
 */
export function themeProperties(sourceArgb: number, intensity = 1): ThemeProperties {
    const source = Hct.fromInt(scaleChroma(sourceArgb, intensity));
    const result: ThemeProperties = { dark: {}, light: {} };

    for (const mode of ['dark', 'light'] as const) {
        const scheme = new SchemeContent(source, mode === 'dark', 0, '2021') as unknown as Record<string, number>;

        const write = (property: string, value: number | undefined): void => {
            if (typeof value === 'number') result[mode][property] = hexFromArgb(value);
        };

        for (const [role, property] of Object.entries(ROLES)) write(property, scheme[role]);
        for (const [property, role] of Object.entries(DERIVED)) write(property, scheme[role]);
        TERM_SOURCES.forEach((role, index) => write(`--term-${index}`, scheme[role]));
    }

    return result;
}

/**
 * Writes the theme onto an element.
 *
 * Inline custom properties are how a wallpaper palette overrides the stylesheet
 * without the stylesheet having to know the palette exists.
 */
export function applyTheme(root: HTMLElement, properties: ThemeProperties, mode: ThemeMode): void {
    for (const [property, value] of Object.entries(properties[mode])) {
        root.style.setProperty(property, value);
    }
    root.dataset.palette = 'dynamic';
}

/** Removes a wallpaper theme, leaving whichever named palette is selected. */
export function clearTheme(root: HTMLElement, properties: ThemeProperties): void {
    for (const mode of ['dark', 'light'] as const) {
        for (const property of Object.keys(properties[mode])) {
            root.style.removeProperty(property);
        }
    }
}
