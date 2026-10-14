/**
 * The visitor's palette choice.
 *
 * The palette is a pair of attributes on <html> (`data-palette`, `data-mode`)
 * and every colour comes from CSS, so switching is a style recalculation rather
 * than a repaint done by script. An inline script in the layout applies the
 * stored choice before the first paint; this module is what the controls on the
 * page write to.
 */

export const PALETTE_KEY = 'caelestia:palette';
export const MODE_KEY = 'caelestia:mode';

export type Mode = 'dark' | 'light';

export interface PaletteState {
    palette: string;
    mode: Mode;
}

export const PALETTE_EVENT = 'caelestia:palette-change';

function store(key: string, value: string | null): void {
    try {
        if (value === null) localStorage.removeItem(key);
        else localStorage.setItem(key, value);
    } catch {
        // Private browsing blocks storage. The change still applies for this
        // page; it just does not survive a reload.
    }
}

export function getState(): PaletteState {
    const root = document.documentElement;
    return {
        palette: root.dataset.palette ?? '',
        mode: root.dataset.mode === 'light' ? 'light' : 'dark',
    };
}

function announce(): void {
    document.dispatchEvent(new CustomEvent<PaletteState>(PALETTE_EVENT, { detail: getState() }));
}

export function setPalette(id: string, { persist = true } = {}): void {
    document.documentElement.dataset.palette = id;
    if (persist) store(PALETTE_KEY, id);
    announce();
}

export function setMode(mode: Mode, { persist = true } = {}): void {
    document.documentElement.dataset.mode = mode;
    if (persist) store(MODE_KEY, mode);
    announce();
}

/** The colours currently in force, for drawing previews from the live palette. */
export function readTokens(...names: string[]): string[] {
    const styles = getComputedStyle(document.documentElement);
    return names.map((name) => styles.getPropertyValue(name).trim());
}
