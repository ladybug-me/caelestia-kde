import { getCollection } from 'astro:content';

import { url } from '../lib/site';

/**
 * The sitemap, generated rather than added as a dependency: the site is small
 * enough that listing its routes is cheaper than integrating a plugin.
 *
 * Everything here is static and prerendered, so the list is the routes plus the
 * docs collection.
 */
export async function GET({ site }: { site: URL | undefined }): Promise<Response> {
    const entries = await getCollection('docs');

    const routes = ['/', '/features', '/gallery', '/themes', '/docs', ...entries.map((entry) => `/docs/${entry.id}`)];

    const origin = site ?? new URL('https://ladybug-me.github.io/caelestia-kde/');
    const body = `<?xml version="1.0" encoding="utf-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${routes.map((route) => `    <url><loc>${new URL(url(route), origin).href}</loc></url>`).join('\n')}
</urlset>
`;

    return new Response(body, {
        headers: { 'Content-Type': 'application/xml; charset=utf-8' },
    });
}
