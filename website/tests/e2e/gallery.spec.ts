import { expect, test } from '@playwright/test';

/**
 * The gallery's gestures, driven with real pointer input.
 *
 * These are the assertions a unit test cannot make: the maths is covered in
 * tests/unit, and what is checked here is that the maths is actually wired to
 * the pointer — that a drag tracks the element 1:1, that a flick commits, and
 * that an interrupted animation does not jump.
 */

/** A considered drag: many small moves with waits, so the release has no speed. */
async function dragSlowly(
    page: import('@playwright/test').Page,
    from: { x: number; y: number },
    to: { x: number; y: number },
    { steps = 12, pause = 16 } = {},
): Promise<void> {
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    for (let step = 1; step <= steps; step += 1) {
        const progress = step / steps;
        await page.mouse.move(from.x + (to.x - from.x) * progress, from.y + (to.y - from.y) * progress);
        await page.waitForTimeout(pause);
    }
}

/**
 * A flick: the moves are dispatched back to back, which is what a throw looks
 * like to the page — a short burst of movement ending in a release.
 */
async function flick(
    page: import('@playwright/test').Page,
    from: { x: number; y: number },
    to: { x: number; y: number },
    { steps = 4 } = {},
): Promise<void> {
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    await page.mouse.move(to.x, to.y, { steps });
}

/**
 * A locator's box, once it is on screen.
 *
 * `mouse.move` works in viewport coordinates, so grabbing something below the
 * fold needs the page scrolled to it first — otherwise the pointer lands on the
 * document and the gesture never starts.
 */
async function boxOf(locator: import('@playwright/test').Locator) {
    await locator.scrollIntoViewIfNeeded();
    const box = await locator.boundingBox();
    if (!box) throw new Error('element has no box');
    return box;
}

/** The X translation of a computed transform: m41, not the matrix's first number. */
function translateX(transform: string): number {
    const values = transform.match(/-?\d*\.?\d+/g)?.map(Number) ?? [];
    return values.length >= 6 ? values[4] : 0;
}

test.describe('bar popouts', () => {
    test('opens from the bar element that was pressed', async ({ page }) => {
        await page.goto('gallery');

        const trigger = page.locator("[data-popout='audio']");
        await trigger.click();

        const panel = page.locator("[data-popout-panel='audio']");
        await expect(panel).toBeVisible();

        // Spatial consistency: the surface grows out of its trigger, so its
        // transform origin sits over that trigger rather than at its centre.
        const origin = await panel.evaluate((element) => getComputedStyle(element).transformOrigin);
        // Chromium reports the used value: two lengths, in px, relative to the
        // panel's own box.
        const [originX, originY] = origin.split(' ').map(Number.parseFloat);
        const box = await boxOf(panel);
        const triggerBox = await trigger.boundingBox();

        const triggerCentreX = triggerBox!.x + triggerBox!.width / 2;
        const triggerCentreY = triggerBox!.y + triggerBox!.height / 2;
        expect(Math.abs(box!.x + originX - triggerCentreX)).toBeLessThan(24);
        expect(Math.abs(box!.y + originY - triggerCentreY)).toBeLessThan(24);
    });

    test('tracks the pointer 1:1 while dragged down', async ({ page }) => {
        await page.goto('gallery');
        await page.locator("[data-popout='audio']").click();

        const panel = page.locator("[data-popout-panel='audio']");
        await expect(panel).toBeVisible();
        const box = await boxOf(panel);
        const start = { x: box.x + box.width / 2, y: box.y + 20 };
        const before = await panel.evaluate((element) => element.getBoundingClientRect().top);

        await page.mouse.move(start.x, start.y);
        await page.mouse.down();
        await page.mouse.move(start.x, start.y + 40, { steps: 8 });
        const after = await panel.evaluate((element) => element.getBoundingClientRect().top);

        // 1:1 with the pointer, within a pixel: the element keeps the distance it
        // had when it was grabbed, and follows from there.
        expect(Math.abs(after - before - 40)).toBeLessThan(2);

        await page.mouse.up();
    });

    test('closes when thrown, and stays open when let go early', async ({ page }) => {
        await page.goto('gallery');
        const panel = page.locator("[data-popout-panel='audio']");

        await page.locator("[data-popout='audio']").click();
        await expect(panel).toBeVisible();
        let box = await boxOf(panel);

        // A slow, short drag: not a dismissal, so it springs back and stays.
        await dragSlowly(page, { x: box.x + 40, y: box.y + 20 }, { x: box.x + 40, y: box.y + 60 }, { steps: 8 });
        await page.mouse.up();
        await page.waitForTimeout(500);
        await expect(panel).toBeVisible();

        // A flick: the throw decides, and the surface leaves.
        box = await boxOf(panel);
        await flick(page, { x: box.x + 40, y: box.y + 20 }, { x: box.x + 40, y: box.y + 200 });
        await page.mouse.up();
        await expect(panel).toBeHidden();
    });
});

test.describe('notification stack', () => {
    test('brings a card back when it is released slowly', async ({ page }) => {
        await page.goto('gallery');
        const card = page.locator('[data-notif]').first();
        const box = await boxOf(card);

        await dragSlowly(
            page,
            { x: box.x + box.width / 2, y: box.y + 20 },
            { x: box.x + box.width / 2 + 60, y: box.y + 22 },
            { steps: 6 },
        );
        await page.mouse.up();

        await expect(card).toBeVisible();
        await page.waitForTimeout(600);
        // Back where it started.
        const after = await card.boundingBox();
        if (!after) throw new Error('the card left the page');
        expect(Math.abs(after.x - box.x)).toBeLessThan(3);
    });

    test('throws a card away when it is flicked', async ({ page }) => {
        await page.goto('gallery');
        const stack = page.locator('[data-notif-stack]');
        const card = stack.locator('[data-notif]').first();
        const app = await card.getAttribute('data-app');
        const box = await boxOf(card);

        await flick(
            page,
            { x: box.x + box.width / 2, y: box.y + 20 },
            { x: box.x + box.width / 2 + 140, y: box.y + 20 },
        );
        await page.mouse.up();

        // That card, not the count: the stack refills itself so the demo stays
        // demonstrable, and a count would race the replacement.
        await expect(stack.locator(`[data-notif][data-app='${app}']`)).toHaveCount(0);
    });

    test('stops the timeout while the pointer is over a card', async ({ page }) => {
        await page.goto('gallery');
        const card = page.locator('[data-notif]').first();
        const progress = card.locator('[data-notif-progress]');

        await card.hover();
        await expect(progress).toHaveCSS('animation-play-state', 'paused');

        await page.locator('h1').hover();
        await expect(progress).toHaveCSS('animation-play-state', 'running');
    });
});

test.describe('launcher', () => {
    test('filters on the keystroke, with no debounce', async ({ page }) => {
        await page.goto('gallery');
        const input = page.locator('[data-launcher-input]');
        await input.click();
        await input.pressSequentially('kon', { delay: 10 });

        // Immediately: no waiting for a pause in typing.
        await expect(page.locator('[data-launcher-app]:visible')).toHaveCount(1);

        await input.fill('');
        await expect(page.locator('[data-launcher-app]:visible')).toHaveCount(12);
    });

    test('moves through the results with the arrow keys', async ({ page }) => {
        await page.goto('gallery');
        const input = page.locator('[data-launcher-input]');
        await input.click();
        await input.pressSequentially('a', { delay: 5 });
        await input.press('ArrowDown');
        await expect(page.locator('[data-launcher-app][data-highlighted]')).toHaveCount(1);
    });

    test('carries a flick to the next page', async ({ page }) => {
        await page.goto('gallery');
        const track = page.locator('[data-launcher-track]');
        // The track is wider than the window it moves inside, so the gesture has
        // to start from the window's box, not the track's.
        const box = await boxOf(page.locator('[data-launcher-viewport]'));
        const before = await track.evaluate((element) => getComputedStyle(element).transform);

        await flick(
            page,
            { x: box.x + box.width * 0.6, y: box.y + 40 },
            { x: box.x + box.width * 0.3, y: box.y + 40 },
            { steps: 6 },
        );
        await page.mouse.up();
        await page.waitForTimeout(700);

        const after = await track.evaluate((element) => getComputedStyle(element).transform);
        expect(after).not.toBe(before);
        // A leftward flick lands on the second page: one window to the left. The
        // translation is m41, not the matrix's first number.
        expect(translateX(after)).toBeLessThan(-100);
    });

    test('steps the workspace strip from the keyboard', async ({ page }) => {
        await page.goto('gallery');
        const track = page.locator('[data-workspace-track]');
        await boxOf(track);
        await track.focus();
        await track.press('ArrowRight');
        await page.waitForTimeout(700);

        const translate = await track.evaluate((element) => getComputedStyle(element).transform);
        expect(translate).not.toBe('none');
        expect(translateX(translate)).toBeLessThan(-100);
    });
});

test.describe('interruption', () => {
    test('does not jump when a surface is caught mid-flight', async ({ page }) => {
        await page.goto('gallery');
        const panel = page.locator("[data-popout-panel='audio']");
        await page.locator("[data-popout='audio']").click();

        // Grab it while it is still arriving.
        const box = await boxOf(panel);
        const grab = { x: box.x + box.width / 2, y: box.y + 20 };
        await page.mouse.move(grab.x, grab.y);
        await page.mouse.down();

        const sampled: number[] = [];
        for (let step = 0; step < 6; step += 1) {
            await page.mouse.move(grab.x, grab.y + step * 3);
            await page.waitForTimeout(20);
            sampled.push(
                await panel.evaluate((element) => new DOMMatrixReadOnly(getComputedStyle(element).transform).m42),
            );
        }

        await page.mouse.up();

        // Continuity: no step may jump. A re-target from the logical value
        // instead of the presented one shows up here as a large single step.
        for (let index = 1; index < sampled.length; index += 1) {
            expect(Math.abs(sampled[index] - sampled[index - 1])).toBeLessThan(20);
        }
    });
});

test.describe('reduced motion', () => {
    test.use({ reducedMotion: 'reduce' });

    test('arrives without travelling', async ({ page }) => {
        await page.goto('gallery');
        await page.locator("[data-popout='network']").click();

        // The surface is there, and it is there immediately.
        await expect(page.locator("[data-popout-panel='network']")).toBeVisible();
        const translate = await page
            .locator("[data-popout-panel='network']")
            .evaluate((element) => new DOMMatrixReadOnly(getComputedStyle(element).transform).m42);
        expect(Math.abs(translate)).toBeLessThan(1);
    });

    test('a slow drag still closes a notification, by distance', async ({ page }) => {
        await page.goto('gallery');
        const stack = page.locator('[data-notif-stack]');
        const before = await stack.locator('[data-notif]').count();
        const box = await boxOf(stack.locator('[data-notif]').first());

        await dragSlowly(
            page,
            { x: box.x + 40, y: box.y + 20 },
            { x: box.x + box.width, y: box.y + 20 },
            { steps: 10 },
        );
        await page.mouse.up();
        await expect(stack.locator('[data-notif]')).toHaveCount(before - 1);
    });
});
