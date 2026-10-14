import { defineConfig } from 'vitest/config';

/**
 * Unit tests cover the arithmetic that decides how a gesture behaves: the
 * spring mapping, momentum projection, rubber-banding, the release decision, the
 * palette parser and the docs loader. Anything that needs a browser — whether a
 * drag actually tracks the pointer, whether an element really moves — belongs in
 * the Playwright suite instead (tests/e2e).
 */
export default defineConfig({
    test: {
        include: ['tests/unit/**/*.test.ts', 'tests/unit/**/*.test.mjs'],
        environment: 'node',
        reporters: ['default'],
        server: {
            deps: {
                // The Material colour utilities import their own files without
                // extensions, which Node's ESM loader refuses. Inlining makes
                // Vite resolve them instead.
                inline: ['@material/material-color-utilities'],
            },
        },
    },
});
