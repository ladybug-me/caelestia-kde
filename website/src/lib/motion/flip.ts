/**
 * FLIP: animate a layout change instead of cutting to it.
 *
 * When something is removed from a stack, everything below it moves. Doing that
 * with a fresh render is a jump; measuring the positions before and after and
 * animating the difference keeps the movement continuous, and running it on a
 * spring is what makes the stack close rather than snap.
 *
 * The transform is written directly rather than through a stylesheet, so an
 * interrupted re-layout starts from wherever the element had got to.
 */

import { springTo } from './animate';
import type { SpringName } from './spring';

export interface FlipOptions {
    spring?: SpringName;
    /** Called once every element has settled. */
    onSettle?: () => void;
}

/**
 * Runs `mutate`, then animates everything that moved in `container` from where
 * it was to where it now is.
 */
export function flip(container: Element, mutate: () => void, { spring = 'settle', onSettle }: FlipOptions = {}): void {
    const targets = [...container.querySelectorAll<HTMLElement>('[data-flip]')];

    const before = new Map<HTMLElement, DOMRect>();
    for (const target of targets) before.set(target, target.getBoundingClientRect());

    mutate();

    let pending = 0;
    for (const target of targets) {
        if (!target.isConnected) continue;
        const was = before.get(target);
        if (!was) continue;

        const now = target.getBoundingClientRect();
        const dx = was.left - now.left;
        const dy = was.top - now.top;
        if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) continue;

        // Start from where it used to be, with no transition, then let the
        // spring carry it home.
        target.style.transform = `translate(${dx}px, ${dy}px)`;
        pending += 1;
        springTo(target, { x: 0, y: 0 }, { spring, onSettle: pending === 1 ? onSettle : undefined });
    }

    if (pending === 0) onSettle?.();
}
