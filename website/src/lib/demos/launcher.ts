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
 */

import { createPager } from '../motion/pager';

export function initLauncherDemo(root: HTMLElement): () => void {
    const input = root.querySelector<HTMLInputElement>('[data-launcher-input]');
    const status = root.querySelector<HTMLElement>('[data-launcher-status]');
    const apps = [...root.querySelectorAll<HTMLElement>('[data-launcher-app]')];
    const empty = root.querySelector<HTMLElement>('[data-launcher-empty]');
    let highlight = -1;

    const visible = (): HTMLElement[] => apps.filter((app) => !app.hidden);

    function filter(): void {
        const query = (input?.value ?? '').trim().toLowerCase();
        let shown = 0;

        for (const app of apps) {
            const haystack = `${app.dataset.launcherApp ?? ''} ${app.textContent ?? ''}`.toLowerCase();
            const matches = query === '' || haystack.includes(query);
            app.hidden = !matches;
            if (matches) shown += 1;
        }

        if (empty) empty.hidden = shown > 0;
        if (status) {
            status.textContent = query === '' ? `${shown} apps` : `${shown} result${shown === 1 ? '' : 's'}`;
        }
        highlight = -1;
        visible().forEach((app) => app.removeAttribute('data-highlighted'));
    }

    function move(delta: number): void {
        const results = visible();
        if (results.length === 0) return;

        if (highlight >= 0) results[highlight]?.removeAttribute('data-highlighted');
        highlight = (highlight + delta + results.length) % results.length;
        const target = results[highlight];
        target.setAttribute('data-highlighted', '');
        target.focus({ preventScroll: false });
    }

    input?.addEventListener('input', filter);
    input?.addEventListener('keydown', (event) => {
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            move(1);
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            move(-1);
        } else if (event.key === 'Escape') {
            input.value = '';
            filter();
        }
    });

    for (const app of apps) {
        app.addEventListener('click', () => {
            if (status) status.textContent = `Launching ${app.dataset.launcherApp ?? app.textContent}`;
        });
    }

    const track = root.querySelector<HTMLElement>('[data-launcher-track]');
    const pages = track ? Number(track.dataset.pages ?? '1') : 1;
    const live = root.querySelector<HTMLElement>('[data-launcher-live]');

    const pager =
        track && pages > 1
            ? createPager({
                  track,
                  handles: [track],
                  pages,
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
