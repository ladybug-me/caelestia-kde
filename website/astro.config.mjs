// @ts-check
import { defineConfig, fontProviders } from 'astro/config';

// The site is published as a GitHub Pages project page, so every internal URL
// carries a base path. Moving to a custom domain is a change to this one value
// plus a CNAME file.
export const SITE_ORIGIN = 'https://ladybug-me.github.io';
export const BASE_PATH = '/caelestia-kde';

export default defineConfig({
    site: `${SITE_ORIGIN}${BASE_PATH}`,
    base: BASE_PATH,
    trailingSlash: 'ignore',
    build: {
        format: 'directory',
        // The pages are mostly static markup; inlining the small sheets saves a
        // round trip without blocking first paint with a large one.
        inlineStylesheets: 'auto',
    },
    markdown: {
        // Code blocks are painted from the active palette's own terminal
        // colours: Shiki emits var(--astro-code-token-*) and
        // src/styles/generated/palettes.css defines them per palette.
        shikiConfig: { theme: 'css-variables', wrap: false },
    },
    fonts: [
        {
            // The face the shell renders in, subset at build time by
            // scripts/sync-assets.mjs. OFL 1.1, so it may be redistributed with
            // its notice, which is staged alongside it.
            name: 'Google Sans Flex',
            cssVariable: '--font-sans',
            provider: fontProviders.local(),
            display: 'swap',
            // Metric-matched fallbacks, so the swap does not shift layout.
            optimizedFallbacks: true,
            fallbacks: ['system-ui', 'sans-serif'],
            options: {
                variants: [
                    {
                        src: ['./src/assets/fonts/googlesansflex-subset.woff2'],
                        weight: '300 800',
                        style: 'normal',
                    },
                ],
            },
        },
    ],
});
