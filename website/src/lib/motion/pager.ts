/**
 * A pager: a horizontal surface that moves 1:1 with a drag and lands on a snap
 * point chosen from where the gesture was *going*, not where it stopped.
 *
 * This is the shared machinery behind the launcher's pages and the workspace
 * strip. Both surfaces are the same problem: a fixed set of stops, a drag that
 * can go past the ends with resistance, and a flick that should carry.
 */

import { draggable, type DragHandle } from './pointer';
import { currentTranslateX, springTo, stopSpring } from './animate';
import { clampWithResistance, project } from './projection';
import { prefersReducedMotion } from './prefers';

export interface PagerOptions {
    /** The element that moves. */
    track: HTMLElement;
    /** Elements that can be dragged or clicked to bring a page into view. */
    handles: HTMLElement[];
    /** Number of snap points. */
    pages: number;
    /** The visible width of the viewport the track moves inside. */
    pageWidth: () => number;
    /** Called with the index of the page nearest the resting position. */
    onChange?: (index: number) => void;
    /** Announce changes to assistive technology. */
    liveRegion?: HTMLElement;
    label?: string;
}

export interface Pager {
    destroy(): void;
    goTo(index: number, options?: { velocity?: number }): void;
    /** The page nearest the current rest position. */
    readonly index: number;
}

export function createPager({
    track,
    handles,
    pages,
    pageWidth,
    onChange,
    liveRegion,
    label = 'page',
}: PagerOptions): Pager {
    let current = 0;
    // The offset the drag started from, so the surface keeps the distance it had
    // from the pointer when it was grabbed.
    let origin = 0;
    let grabbed = false;

    const offsets = (): number[] => Array.from({ length: pages }, (_, index) => -index * pageWidth());

    function apply(x: number): void {
        track.style.transform = `translateX(${x}px)`;
    }

    function announce(index: number): void {
        if (!liveRegion) return;
        liveRegion.textContent = `${label} ${index + 1} of ${pages}`;
    }

    function settle(index: number, velocity = 0): void {
        current = Math.max(0, Math.min(pages - 1, index));
        springTo(
            track,
            { x: offsets()[current] },
            {
                spring: velocity === 0 ? 'settle' : 'momentum',
                velocity: velocity === 0 ? undefined : { x: velocity },
                onSettle: () => announce(current),
            },
        );
        onChange?.(current);
    }

    function nearestIndex(x: number): number {
        const stops = offsets();
        let best = 0;
        let distance = Infinity;
        stops.forEach((stop, index) => {
            const candidate = Math.abs(stop - x);
            if (candidate < distance) {
                best = index;
                distance = candidate;
            }
        });
        return best;
    }

    const drags: DragHandle[] = [];

    for (const handle of handles) {
        drags.push(
            draggable({
                element: handle,
                lock: 'x',
                onDrag: ({ offset }) => {
                    if (!grabbed) {
                        // The page may have been travelling when it was grabbed:
                        // continue from where it is, not from where it was going.
                        stopSpring(track);
                        origin = currentTranslateX(track);
                        grabbed = true;
                    }

                    const width = pageWidth();
                    apply(clampWithResistance(origin + offset, -width * (pages - 1), 0, width));
                },
                onRelease: ({ offset, velocity }) => {
                    grabbed = false;
                    const from = origin + offset;

                    if (prefersReducedMotion()) {
                        settle(nearestIndex(from));
                        return;
                    }

                    // Project where the release would have travelled to, including
                    // any rubber-banded overshoot, then land on the stop nearest
                    // that endpoint. The projection gives a position; the pager
                    // needs the page that position belongs to.
                    const landed = nearestIndex(from + project(velocity));
                    settle(landed, velocity);
                },
                onCancel: () => {
                    settle(current);
                },
            }),
        );
    }

    for (const [index, handle] of handles.entries()) {
        if (index >= pages) break;
        handle.addEventListener('keydown', (event) => {
            if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
            event.preventDefault();
            settle(Math.max(0, Math.min(pages - 1, index + (event.key === 'ArrowRight' ? 1 : -1))));
        });
    }

    apply(offsets()[0]);

    return {
        get index() {
            return current;
        },
        goTo(index, { velocity = 0 } = {}) {
            origin = offsets()[Math.max(0, Math.min(pages - 1, index))];
            settle(index, velocity);
        },
        destroy() {
            drags.forEach((drag) => drag.destroy());
        },
    };
}

/** The current x offset of a pager's track, for tests and for re-syncing. */
export function trackOffset(track: HTMLElement): number {
    return currentTranslateX(track);
}
