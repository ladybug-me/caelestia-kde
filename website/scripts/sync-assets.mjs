// Stages the two kinds of binary the site renders from the repository:
//
//   src/assets/repo/**    the logo and the screenshots, copied from the
//                         repository's own `assets/` so there is one original
//   src/assets/fonts/**   Google Sans Flex, subset for the web
//
// Both destinations are generated at build time and are not committed, which
// keeps the repository free of binaries and keeps the font out of git, matching
// the decision in docs/wayfinder/upstream-layout/tickets/T10-fonts-out-of-repo.md.

import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import subsetFont from 'subset-font';

const here = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(here, '..');
const repoRoot = resolve(websiteRoot, '..');

const assetOut = join(websiteRoot, 'src', 'assets', 'repo');
const fontOut = join(websiteRoot, 'src', 'assets', 'fonts');

// Screenshots the docs and the landing page use.
const ASSETS = ['logo.svg', 'shell-screenshot.png', 'lockscreen-screenshot.png'];

// The shell loads Google Sans Flex from here. The upstream layout promotion
// moves it to the repository root, so both locations are accepted.
const FONT_DIRS = [join(repoRoot, 'shell', 'assets', 'google-sans-flex'), join(repoRoot, 'assets', 'google-sans-flex')];

// Characters the subset must carry beyond what the source scan finds: the
// printable ASCII range, the Latin-1 supplement, and the punctuation and
// symbols the site's own copy and UI lean on.
function baseCharacters() {
    let text = '';
    for (let code = 0x20; code <= 0x7e; code += 1) text += String.fromCharCode(code);
    for (let code = 0xa0; code <= 0xff; code += 1) text += String.fromCharCode(code);
    text += '‘’“”–—…•·°±×÷≈≠≤≥→←↑↓↔✓✗⚠⏎⌘⏱▁▂▃▄▅▆▇█◐◑⌥⇧§¶†‡€£¥©®™';
    return text;
}

const SOURCE_EXTENSIONS = new Set(['.astro', '.ts', '.mjs', '.js', '.json', '.md', '.css', '.html']);

function collectCharacters(dir, seen = new Set(), text = '') {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === 'node_modules' || entry.name === 'generated' || entry.name.startsWith('.')) continue;
        const path = join(dir, entry.name);
        if (entry.isDirectory()) {
            text = collectCharacters(path, seen, text);
            continue;
        }
        if (!SOURCE_EXTENSIONS.has(entry.name.slice(entry.name.lastIndexOf('.')))) continue;
        if (seen.has(path)) continue;
        seen.add(path);
        text += readFileSync(path, 'utf8');
    }
    return text;
}

function stageAssets() {
    mkdirSync(assetOut, { recursive: true });
    mkdirSync(join(websiteRoot, 'public'), { recursive: true });
    const staged = [];

    for (const name of ASSETS) {
        const from = join(repoRoot, 'assets', name);
        if (!existsSync(from)) {
            throw new Error(`Missing ${from}. The repository's assets/ directory is where these come from.`);
        }
        copyFileSync(from, join(assetOut, name));
        staged.push(name);
    }

    // The project's own mark is the tab icon; there is no second logo to keep
    // in step.
    copyFileSync(join(repoRoot, 'assets', 'logo.svg'), join(websiteRoot, 'public', 'favicon.svg'));

    return staged;
}

function findFont() {
    for (const dir of FONT_DIRS) {
        if (!existsSync(dir)) continue;
        const font = readdirSync(dir).find((name) => name.endsWith('.ttf') && name.startsWith('GoogleSansFlex'));
        if (font) return { dir, file: join(dir, font) };
    }
    throw new Error(
        `Google Sans Flex is not in the tree (looked in ${FONT_DIRS.join(', ')}). ` +
            'It is the face the shell renders in; the site cannot be built without it.',
    );
}

async function stageFont() {
    const { dir, file } = findFont();

    // Scraped from the site's own sources, so copy added later is covered
    // without touching this script. Characters outside the subset fall back to
    // the next family in the stack.
    const characters = `${baseCharacters()}${collectCharacters(join(websiteRoot, 'src'))}`;

    const subset = await subsetFont(readFileSync(file), characters, {
        targetFormat: 'woff2',
        // Pin the axes the site does not use, keep weight and optical size.
        variationAxes: {
            GRAD: 0,
            ROND: 0,
            slnt: 0,
            wdth: 100,
            opsz: { min: 12, max: 48 },
            wght: { min: 300, max: 800 },
        },
    });

    mkdirSync(fontOut, { recursive: true });
    writeFileSync(join(fontOut, 'googlesansflex-subset.woff2'), subset);

    // OFL 1.1 requires the copyright notice to travel with the font software.
    const licence = join(dir, 'LICENSE');
    if (existsSync(licence)) copyFileSync(licence, join(fontOut, 'GoogleSansFlex-LICENSE.txt'));

    return {
        source: basename(file),
        uniqueCharacters: new Set(characters).size,
        bytes: subset.byteLength,
    };
}

const stagedAssets = stageAssets();
const font = await stageFont();

console.log(`assets: ${stagedAssets.length} files staged from assets/ ` + `(${stagedAssets.join(', ')})`);
console.log(
    `assets: ${font.source} subset to ${font.uniqueCharacters} characters -> ` +
        `googlesansflex-subset.woff2 (${(font.bytes / 1024).toFixed(0)} KB)`,
);
