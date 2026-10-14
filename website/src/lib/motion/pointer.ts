/**
 * Direct manipulation.
 *
 * Three things make a drag feel attached to the pointer rather than to the
 * element:
 *
 *   - **Pointer capture.** Tracking continues outside the element's box, so a
 *     fast gesture or one that leaves the surface does not fall off.
 *   - **The grab offset.** The element keeps the distance it had from the
 *     pointer when it was grabbed. Snapping the element to the pointer on
 *     pointer-down is the most common way to break the illusion.
 *   - **A velocity history.** Velocity at release is what the animation
 *     inherits, and one point cannot produce it, so the last few moves are kept
 *     with their timestamps.
 *
 * Nothing here touches the DOM beyond the listeners: the caller owns the
 * element's transform, because only the caller knows what the surface is.
 */

import { resolveAxis, type DragAxis } from './projection';

export interface DragSample {
    /** Position along the dragged axis, in px, relative to where it was grabbed. */
    offset: number;
    time: number;
}

export interface DragState {
    /** The axis the gesture settled on. */
    axis: Exclude<DragAxis, null>;
    /** Offset along the locked axis, in px. */
    offset: number;
    /** Offset along the other axis, in px, for gestures allowed to wobble. */
    cross: number;
    event: PointerEvent;
}

export interface ReleaseState {
    /** Offset along the locked axis at release, in px. */
    offset: number;
    /** Release velocity along that axis, in px per second. */
    velocity: number;
    /** True when the gesture never passed the threshold, so it was a tap. */
    tap: boolean;
    event: PointerEvent;
}

export interface DragOptions {
    element: HTMLElement;
    /** Restrict the gesture to one axis, e.g. a notification that only swipes sideways. */
    lock?: Exclude<DragAxis, null>;
    /** Movement before an axis is committed to. */
    threshold?: number;
    onDrag?: (state: DragState) => void;
    onRelease?: (state: ReleaseState) => void;
    /** Escape, or the system taking the pointer away: the caller springs back. */
    onCancel?: (state: ReleaseState) => void;
    /** Pointer button that starts a drag. Defaults to the primary button. */
    button?: number;
}

// The window velocity is measured over. Long enough to smooth frame jitter,
// short enough that a flick's own speed is not averaged away.
const VELOCITY_WINDOW_MS = 100;

/**
 * Velocity over the last 100 ms, in units per second.
 *
 * From the oldest sample inside the window to the newest: that is the speed the
 * pointer actually had when it was lifted off. A regression over the same samples
 * gives a similar answer for a lot more arithmetic.
 *
 * When the window holds only the last sample — the previous move was longer ago
 * than the window, which happens when a frame is slow — the last two samples are
 * used anyway. Reporting zero there would read a hard flick as a stop, and the
 * distance fallback would then decide a gesture that was obviously a throw. A
 * pointer that genuinely stopped, or was held still and released, has two samples
 * at the same offset and still measures as zero.
 */
export function velocityFrom(samples: readonly DragSample[]): number {
    if (samples.length < 2) return 0;

    const last = samples[samples.length - 1];
    let first = samples[samples.length - 2];

    for (let index = samples.length - 2; index >= 0; index -= 1) {
        if (last.time - samples[index].time > VELOCITY_WINDOW_MS) break;
        first = samples[index];
    }

    const elapsed = last.time - first.time;
    if (elapsed <= 0) return 0;
    return ((last.offset - first.offset) / elapsed) * 1000;
}

export interface DragHandle {
    destroy(): void;
    /** True while a pointer is down. */
    readonly active: boolean;
}

/** Starts a pointer-driven drag on `element`. */
export function draggable({
    element,
    lock,
    threshold = 10,
    onDrag,
    onRelease,
    onCancel,
    button = 0,
}: DragOptions): DragHandle {
    let samples: DragSample[] = [];
    let pointerId: number | null = null;
    let startX = 0;
    let startY = 0;
    let axis: Exclude<DragAxis, null> | null = null;
    let last: DragState | null = null;

    function detach(): void {
        element.removeEventListener('pointermove', move);
        element.removeEventListener('pointerup', up);
        element.removeEventListener('pointercancel', cancel);
        window.removeEventListener('keydown', keydown);
    }

    function finish(event: PointerEvent, cancelled: boolean): void {
        const state: ReleaseState = {
            offset: last?.offset ?? 0,
            velocity: axis ? velocityFrom(samples) : 0,
            tap: axis === null,
            event,
        };

        if (pointerId !== null && element.hasPointerCapture(pointerId)) {
            element.releasePointerCapture(pointerId);
        }
        pointerId = null;
        samples = [];
        axis = null;
        last = null;
        detach();

        if (cancelled) onCancel?.(state);
        else onRelease?.(state);
    }

    function move(event: PointerEvent): void {
        if (pointerId !== event.pointerId) return;

        const dx = event.clientX - startX;
        const dy = event.clientY - startY;

        if (!axis) {
            // A locked axis still needs the threshold: without it, a tap on the
            // surface would read as a drag of zero distance.
            const travelled = lock === 'y' ? Math.abs(dy) : Math.abs(dx);
            const resolved = lock ? (travelled >= threshold ? lock : null) : resolveAxis(dx, dy, threshold);
            if (!resolved) return;
            axis = resolved;
        }

        const offset = axis === 'x' ? dx : dy;
        const cross = axis === 'x' ? dy : dx;

        samples.push({ offset, time: event.timeStamp });
        if (samples.length > 12) samples.shift();

        last = { axis, offset, cross, event };
        onDrag?.(last);
    }

    function up(event: PointerEvent): void {
        if (pointerId !== event.pointerId) return;
        finish(event, false);
    }

    function cancel(event: PointerEvent): void {
        if (pointerId !== event.pointerId) return;
        finish(event, true);
    }

    function keydown(event: KeyboardEvent): void {
        if (event.key !== 'Escape' || pointerId === null) return;
        // A keyboard cancel has no pointer event, but the last move carries the
        // position and the velocity, so it is reused.
        const carried = last?.event;
        if (carried) finish(carried, true);
    }

    function down(event: PointerEvent): void {
        if (event.button !== button || pointerId !== null) return;

        pointerId = event.pointerId;
        startX = event.clientX;
        startY = event.clientY;
        samples = [{ offset: 0, time: event.timeStamp }];
        axis = null;
        last = null;

        element.setPointerCapture(event.pointerId);
        element.addEventListener('pointermove', move);
        element.addEventListener('pointerup', up);
        element.addEventListener('pointercancel', cancel);
        window.addEventListener('keydown', keydown);
    }

    element.addEventListener('pointerdown', down);

    return {
        get active() {
            return pointerId !== null;
        },
        destroy() {
            element.removeEventListener('pointerdown', down);
            detach();
        },
    };
}
