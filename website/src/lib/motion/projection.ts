/**
 * Momentum and boundaries.
 *
 * Pure functions, so the arithmetic that decides where a flick lands can be
 * tested without a browser.
 */

/**
 * Apple's projection, from the *Designing Fluid Interfaces* sample code: where
 * a gesture would come to rest if it kept decelerating.
 *
 * The physics-textbook `v² / 2a` is not this. The exponential decay form below
 * is what the shell's own momentum matches, and `0.998` is the normal scroll
 * feel; lower it for a snappier surface.
 */
export function project(velocity: number, decelerationRate = 0.998): number {
    return (velocity / 1000) * (decelerationRate / (1 - decelerationRate));
}

/**
 * The snap point a gesture is heading for.
 *
 * Choosing from the projected endpoint rather than the release position is what
 * makes a small flick travel a long way, and what stops a slow drag that ends
 * just past a boundary from jumping to the next one.
 */
export function nearestSnapPoint(projected: number, points: readonly number[]): number {
    let best = points[0];
    let bestDistance = Math.abs(projected - best);

    for (const point of points) {
        const distance = Math.abs(projected - point);
        if (distance < bestDistance) {
            best = point;
            bestDistance = distance;
        }
    }

    return best;
}

/** Where a flick lands, in one step: project, then snap. */
export function projectToSnap(
    current: number,
    velocity: number,
    points: readonly number[],
    decelerationRate = 0.998,
): number {
    return nearestSnapPoint(current + project(velocity, decelerationRate), points);
}

/**
 * Progressive resistance past a boundary.
 *
 * A hard stop reads as frozen; resistance reads as "responsive, but there is
 * nothing more here". Movement keeps following the pointer, just less and less
 * of it, so a drag past the end can always be brought back.
 */
export function rubberband(overshoot: number, dimension: number, constant = 0.55): number {
    if (dimension <= 0) return 0;
    return (overshoot * dimension * constant) / (dimension + constant * Math.abs(overshoot));
}

/** Applies rubber-banding to a position that has gone past `min`/`max`. */
export function clampWithResistance(value: number, min: number, max: number, dimension: number): number {
    if (value < min) return min + rubberband(value - min, dimension);
    if (value > max) return max + rubberband(value - max, dimension);
    return value;
}

/** Which way a drag is going, once intent is clear. `null` while it is not. */
export type DragAxis = 'x' | 'y' | null;

/**
 * Locks a drag to one axis after a small threshold, so a gesture that starts
 * diagonally does not wobble. Below the threshold nothing is committed.
 */
export function resolveAxis(dx: number, dy: number, threshold = 10): DragAxis {
    if (Math.abs(dx) < threshold && Math.abs(dy) < threshold) return null;
    return Math.abs(dx) >= Math.abs(dy) ? 'x' : 'y';
}

export interface DismissDecision {
    /** Offset from rest at release, in px. */
    offset: number;
    /** Release velocity, px/s, signed the same way as `offset`. */
    velocity: number;
    /** The dimension being travelled across, in px. */
    size: number;
    /** Fraction of `size` that counts as past the point of no return. */
    distanceFraction?: number;
    /** Speed above which the throw alone decides, in px/s. */
    velocityThreshold?: number;
}

/**
 * Whether a swipe dismisses or springs back — the notification case, where
 * either direction clears the card and only the distance from rest matters.
 *
 * A throw is decided by speed and a slow release by distance, so a small quick
 * flick works and a slow drag that barely moves does not. The shell's popup uses
 * the same shape: `Math.abs(root.x)` against a fraction of its width.
 */
export function isDismissed({
    offset,
    velocity,
    size,
    distanceFraction = 0.4,
    velocityThreshold = 400,
}: DismissDecision): boolean {
    if (Math.abs(velocity) >= velocityThreshold) return Math.sign(velocity) === Math.sign(offset) || offset === 0;
    return Math.abs(offset) >= size * distanceFraction;
}

export interface TwoStateDecision {
    /** Offset from the first rest state, in px. */
    offset: number;
    /** Release velocity, px/s. */
    velocity: number;
    /** Distance between the two rest states, in px. Positive. */
    travel: number;
    /** Below this speed, release is a stop, in px/s. */
    velocityThreshold?: number;
}

/**
 * Which of two rest states a released surface belongs in — the drawer case.
 *
 * Velocity decides when there is any of it: a surface pushed a third of the way
 * open and thrown open keeps going, and the same surface let go comes back.
 * Only a slow release falls back to distance. Returns `true` for the further
 * state.
 */
export function resolvesToFarState({ offset, velocity, travel, velocityThreshold = 400 }: TwoStateDecision): boolean {
    if (travel <= 0) return false;
    if (Math.abs(velocity) >= velocityThreshold) return velocity > 0;
    return offset >= travel / 2;
}
