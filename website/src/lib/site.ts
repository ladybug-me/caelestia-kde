/**
 * Site-wide constants and the one place internal links are built.
 *
 * Every URL a visitor can see has to carry the GitHub Pages base path, and
 * hardcoding it in components is how a site breaks the day it moves to a custom
 * domain. `url()` is the only thing that knows about the base.
 */

// Trailing slash included, which is why `url()` trims it.
const base = import.meta.env.BASE_URL;

/** An internal path (leading slash) as a URL the browser can use. */
export function url(path = '/'): string {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('#')) return path;
    const trimmed = base.endsWith('/') ? base.slice(0, -1) : base;
    if (path === '/') return trimmed.length > 0 ? `${trimmed}/` : '/';
    return `${trimmed}${path.startsWith('/') ? path : `/${path}`}`;
}

/** True when the current page is `path` or below it, for nav highlighting. */
export function isCurrent(current: string, path: string): boolean {
    if (path === '/') return current === '/' || current === '';
    return current === path || current.startsWith(`${path}/`);
}

export const SITE = {
    title: 'Caelestia',
    tagline: 'A desktop shell for KDE Plasma',
    description:
        'Caelestia is a Quickshell desktop shell for KDE Plasma 6 on Wayland: a bar, launcher, ' +
        'notification centre, overview and settings app, all themed from your wallpaper.',
    repo: 'https://github.com/ladybug-me/caelestia-kde',
    issues: 'https://github.com/ladybug-me/caelestia-kde/issues',
    discussions: 'https://github.com/ladybug-me/caelestia-kde/discussions',
    upstream: 'https://github.com/caelestia-dots/shell',
    upstreamDots: 'https://github.com/caelestia-dots/caelestia',
    licence: 'GPL-3.0-or-later',
    install: 'curl -fsSL https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/install.sh | sh',
} as const;

export const NAV = [
    { href: '/features', label: 'Features' },
    { href: '/gallery', label: 'Gallery' },
    { href: '/themes', label: 'Themes' },
    { href: '/docs', label: 'Docs' },
] as const;
