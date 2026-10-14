/**
 * The wallpaper palette, in a worker.
 *
 * The shell's headline behaviour is that colours come from the wallpaper. The
 * site can do the same to an image a visitor drops on the page, and the one
 * constraint that matters is that it must not block the main thread: quantising
 * a photo takes tens of milliseconds at best.
 *
 * The pipeline is the reference one, minus the parts that need an
 * HTMLImageElement:
 *
 *   1. decode the dropped file to an ImageBitmap
 *   2. downscale, which is what makes the quantiser fast and does not change
 *      the answer it gives
 *   3. quantise to a small set of colours (Celebi), score them, and take the
 *      first that is colourful enough and neither near-white nor near-black
 *
 * It posts back a single ARGB colour. Building the scheme from it is cheap and
 * happens on the main thread, where the result is applied.
 */

import { Hct, QuantizerCelebi, Score } from '@material/material-color-utilities';

const SAMPLE_SIZE = 128;
const FALLBACK = 0xff4285f4; // Google blue, the fallback the reference uses.

export interface ThemeRequest {
    file: Blob;
}

export type ThemeResponse = { argb: number } | { error: string };

/**
 * The image's representative colour: the top scoring quantised colour that is
 * actually usable as a source (colourful, and neither washed out nor black).
 */
export function sourceColorFrom(pixels: Int32Array): number {
    const ranked = Score.score(QuantizerCelebi.quantize(Array.from(pixels), 128));
    if (ranked.length === 0) return FALLBACK;

    const usable = ranked.filter((argb) => {
        const hct = Hct.fromInt(argb);
        return hct.chroma >= 5 && hct.tone > 20 && hct.tone < 80;
    });

    return usable.length > 0 ? usable[0] : ranked[0];
}

self.addEventListener('message', async (event: MessageEvent<ThemeRequest>) => {
    const reply = (message: ThemeResponse): void => {
        (self as unknown as Worker).postMessage(message);
    };

    try {
        const bitmap = await createImageBitmap(event.data.file);
        const scale = Math.min(1, SAMPLE_SIZE / Math.max(bitmap.width, bitmap.height));
        const width = Math.max(1, Math.round(bitmap.width * scale));
        const height = Math.max(1, Math.round(bitmap.height * scale));

        const canvas = new OffscreenCanvas(width, height);
        const context = canvas.getContext('2d');
        if (!context) throw new Error('The browser gave no 2D context for the image.');

        context.drawImage(bitmap, 0, 0, width, height);
        bitmap.close();

        const { data } = context.getImageData(0, 0, width, height);
        // Quantisers take ARGB ints; the canvas gives RGBA bytes.
        const pixels = new Int32Array(data.length / 4);
        for (let index = 0; index < pixels.length; index += 1) {
            const offset = index * 4;
            pixels[index] = (255 << 24) | (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
        }

        reply({ argb: sourceColorFrom(pixels) });
    } catch (error) {
        reply({ error: error instanceof Error ? error.message : 'The image could not be read.' });
    }
});
