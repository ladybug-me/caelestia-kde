import { describe, expect, it } from 'vitest';

import { SPRINGS, isCriticallyDamped, toMotionSpring } from '../../src/lib/motion/spring';

/**
 * Simulates the spring as a second-order system, which is the only way to make
 * claims about "settles" and "overshoots" that mean anything.
 *
 * x'' = -(k/m)(x - target) - (c/m)x'
 */
function simulate(spring: { stiffness: number; damping: number; mass: number }, seconds = 4, step = 1 / 240) {
    let position = 0;
    let velocity = 0;
    let peak = 0;
    const target = 1;

    for (let time = 0; time < seconds; time += step) {
        const acceleration = (-spring.stiffness * (position - target) - spring.damping * velocity) / spring.mass;
        velocity += acceleration * step;
        position += velocity * step;
        peak = Math.max(peak, position);
    }

    return { peak, settled: Math.abs(position - target) };
}

describe('toMotionSpring', () => {
    it('maps response to stiffness as (2pi/T)^2', () => {
        const spring = toMotionSpring({ damping: 1, response: 0.4 });
        expect(spring.stiffness).toBeCloseTo(Math.pow((2 * Math.PI) / 0.4, 2), 6);
    });

    it('maps damping ratio to c = 4*zeta*pi/T', () => {
        const spring = toMotionSpring({ damping: 0.8, response: 0.3 });
        expect(spring.damping).toBeCloseTo((4 * Math.PI * 0.8) / 0.3, 6);
    });

    it('keeps mass out of the shape of the motion', () => {
        const light = toMotionSpring({ damping: 1, response: 0.35, mass: 1 });
        const heavy = toMotionSpring({ damping: 1, response: 0.35, mass: 2 });
        expect(heavy.stiffness / heavy.mass).toBeCloseTo(light.stiffness / light.mass, 6);
        expect(heavy.damping / heavy.mass).toBeCloseTo(light.damping / light.mass, 6);
    });

    it('refuses parameters that cannot produce a spring', () => {
        expect(() => toMotionSpring({ damping: 1, response: 0 })).toThrow(RangeError);
        expect(() => toMotionSpring({ damping: 0, response: 0.3 })).toThrow(RangeError);
    });
});

describe('the house springs', () => {
    it('settles without overshoot when it is critically damped', () => {
        const { peak, settled } = simulate(toMotionSpring(SPRINGS.settle));
        expect(peak).toBeLessThanOrEqual(1.001);
        expect(settled).toBeLessThan(0.01);
    });

    it('overshoots deliberately on a gesture release', () => {
        const { peak } = simulate(toMotionSpring(SPRINGS.momentum));
        expect(peak).toBeGreaterThan(1.001);
        // A bounce, not a wobble: under 12% past the target.
        expect(peak).toBeLessThan(1.12);
    });

    it('settles every spring inside half a second', () => {
        for (const [name, spring] of Object.entries(SPRINGS)) {
            const { settled } = simulate(toMotionSpring(spring), 0.5);
            expect(settled, `${name} had not settled`).toBeLessThan(0.02);
        }
    });

    it('only the gesture springs are under-damped', () => {
        expect(isCriticallyDamped(SPRINGS.settle)).toBe(true);
        expect(isCriticallyDamped(SPRINGS.reposition)).toBe(true);
        expect(isCriticallyDamped(SPRINGS.momentum)).toBe(false);
        expect(isCriticallyDamped(SPRINGS.drawer)).toBe(false);
    });
});
