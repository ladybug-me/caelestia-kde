import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import astro from 'eslint-plugin-astro';
import tseslint from 'typescript-eslint';

export default defineConfig(
    {
        ignores: [
            'dist/**',
            '.astro/**',
            'node_modules/**',
            'src/styles/generated/**',
            'src/data/palettes.json',
            'src/assets/**',
            'test-results/**',
            'playwright-report/**',
        ],
    },
    js.configs.recommended,
    ...tseslint.configs.recommended,
    ...astro.configs.recommended,
    {
        // TypeScript knows which identifiers exist; `no-undef` only produces
        // false positives on browser globals in .ts and .astro files.
        files: ['**/*.ts', '**/*.astro'],
        rules: {
            'no-undef': 'off',
        },
    },
    {
        files: ['**/*.mjs', 'scripts/**/*.mjs'],
        languageOptions: {
            globals: {
                process: 'readonly',
                console: 'readonly',
                self: 'readonly',
                // The worker module is loaded by the browser, not by Node.
                Worker: 'readonly',
                OffscreenCanvas: 'readonly',
                createImageBitmap: 'readonly',
            },
        },
    },
    {
        rules: {
            '@typescript-eslint/no-non-null-assertion': 'off',
        },
    },
);
