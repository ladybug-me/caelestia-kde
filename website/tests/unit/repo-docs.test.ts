import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { extractSection, rewriteLinks, stripTitle } from '../../src/loaders/repo-docs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..', '..');

const readme = readFileSync(join(repoRoot, 'README.md'), 'utf8');
const troubleshooting = readFileSync(join(repoRoot, 'docs', 'TROUBLESHOOTING.md'), 'utf8');
const contributing = readFileSync(join(repoRoot, '.github', 'CONTRIBUTING.md'), 'utf8');

describe('extractSection', () => {
    const siblings = ['Installation', 'Updating', 'Uninstalling', 'Keybinds', 'Configuring'];

    it('cuts a README section out, stopping at the sections the site renders separately', () => {
        const installation = extractSection(readme, 'Installation', siblings);
        expect(installation).toBeTruthy();
        expect(installation).toContain('curl -fsSL');
        // `### Updating` is its own page, so Installation must not keep it.
        expect(installation).not.toContain('### Updating');
        expect(installation).not.toContain('### Uninstalling');
    });

    it('cuts a nested section without swallowing its sibling', () => {
        const updating = extractSection(readme, 'Updating', siblings);
        expect(updating).toContain('bash update.sh');
        expect(updating).not.toContain('Uninstalling Caelestia');
    });

    it('takes the whole section when nothing else is named to stop at', () => {
        const installation = extractSection(readme, 'Installation');
        expect(installation).toContain('### Updating');
    });

    it('returns null for a heading that is not there, so the build can fail loudly', () => {
        expect(extractSection(readme, 'Nonexistent section')).toBeNull();
    });

    it('finds sections in the documents the site renders whole', () => {
        const section = extractSection(troubleshooting, '3.4 Colors not applying');
        expect(section).toBeTruthy();
    });
});

describe('stripTitle', () => {
    it('removes the document title and anything above it', () => {
        const body = stripTitle('# Troubleshooting\n\nSome text.\n');
        expect(body).toBe('Some text.');
    });

    it('drops the HTML preamble a README-style header puts before the title', () => {
        const body = stripTitle(
            '<div align="center">\n<img src="assets/logo.svg" />\n</div>\n\n# Caelestia\n\nReal text.\n',
        );
        expect(body).toBe('Real text.');
    });

    it('leaves the rest of the document alone', () => {
        expect(stripTitle('# Title\n\n## Section\n\nBody\n')).toBe('## Section\n\nBody');
    });
});

describe('rewriteLinks', () => {
    const base = '/caelestia-kde';

    it('points a document the site renders at its own route', () => {
        expect(rewriteLinks('See [Troubleshooting](docs/TROUBLESHOOTING.md).', base)).toBe(
            'See [Troubleshooting](/caelestia-kde/docs/troubleshooting).',
        );
    });

    it('keeps the anchor, which is how the README links into the troubleshooting file', () => {
        expect(rewriteLinks('See [it](docs/TROUBLESHOOTING.md#34-colors-not-applying).', base)).toBe(
            'See [it](/caelestia-kde/docs/troubleshooting#34-colors-not-applying).',
        );
    });

    it('sends everything else to the repository rather than to a page that does not exist', () => {
        expect(rewriteLinks('[the installer](install.sh)', base)).toBe(
            '[the installer](https://github.com/ladybug-me/caelestia-kde/blob/main/install.sh)',
        );
        expect(rewriteLinks('![shot](assets/shell-screenshot.png)', base)).toBe(
            '![shot](https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/assets/shell-screenshot.png)',
        );
    });

    it('leaves absolute URLs and in-page anchors alone', () => {
        expect(rewriteLinks('[x](https://example.com/a.md)', base)).toBe('[x](https://example.com/a.md)');
        expect(rewriteLinks('[x](#a-heading)', base)).toBe('[x](#a-heading)');
        expect(rewriteLinks('[x](mailto:someone@example.com)', base)).toBe('[x](mailto:someone@example.com)');
    });

    it('rewrites every link inside a README section, not just the first', () => {
        const rewritten = rewriteLinks(readme, base);
        expect(rewritten).not.toMatch(/\]\(docs\/TROUBLESHOOTING\.md/);
        expect(rewritten).toContain('/caelestia-kde/docs/troubleshooting');
    });
});

describe('the sources the site renders', () => {
    it('are all present in the checkout', () => {
        expect(readme.length).toBeGreaterThan(1000);
        expect(troubleshooting.length).toBeGreaterThan(1000);
        expect(contributing.length).toBeGreaterThan(1000);
    });

    it('no longer describe the site-only concerns the loader handles', () => {
        // A guard against the loader's manifest drifting from the files: every
        // section it asks for has to be in the document it takes it from.
        for (const heading of ['Installation', 'Updating', 'Uninstalling', 'Keybinds', 'Configuring']) {
            expect(extractSection(readme, heading), `${heading} is missing from README.md`).toBeTruthy();
        }
    });
});
