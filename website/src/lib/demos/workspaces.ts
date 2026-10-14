/**
 * The workspace strip.
 *
 * The same pager as the launcher, on the surface where momentum is most
 * visible: five workspaces, a flick that projects where it was going, and
 * resistance at either end. Window cards on a workspace fade as the strip moves
 * away from them, which is what keeps the strip reading as depth rather than as
 * a list scrolling sideways.
 */

import { createPager } from '../motion/pager';

export function initWorkspacesDemo(root: HTMLElement): () => void {
    const track = root.querySelector<HTMLElement>('[data-workspace-track]');
    const live = root.querySelector<HTMLElement>('[data-workspace-live]');
    const workspaces = [...root.querySelectorAll<HTMLElement>('[data-workspace]')];
    if (!track || workspaces.length === 0) return () => {};

    const viewport = track.parentElement ?? track;
    const buttons = [...root.querySelectorAll<HTMLButtonElement>('[data-workspace-jump]')];

    /** The strip and the dots say the same thing, so they move together. */
    const mark = (index: number): void => {
        for (const [position, workspace] of workspaces.entries()) {
            workspace.dataset.active = String(position === index);
        }
        for (const [position, button] of buttons.entries()) {
            button.setAttribute('aria-current', String(position === index));
        }
    };

    const pager = createPager({
        track,
        handles: [track],
        pages: workspaces.length,
        pageWidth: () => viewport.clientWidth,
        liveRegion: live ?? undefined,
        label: 'workspace',
        onChange: mark,
    });

    // The markup ships the first workspace as current; this makes the state come
    // from the strip rather than from the template, so the two cannot drift.
    mark(0);

    for (const button of buttons) {
        button.addEventListener('click', () => pager.goTo(Number(button.dataset.workspaceJump ?? '0')));
    }

    // Reduced motion: the strip still moves, it just arrives immediately.
    root.dataset.pages = String(workspaces.length);

    return () => pager.destroy();
}
