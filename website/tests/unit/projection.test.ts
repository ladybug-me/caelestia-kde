import { describe, expect, it } from 'vitest';

import {
    clampWithResistance,
    isDismissed,
    nearestSnapPoint,
    project,
    projectToSnap,
    resolveAxis,
    resolvesToFarState,
    rubberband,
} from '../../src/lib/motion/projection';

describe('project', () => {
    it("matches Apple's shipped deceleration for a known velocity", () => {
        // (1000/1000) * 0.998 / 0.002
        expect(project(1000)).toBeCloseTo(499, 1);
    });

    it('projects nothing for a release at rest', () => {
        expect(project(0)).toBe(0);
    });

    it('projects backwards for a backwards throw', () => {
        expect(project(-2000)).toBeLessThan(0);
        expect(Math.abs(project(-2000))).toBeGreaterThan(Math.abs(project(-1000)));
    });

    it('travels further at the snappier deceleration rate', () => {
        expect(Math.abs(project(1000, 0.99))).toBeLessThan(Math.abs(project(1000, 0.998)));
    });
});

describe('nearestSnapPoint', () => {
    const stops = [0, -400, -800];

    it('chooses the stop the projection is heading for, not the release point', () => {
        // Released 100px in from the first stop, thrown hard enough to project
        // past the second one.
        expect(projectToSnap(100, -3000, stops)).toBe(-800);
        // The same release thrown the other way comes back to the first stop.
        expect(projectToSnap(100, 3000, stops)).toBe(0);
    });

    it('stays put when released slowly between two stops', () => {
        expect(projectToSnap(-180, 0, stops)).toBe(0);
        expect(projectToSnap(-220, 0, stops)).toBe(-400);
    });

    it('never returns a stop that does not exist', () => {
        expect(nearestSnapPoint(-99999, stops)).toBe(-800);
        expect(nearestSnapPoint(99999, stops)).toBe(0);
    });
});

describe('rubberband', () => {
    it('follows the pointer less and less as it goes past the boundary', () => {
        const first = rubberband(50, 400);
        const second = rubberband(100, 400);
        const third = rubberband(150, 400);

        expect(first).toBeGreaterThan(0);
        expect(second).toBeGreaterThan(first);
        expect(third).toBeGreaterThan(second);
        // Diminishing returns: equal pulls past the boundary buy less and less
        // movement as they go.
        expect(second - first).toBeGreaterThan(third - second);
    });

    it('is always less than the movement that caused it, and approaches the dimension', () => {
        for (const overshoot of [1, 10, 100, 1000, 10000]) {
            const resisted = rubberband(overshoot, 400);
            expect(resisted).toBeGreaterThan(0);
            expect(resisted).toBeLessThan(overshoot);
            // The asymptote is the surface's own dimension: no amount of
            // dragging past the end moves it further than its own width.
            expect(resisted).toBeLessThan(400);
        }
    });

    it('leaves a position inside the bounds alone', () => {
        expect(clampWithResistance(120, 0, 400, 400)).toBe(120);
        expect(clampWithResistance(-30, 0, 400, 400)).toBeGreaterThan(-30);
        expect(clampWithResistance(430, 0, 400, 400)).toBeLessThan(430);
    });
});

describe('resolveAxis', () => {
    it('commits to nothing below the threshold', () => {
        expect(resolveAxis(4, 3)).toBeNull();
        expect(resolveAxis(-9, 9)).toBeNull();
    });

    it('picks the larger of the two directions once past it', () => {
        expect(resolveAxis(40, 5)).toBe('x');
        expect(resolveAxis(5, -40)).toBe('y');
        expect(resolveAxis(-30, -20)).toBe('x');
    });
});

describe('isDismissed', () => {
    const size = 320;

    it('dismisses a throw even when it has barely moved', () => {
        expect(isDismissed({ offset: 30, velocity: 1500, size })).toBe(true);
    });

    it('brings back a card that was let go slowly', () => {
        expect(isDismissed({ offset: 60, velocity: 20, size })).toBe(false);
    });

    it('dismisses on distance when there is no velocity to read', () => {
        expect(isDismissed({ offset: 200, velocity: 0, size })).toBe(true);
        expect(isDismissed({ offset: 80, velocity: 0, size })).toBe(false);
    });

    it('works in either direction', () => {
        expect(isDismissed({ offset: -200, velocity: 0, size })).toBe(true);
        expect(isDismissed({ offset: -30, velocity: -1500, size })).toBe(true);
    });

    it('does not dismiss a push that opposes the throw', () => {
        // Dragged left, released rightwards: the release wins.
        expect(isDismissed({ offset: -100, velocity: 1200, size })).toBe(false);
    });

    it('honours a tighter threshold when one is given', () => {
        expect(isDismissed({ offset: 100, velocity: 0, size, distanceFraction: 0.25 })).toBe(true);
        expect(isDismissed({ offset: 100, velocity: 0, size, distanceFraction: 0.5 })).toBe(false);
    });
});

describe('resolvesToFarState', () => {
    it('throws a surface open from part way', () => {
        expect(resolvesToFarState({ offset: 40, velocity: 900, travel: 300 })).toBe(true);
    });

    it('gives up and closes when the throw was the other way', () => {
        expect(resolvesToFarState({ offset: 200, velocity: -900, travel: 300 })).toBe(false);
    });

    it('falls back to distance for a slow release', () => {
        expect(resolvesToFarState({ offset: 200, velocity: 10, travel: 300 })).toBe(true);
        expect(resolvesToFarState({ offset: 100, velocity: 10, travel: 300 })).toBe(false);
    });

    it('stays put when there is no travel', () => {
        expect(resolvesToFarState({ offset: 100, velocity: 5000, travel: 0 })).toBe(false);
    });
});
