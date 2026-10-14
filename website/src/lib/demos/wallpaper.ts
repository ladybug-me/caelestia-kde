/**
 * Drop a wallpaper, watch the site become that wallpaper's palette.
 *
 * The work that can be slow (decode, downscale, quantise) is in a worker. The
 * work that must feel instant — the intensity slider — is applied on the spot:
 * while the slider is being dragged there is no animation at all, because
 * feedback during an interaction has to be continuous, not eased.
 */

import type { ThemeResponse } from '../../workers/theme-worker';
import { PALETTE_EVENT, getState } from '../palette-store';
import { applyTheme, clearTheme, themeProperties, type ThemeProperties } from '../palettes/dynamic';
import { hexFromArgb } from '@material/material-color-utilities';

export function initWallpaperDemo(root: HTMLElement): () => void {
    const input = root.querySelector<HTMLInputElement>('[data-wallpaper-input]');
    const drop = root.querySelector<HTMLElement>('[data-wallpaper-drop]');
    const swatch = root.querySelector<HTMLElement>('[data-wallpaper-swatch]');
    const status = root.querySelector<HTMLElement>('[data-wallpaper-status]');
    const intensity = root.querySelector<HTMLInputElement>('[data-wallpaper-intensity]');
    const intensityReadout = root.querySelector<HTMLElement>('[data-wallpaper-intensity-value]');
    const reset = root.querySelector<HTMLButtonElement>('[data-wallpaper-reset]');

    let source: number | null = null;
    let properties: ThemeProperties | null = null;
    let frame = 0;

    const say = (message: string): void => {
        if (status) status.textContent = message;
    };

    function paint(immediate = false): void {
        if (source === null) return;
        const value = Number(intensity?.value ?? '1');

        const render = () => {
            frame = 0;
            properties = themeProperties(source as number, value);
            applyTheme(document.documentElement, properties, getState().mode);
            if (swatch) swatch.style.background = hexFromArgb(source as number);
            if (intensityReadout) intensityReadout.textContent = value.toFixed(2);
        };

        // One update per frame while the slider moves: more would be wasted work,
        // fewer would be visible lag.
        if (immediate) {
            cancelAnimationFrame(frame);
            render();
            return;
        }
        if (frame) return;
        frame = requestAnimationFrame(render);
    }

    const worker = new Worker(new URL('../../workers/theme-worker.ts', import.meta.url), { type: 'module' });

    worker.addEventListener('message', (event: MessageEvent<ThemeResponse>) => {
        const data = event.data;
        if ('error' in data) {
            say(`Could not read that image: ${data.error}`);
            return;
        }

        source = data.argb;
        paint(true);
        say('Palette taken from that image. The whole site is wearing it now.');
    });

    function useFile(file: File | undefined): void {
        if (!file) return;
        say('Reading the image…');
        worker.postMessage({ file });
    }

    input?.addEventListener('change', () => useFile(input.files?.[0]));

    if (drop) {
        // Highlight on pointer-down rather than on drop, so the target reacts
        // the moment it is aimed at.
        const activate = () => (drop.dataset.active = '');
        const deactivate = () => delete drop.dataset.active;

        for (const type of ['dragenter', 'dragover'] as const) {
            drop.addEventListener(type, (event) => {
                event.preventDefault();
                activate();
            });
        }
        for (const type of ['dragleave', 'drop'] as const) {
            drop.addEventListener(type, () => deactivate());
        }
        drop.addEventListener('drop', (event) => {
            event.preventDefault();
            useFile(event.dataTransfer?.files?.[0]);
        });
    }

    intensity?.addEventListener('input', () => paint(false));

    reset?.addEventListener('click', () => {
        if (properties) clearTheme(document.documentElement, properties);
        properties = null;
        source = null;
        if (swatch) swatch.style.background = 'transparent';
        say('Back to the palette you picked.');
        document.dispatchEvent(new CustomEvent(PALETTE_EVENT, { detail: getState() }));
    });

    // A wallpaper palette has a light and a dark set, so switching mode has to
    // re-apply rather than re-derive; and choosing a named palette has to put
    // the inline properties away.
    const onPaletteChange = (): void => {
        const state = getState();
        if (!properties) return;
        if (state.palette !== 'dynamic') clearTheme(document.documentElement, properties);
        else applyTheme(document.documentElement, properties, state.mode);
    };
    document.addEventListener(PALETTE_EVENT, onPaletteChange);

    return () => {
        worker.terminate();
        cancelAnimationFrame(frame);
        document.removeEventListener(PALETTE_EVENT, onPaletteChange);
    };
}
