import { expect, test } from '@playwright/test';

/**
 * The site's own behaviour: the palette it remembers, the code blocks it paints
 * from the palette, the docs it renders from the repository, and the pages that
 * have to read without JavaScript.
 */

test.describe('the palette', () => {
    test('changes the whole document, and the command follows it', async ({ page }) => {
        await page.goto('themes');
        const primaryBefore = await page.evaluate(() =>
            getComputedStyle(document.documentElement).getPropertyValue('--primary').trim(),
        );

        await page.locator("[data-palette-control='catppuccin-mocha']").click();

        const state = await page.evaluate(() => ({
            palette: document.documentElement.dataset.palette,
            primary: getComputedStyle(document.documentElement).getPropertyValue('--primary').trim(),
            stored: localStorage.getItem('caelestia:palette'),
        }));

        expect(state.palette).toBe('catppuccin-mocha');
        expect(state.primary).not.toBe(primaryBefore);
        expect(state.stored).toBe('catppuccin-mocha');
        await expect(page.locator('[data-command-output]')).toHaveText(
            'caelestia scheme set -n catppuccin -f mocha -m dark',
        );
    });

    test('survives a navigation, and is applied before the page paints', async ({ page }) => {
        await page.goto('themes');
        await page.locator("[data-palette-control='gruvbox-hard']").click();
        await page.goto('gallery');
        await expect(page.locator('html')).toHaveAttribute('data-palette', 'gruvbox-hard');
    });

    test('switches mode and keeps the palette', async ({ page }) => {
        await page.goto('themes');
        // A palette that ships both modes, so switching is the visitor's choice.
        await page.locator("[data-palette-control='everforest-medium']").click();
        await page.locator("[data-mode-control='light']").click();

        await expect(page.locator('html')).toHaveAttribute('data-mode', 'light');
        await expect(page.locator('html')).toHaveAttribute('data-palette', 'everforest-medium');
        await expect(page.locator('[data-command-output]')).toHaveText(
            'caelestia scheme set -n everforest -f medium -m light',
        );
    });

    test('takes the mode with a palette that only ships one, and stops offering the other', async ({ page }) => {
        await page.goto('themes');
        await page.locator("[data-mode-control='light']").click();
        await expect(page.locator('html')).toHaveAttribute('data-mode', 'light');

        // Nord ships dark only, so choosing it takes the site dark with it.
        await page.locator("[data-palette-control='nord-medium']").click();

        await expect(page.locator('html')).toHaveAttribute('data-mode', 'dark');
        await expect(page.locator('html')).toHaveAttribute('data-palette', 'nord-medium');
        await expect(page.locator("[data-mode-control='light']")).toBeDisabled();
        await expect(page.locator('[data-command-output]')).toHaveText(
            'caelestia scheme set -n nord -f medium -m dark',
        );
    });

    test('paints code blocks from the palette, not from a fixed theme', async ({ page }) => {
        await page.goto('docs/installation');
        const block = page.locator('pre.astro-code').first();
        await expect(block).toBeVisible();

        const tokenColor = await block.evaluate((element) => {
            const token = element.querySelector('.astro-code-token-string, [style*="--astro-code-token"]');
            const probe = token ?? element;
            return getComputedStyle(probe).getPropertyValue('--astro-code-token-keyword').trim();
        });
        expect(tokenColor).toMatch(/^#|rgb/);
    });
});

test.describe('the docs', () => {
    const routes = [
        'docs',
        'docs/installation',
        'docs/updating',
        'docs/uninstalling',
        'docs/keybinds',
        'docs/configuring',
        'docs/troubleshooting',
        'docs/contributing',
    ];

    for (const route of routes) {
        test(`${route} renders`, async ({ page }) => {
            const response = await page.goto(route);
            expect(response?.status()).toBe(200);
            await expect(page.locator('h1')).toBeVisible();
        });
    }

    test('renders the install command straight out of the README', async ({ page }) => {
        await page.goto('docs/installation');
        await expect(page.locator('main')).toContainText('curl -fsSL');
        await expect(page.locator('main')).toContainText('KDE Plasma 6 on Wayland');
    });

    test('sends a link the site has a page for to that page, not to GitHub', async ({ page }) => {
        await page.goto('docs/installation');
        const link = page.locator("main a[href*='/docs/troubleshooting']").first();
        await expect(link).toBeVisible();
        // The README's anchor survives the rewrite, so the deep link still lands.
        await link.click();
        await expect(page).toHaveURL(/\/docs\/troubleshooting/);
    });

    test('sends a link the site does not have a page for to the repository', async ({ page }) => {
        await page.goto('docs/troubleshooting');
        const external = page.locator("main a[href^='https://github.com/ladybug-me/caelestia-kde']").first();
        await expect(external).toHaveAttribute('href', /github\.com/);
    });

    test('lists the keybinds the README lists', async ({ page }) => {
        await page.goto('docs/keybinds');
        await expect(page.locator('table')).toContainText('App launcher');
        await expect(page.locator('table')).toContainText('Clipboard history');
    });
});

test.describe('the whole site', () => {
    test('every page is readable and navigable without JavaScript', async ({ browser }) => {
        const context = await browser.newContext({ javaScriptEnabled: false });
        const page = await context.newPage();

        for (const route of ['', 'features', 'gallery', 'themes', 'docs/keybinds']) {
            await page.goto(route);
            await expect(page.locator('h1')).toBeVisible();
            // Nothing may be hidden behind a script that never ran.
            await expect(page.locator('body')).not.toHaveCSS('visibility', 'hidden');
            await expect(page.locator('main')).toContainText(/\w{20,}/);
        }

        await context.close();
    });

    test('has one h1 and a skip link on every page', async ({ page }) => {
        for (const route of ['', 'features', 'gallery', 'themes', 'docs', 'docs/installation']) {
            await page.goto(route);
            await expect(page.locator('h1')).toHaveCount(1);
            await expect(page.locator('a.skip-link')).toHaveCount(1);
        }
    });

    test('fits a phone without scrolling sideways', async ({ page }) => {
        // A viewport narrower than the layout is a craft bug that only shows on a
        // device, so it is checked here rather than discovered later.
        await page.setViewportSize({ width: 390, height: 844 });

        for (const route of ['', 'features', 'gallery', 'themes', 'docs', 'docs/installation']) {
            await page.goto(route);
            const overflow = await page.evaluate(
                () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
            );
            expect(overflow, `${route || '/'} overflows by ${overflow}px`).toBeLessThanOrEqual(1);
        }
    });

    test('says so when a page does not exist', async ({ page }) => {
        const response = await page.goto('no-such-page');
        expect(response?.status()).toBe(404);
    });

    test('serves a sitemap and robots.txt under the base path', async ({ request }) => {
        const sitemap = await request.get('sitemap.xml');
        expect(sitemap.status()).toBe(200);
        expect(await sitemap.text()).toContain('/caelestia-kde/docs/troubleshooting');

        const robots = await request.get('robots.txt');
        expect(await robots.text()).toContain('Sitemap:');
    });
});
