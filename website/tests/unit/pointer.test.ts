import { describe, expect, it } from 'vitest';

import { velocityFrom } from '../../src/lib/motion/pointer';

/**
 * Velocity at release is what the animation inherits, so it is the one number in
 * the gesture layer that has to be right. These tests pin the three cases that
 * actually occur: a steady drag, a flick, and a release after a pause.
 */
describe('velocityFrom', () => {
    it('is zero without two samples to compare', () => {
        expect(velocityFrom([])).toBe(0);
        expect(velocityFrom([{ offset: 40, time: 100 }])).toBe(0);
    });

    it('measures a steady drag as its own speed', () => {
        // 100px over 100ms is 1000px/s.
        const samples = [
            { offset: 0, time: 0 },
            { offset: 50, time: 50 },
            { offset: 100, time: 100 },
        ];
        expect(velocityFrom(samples)).toBeCloseTo(1000, 6);
    });

    it('measures a flick from the samples inside the velocity window', () => {
        // A slow start, then a hard flick in the last 100ms.
        const samples = [
            { offset: 0, time: 0 },
            { offset: 20, time: 300 },
            { offset: 60, time: 400 },
            { offset: 160, time: 500 },
        ];
        // The window covers 400 -> 500, i.e. 100px in 100ms, which is the flick
        // rather than the slow drag that preceded it.
        expect(velocityFrom(samples)).toBeCloseTo(1000, 0);
    });

    it('reads a release after a pause as a stop, not as the drag that came before', () => {
        const samples = [
            { offset: 0, time: 0 },
            { offset: 300, time: 300 },
            // The pointer stopped moving, but kept reporting.
            { offset: 300, time: 400 },
            { offset: 300, time: 500 },
        ];
        expect(velocityFrom(samples)).toBe(0);
    });

    it('keeps the sign of the direction', () => {
        const samples = [
            { offset: 0, time: 0 },
            { offset: -80, time: 100 },
        ];
        expect(velocityFrom(samples)).toBeCloseTo(-800, 6);
    });

    it('still measures the throw when the last move was longer ago than the window', () => {
        // A slow frame between the last two moves. Reporting zero here would read
        // the flick as a stop and let the distance fallback decide.
        const samples = [
            { offset: 0, time: 0 },
            { offset: 120, time: 40 },
            { offset: 260, time: 210 },
        ];
        expect(velocityFrom(samples)).toBeCloseTo(823.5, 0);
    });

    it('ignores samples with no time between them rather than dividing by zero', () => {
        expect(
            velocityFrom([
                { offset: 0, time: 250 },
                { offset: 90, time: 250 },
            ]),
        ).toBe(0);
    });
});
