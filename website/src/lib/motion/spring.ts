/**
 * Springs, in Apple's two parameters.
 *
 * A designer should not have to think in stiffness, damping and mass, so the
 * authoring surface here is **damping ratio** (does it overshoot?) and
 * **response** (how quickly does it get there?). Motion is driven by the
 * physics form rather than `bounce` + duration, for two reasons that matter:
 *
 *   1. A duration-based spring ignores the velocity a gesture ended with, and
 *      the velocity handoff is the whole point (see the release code in
 *      pointer.ts).
 *   2. A physics spring carries the current value's velocity by default, so
 *      re-targeting mid-flight continues the motion instead of restarting it.
 *
 * Mapping, for a spring of mass m = 1:
 *
 *   stiffness k = ω₀² = (2π / response)²
 *   damping   c = 2ζω₀ = 4πζ / response
 *
 * `response` is *not* a duration: the settle time falls out of the parameters.
 */

export interface AppleSpring {
    /** 1.0 is critically damped and settles without overshoot. Below that it bounces. */
    damping: number;
    /** Time to reach the target, in seconds. Lower is snappier. */
    response: number;
    mass?: number;
}

export interface MotionSpring {
    type: 'spring';
    stiffness: number;
    damping: number;
    mass: number;
}

/** Per-axis velocity, for motion that is not the same on both axes. */
export interface AxisVelocity {
    x?: number;
    y?: number;
}

/** Converts Apple's parameters into the physics form `motion` animates with. */
export function toMotionSpring({ damping, response, mass = 1 }: AppleSpring): MotionSpring {
    if (!(response > 0)) throw new RangeError(`response must be greater than zero, got ${response}`);
    if (!(damping > 0)) throw new RangeError(`damping must be greater than zero, got ${damping}`);

    const omega = (2 * Math.PI) / response;
    return {
        type: 'spring',
        stiffness: omega * omega * mass,
        damping: 2 * damping * omega * mass,
        mass,
    };
}

/**
 * The house springs.
 *
 * Most UI is critically damped: a menu that was never thrown anywhere has no
 * business bouncing. Bounce is reserved for motion a gesture started, because
 * overshoot reads as momentum there and as sloppiness anywhere else.
 */
export const SPRINGS = {
    /** Default for chrome that appears without a gesture. */
    settle: { damping: 1, response: 0.35 },
    /** An element changing position. */
    reposition: { damping: 1, response: 0.4 },
    /** Anything released from a pointer: the drawer and sheet case Apple ships. */
    momentum: { damping: 0.8, response: 0.3 },
    /** A surface travelling open or closed under the pointer. */
    drawer: { damping: 0.8, response: 0.3 },
    /** Colour and opacity changes that are not gesture-driven. */
    fade: { damping: 1, response: 0.25 },
} as const satisfies Record<string, AppleSpring>;

export type SpringName = keyof typeof SPRINGS;

/**
 * Motion options for one of the house springs, carrying a release velocity.
 *
 * Motion takes velocity either as one number for the whole animation or as a
 * per-value option, so a release that was faster sideways than vertically keeps
 * both: a single spring over the 2D distance would desync the moment the two
 * axes differ.
 */
export function springOptions(name: SpringName, velocity?: number | AxisVelocity): Record<string, unknown> {
    const spring = toMotionSpring(SPRINGS[name]);
    if (velocity === undefined) return { ...spring };

    if (typeof velocity === 'number') {
        return velocity === 0 ? { ...spring } : { ...spring, velocity };
    }

    const perAxis: Record<string, unknown> = { ...spring };
    if (velocity.x) perAxis.x = { velocity: velocity.x };
    if (velocity.y) perAxis.y = { velocity: velocity.y };
    return perAxis;
}

/**
 * The damping ratio that produces no overshoot, for tests and for reasoning
 * about a spring that was tuned by eye.
 */
export function isCriticallyDamped(spring: AppleSpring): boolean {
    return spring.damping >= 1;
}
