/**
 * The launcher.
 *
 * Two behaviours, both of them from the shell:
 *
 *   - **Search answers on the keystroke.** The shell's own settings search waits
 *     for a pause in typing because it filters a large tree; a launcher filters a
 *     handful of apps, so waiting would be pure added latency. There is no
 *     debounce here, and no animation on the results: they appear.
 *   - **Pages carry.** The grid is paged, so it behaves like a physical surface:
 *     a flick projects where the gesture was going and snaps to the page nearest
 *     that point, and the ends resist instead of fighting back.
 *   - **The arrows move a highlight, not the focus.** Focus stays in the field,
 *     so the arrow keys keep working and typing keeps filtering; the page turns
 *     when the highlighted app is on the other one.
 */

import { createPager } from '../motion/pager';

export function initLauncherDemo(root: HTMLElement): () => void {
    const input = root.querySelector<HTMLInputElement>('[data-launcher-input]');
    const status = root.querySelector<HTMLElement>('[data-launcher-status]');
    const apps = [...root.querySelectorAll<HTMLElement>('[data-launcher-app]')];
    const empty = root.querySelector<HTMLElement>('[data-launcher-empty]');
    const live = root.querySelector<HTMLElement>('[data-launcher-live]');
    const pages = [...root.querySelectorAll<HTMLElement>('.launcher__page')];
    let highlight = -1;

    const visible = (): HTMLElement[] => apps.filter((app) => !app.hidden);

    const label = (app: HTMLElement): string => app.dataset.launcherApp ?? 'app';

    function filter(): void {
        const query = (input?.value ?? '').trim().toLowerCase();
        let shown = 0;

        for (const app of apps) {
            const haystack = `${app.dataset.launcherApp ?? ''} ${app.textContent ?? ''}`.toLowerCase();
            const matches = query === '' || haystack.includes(query);
            app.hidden = !matches;
            if (matches) shown += 1;
        }

        if (empty) {
            empty.hidden = shown > 0;
            if (shown === 0) empty.textContent = `No apps match “${query}”. Clear the field to see all ${apps.length}.`;
        }
        if (status) {
            status.textContent = query === '' ? `${shown} apps` : shown === 1 ? '1 result' : `${shown} results`;
        }
        highlight = -1;
        // Every one of them, not just the visible ones: an app that comes back
        // when the query is cleared must not arrive still wearing the highlight.
        apps.forEach((app) => app.removeAttribute('data-highlighted'));

        // Results live on the first page, so a filter that changed them while the
        // grid sat on the second one would hide every match.
        if (pager && pager.index !== 0) pager.goTo(0);
    }

    /**
     * Moves the highlight, not the focus.
     *
     * Focus stays in the field: moving it onto the result would end the gesture,
     * because the next arrow key would land on that button and any further typing
     * would go nowhere. The live region is what announces the highlight, and the
     * page changes if the result is not on the one in view.
     */
    function move(delta: number): void {
        const results = visible();
        if (results.length === 0) return;

        if (highlight >= 0) results[highlight]?.removeAttribute('data-highlighted');
        highlight = (highlight + delta + results.length) % results.length;
        const target = results[highlight];
        target.setAttribute('data-highlighted', '');

        const page = pages.indexOf(target.closest<HTMLElement>('.launcher__page') ?? target);
        if (page > 0) pager?.goTo(page);

        if (live) live.textContent = `${label(target)}, ${highlight + 1} of ${results.length}`;
    }

    input?.addEventListener('input', filter);
    input?.addEventListener('keydown', (event) => {
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            move(1);
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            move(-1);
        } else if (event.key === 'Enter') {
            const target = visible()[highlight];
            if (!target) return;
            event.preventDefault();
            target.click();
        } else if (event.key === 'Escape') {
            input.value = '';
            filter();
        }
    });

    for (const app of apps) {
        app.addEventListener('click', () => {
            if (status) status.textContent = `Launching ${label(app)}`;
        });
    }

    const track = root.querySelector<HTMLElement>('[data-launcher-track]');
    const pageCount = track ? Number(track.dataset.pages ?? '1') : 1;

    const pager =
        track && pageCount > 1
            ? createPager({
                  track,
                  handles: [track],
                  pages: pageCount,
                  pageWidth: () => track.parentElement?.clientWidth ?? track.clientWidth,
                  liveRegion: live ?? undefined,
                  label: 'apps page',
              })
            : null;

    const pagerButtons = [...root.querySelectorAll<HTMLButtonElement>('[data-launcher-page]')];
    for (const button of pagerButtons) {
        button.addEventListener('click', () => pager?.goTo(Number(button.dataset.launcherPage ?? '0')));
    }

    filter();

    return () => pager?.destroy();
}
