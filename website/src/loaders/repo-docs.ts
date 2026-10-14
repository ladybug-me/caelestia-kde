/**
 * The docs are the repository's own markdown.
 *
 * This loader reads the user-facing documents out of the checkout at build
 * time, slices the README into the pages that belong on the site, and rewrites
 * every link so it points at a site route when there is one and at GitHub when
 * there is not. Nothing is copied into the repository, so an edit to the README
 * cannot leave the site describing last month's install command.
 *
 * The documents it deliberately does not read: `CONTEXT.md`, `CLAUDE.md` and
 * `docs/adr/**` are gitignored, so they are absent from a CI checkout, and
 * `docs/wayfinder/**` is internal design work.
 */

import { readFileSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

import type { Loader, LoaderContext } from 'astro/loaders';

interface Section {
    /** Route id, and the last segment of the page's URL. */
    id: string;
    title: string;
    description: string;
    group: string;
    order: number;
    /** Heading text this page is cut from, for a README section. */
    heading?: string;
    /** Or the whole file, minus its title. */
    file?: string;
}

// The reading order someone installing the shell actually follows.
const SECTIONS: Section[] = [
    {
        id: 'installation',
        title: 'Installation',
        description: 'Requirements, the install one-liner, and what the installer does.',
        group: 'Getting started',
        order: 10,
        heading: 'Installation',
    },
    {
        id: 'updating',
        title: 'Updating',
        description: 'Updating through the installer, Nexus, or the update script.',
        group: 'Getting started',
        order: 20,
        heading: 'Updating',
    },
    {
        id: 'uninstalling',
        title: 'Uninstalling',
        description: 'Removing Caelestia and leaving your KDE session intact.',
        group: 'Getting started',
        order: 30,
        heading: 'Uninstalling',
    },
    {
        id: 'keybinds',
        title: 'Keybinds',
        description: 'Everything bound by default, from the launcher to the colour picker.',
        group: 'Using Caelestia',
        order: 10,
        heading: 'Keybinds',
    },
    {
        id: 'configuring',
        title: 'Configuring',
        description: 'Where the settings live and what each page of Nexus configures.',
        group: 'Using Caelestia',
        order: 20,
        heading: 'Configuring',
    },
    {
        id: 'troubleshooting',
        title: 'Troubleshooting',
        description: 'The failures people hit, and what fixes them.',
        group: 'When something breaks',
        order: 10,
        file: 'docs/TROUBLESHOOTING.md',
    },
    {
        id: 'contributing',
        title: 'Contributing',
        description: 'How to build the shell from a checkout, and what a pull request should look like.',
        group: 'Building on it',
        order: 10,
        file: '.github/CONTRIBUTING.md',
    },
];

/** Routes the site serves, so a markdown link can be pointed at one. */
const ROUTES: Record<string, string> = Object.fromEntries(
    SECTIONS.filter((section) => section.file).map((section) => [`${section.file}`, `/docs/${section.id}`]),
);

const BLOB = 'https://github.com/ladybug-me/caelestia-kde/blob/main';
const RAW = 'https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main';

/** The README sections the site renders, so a section can stop at its siblings. */
const README_HEADINGS = SECTIONS.filter((section) => section.heading).map((section) => section.heading as string);

/**
 * Cuts the section that starts at `heading` out of a document.
 *
 * The section ends at the next heading of the same or a shallower level, or at
 * any heading named in `stopAt`. The second rule is what keeps the README's
 * `## Installation` from swallowing `### Updating` and `### Uninstalling`, which
 * are pages of their own.
 */
export function extractSection(markdown: string, heading: string, stopAt: readonly string[] = []): string | null {
    const lines = markdown.split('\n');
    const wanted = heading.trim().toLowerCase();
    const stops = new Set([wanted, ...stopAt.map((entry) => entry.trim().toLowerCase())]);

    let start = -1;
    let level = 0;

    for (const [index, line] of lines.entries()) {
        const match = /^(#{2,4})\s+(.*?)\s*$/.exec(line);
        if (!match) continue;
        const text = match[2].toLowerCase();

        if (start === -1) {
            if (text !== wanted) continue;
            start = index + 1;
            level = match[1].length;
            continue;
        }

        if (match[1].length <= level || stops.has(text)) return lines.slice(start, index).join('\n').trim();
    }

    return start === -1 ? null : lines.slice(start).join('\n').trim();
}

/** Drops a document's own title, and any HTML preamble above it. */
export function stripTitle(markdown: string): string {
    return markdown
        .replace(/^(.|\n)*?^#\s+.*?$/m, '')
        .replace(/^\s+/, '')
        .trim();
}

/**
 * Points markdown links at the site where the site has a page for them, and at
 * GitHub where it does not. Anchors into `docs/TROUBLESHOOTING.md` keep working
 * because the rendered headings use the same slugger GitHub does.
 */
export function rewriteLinks(markdown: string, base: string): string {
    const prefix = base.endsWith('/') ? base.slice(0, -1) : base;

    return markdown.replace(/\]\(([^)\s]+?)(#[^)\s]*)?\)/g, (whole, target: string, anchor = '') => {
        if (/^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith('#')) return whole;

        const normalised = target.replace(/^\.\//, '');
        const route = ROUTES[normalised];
        if (route) return `](${prefix}${route}${anchor})`;

        if (/\.(png|jpe?g|svg|webp|gif|mp4|webm)$/i.test(normalised)) {
            return `](${RAW}/${normalised})`;
        }
        return `](${BLOB}/${normalised}${anchor})`;
    });
}

function readDocument(root: string, file: string): string {
    try {
        return readFileSync(join(root, file.replace(/^\.\//, '')), 'utf8');
    } catch (error) {
        // A reworded README heading or a moved file has to fail the build: the
        // alternative is a docs page that silently says nothing.
        throw new Error(`repo-docs: cannot read ${file}`, { cause: error });
    }
}

function resolveRoots(context: LoaderContext): { site: string; repo: string } {
    // `new URL(...).pathname` keeps a leading slash that Windows paths do not
    // want, and the drive letter arrives as `/C:/...`. Astro's root is the
    // website directory; the documents live one level up, in the repository.
    const site = decodeURIComponent(new URL(context.config.root).pathname).replace(/^\/([A-Za-z]:)/, '$1');
    return { site, repo: resolve(site, '..') };
}

/**
 * The `filePath` Astro is handed for an entry.
 *
 * Astro wants a path relative to the site root, and it throws on anything
 * starting with `/`, which is every absolute path on Linux and macOS. An
 * absolute path here therefore built on Windows and failed everywhere else —
 * including CI. The documents sit outside the site root, so the honest relative
 * path starts with `..`, and it is written in POSIX form whatever platform the
 * build runs on.
 */
export function sourcePath(site: string, repo: string, file: string): string {
    return relative(site, join(repo, file)).split(sep).join('/');
}

export function repoDocs(): Loader {
    return {
        name: 'repo-docs',
        load: async (context: LoaderContext) => {
            const roots = resolveRoots(context);
            const base = context.config.base ?? '/';
            const readme = readDocument(roots.repo, 'README.md');

            for (const section of SECTIONS) {
                const source = section.file ?? 'README.md';
                const document = section.file ? readDocument(roots.repo, section.file) : readme;
                const body = section.heading
                    ? extractSection(document, section.heading, README_HEADINGS)
                    : stripTitle(document);

                if (!body) {
                    throw new Error(
                        `repo-docs: ${section.id} came out empty. ` +
                            (section.heading
                                ? `README.md has no "## ${section.heading}" section.`
                                : `${section.file} is empty after its title.`),
                    );
                }

                const markdown = rewriteLinks(body, base);
                const filePath = sourcePath(roots.site, roots.repo, source);

                context.store.set({
                    id: section.id,
                    filePath,
                    body: markdown,
                    data: await context.parseData({
                        id: section.id,
                        filePath,
                        data: {
                            title: section.title,
                            description: section.description,
                            group: section.group,
                            order: section.order,
                            source,
                        },
                    }),
                    rendered: await context.renderMarkdown(markdown, { fileURL: new URL(context.config.root) }),
                    digest: context.generateDigest(markdown),
                });
            }
        },
    };
}
