/**
 * The bridge between the spring tokens and an element on the page.
 *
 * Two rules are enforced here so no demo has to remember them:
 *
 *   - Under `prefers-reduced-motion` the element still arrives at its target, it
 *     just does not travel there: position is set outright and only opacity is
 *     eased.
 *   - A release velocity is handed to the spring, which is what makes the
 *     animation continue a throw instead of starting a new one.
 *
 * And one that is easy to get wrong: an element has at most one animation. Two
 * animations writing the same transform fight, and the loser is whichever one is
 * not being read — a drag that starts mid-flight appears frozen because the
 * spring keeps overwriting the pointer's position. Animating stops the previous
 * animation first, and direct manipulation calls `stopSpring` before it reads
 * the live transform.
 */

import { animate, type AnimationPlaybackControls } from 'motion';

import { springOptions, type AxisVelocity, type SpringName } from './spring';
import { prefersReducedMotion } from './prefers';

export interface TransformKeys {
    /** Motion writes these as independent transforms; one 2D spring would desync them. */
    [key: string]: number | undefined;
    x?: number;
    y?: number;
    scale?: number;
    opacity?: number;
    rotate?: number;
}

export interface SpringToOptions {
    /** Which house spring to use. */
    spring?: SpringName;
    /** Release velocity in px/s, for a gesture that has just ended. */
    velocity?: number | AxisVelocity;
    /** Called once the spring comes to rest. */
    onSettle?: () => void;
}

// The animation each element is currently running, so the next one can stop it
// rather than fight it. A WeakMap, because an element that leaves the page must
// not keep its animation alive.
const running = new WeakMap<Element, AnimationPlaybackControls>();

/**
 * Animates `element` to `keyframes` and returns the playback controls.
 *
 * Motion starts from the value that is on screen, so stopping the previous
 * animation and starting this one is continuous by construction: the interrupted
 * motion carries on from where it was, rather than restarting from the target it
 * was heading for.
 */
export function springTo(
    element: Element,
    keyframes: TransformKeys,
    { spring = 'settle', velocity, onSettle }: SpringToOptions = {},
): AnimationPlaybackControls {
    stopSpring(element);

    const { opacity, ...transform } = keyframes;

    if (prefersReducedMotion()) {
        // Travel is what the preference is about; the destination is not.
        if (Object.keys(transform).length > 0) animate(element, transform, { duration: 0.001 });
        const fade = animate(element, { opacity: opacity ?? 1 }, { duration: 0.2, ease: 'easeOut' });
        running.set(element, fade);
        if (onSettle) fade.finished.then(onSettle).catch(() => undefined);
        return fade;
    }

    // The options object is built by name from the spring tokens, so its shape is
    // only known to springOptions; Motion's option type is structural.
    const controls = animate(element, keyframes, springOptions(spring, velocity) as Parameters<typeof animate>[2]);
    running.set(element, controls);
    if (onSettle) controls.finished.then(onSettle).catch(() => undefined);
    return controls;
}

/**
 * Stops whatever spring is running on `element`.
 *
 * Direct manipulation calls this before reading the live transform: without it,
 * the element's position is a race between the pointer and the animation that
 * was already in flight.
 */
export function stopSpring(element: Element): void {
    const controls = running.get(element);
    if (!controls) return;
    running.delete(element);
    controls.stop();
}

/** The live X translation, so a re-target can start from the presented value. */
export function currentTranslateX(element: Element): number {
    return readTransform(element)[4];
}

/** The live Y translation. */
export function currentTranslateY(element: Element): number {
    return readTransform(element)[5];
}

/**
 * The element's transform matrix, as far as the browser reports it. `matrix(a,
 * b, c, d, tx, ty)` puts the translation at indices 4 and 5, which is the 2D case
 * the site uses everywhere.
 */
function readTransform(element: Element): number[] {
    const transform = getComputedStyle(element).transform;
    if (!transform || transform === 'none') return [1, 0, 0, 1, 0, 0];
    const values = transform.match(/-?\d*\.?\d+(?:e-?\d+)?/g)?.map(Number) ?? [];
    return values.length >= 6 ? values : [1, 0, 0, 1, 0, 0];
}
