.pragma library
.import "point.js" as PointModule

var Point = PointModule.Point;
var DistanceEpsilon = 1e-4;
var AngleEpsilon = 1e-6;

function convex(previous, current, next) {
    return (current.minus(previous)).clockwise(next.minus(current));
}

function interpolate(start, stop, fraction) {
    return (1 - fraction) * start + fraction * stop;
}

function directionVector(x, y) {
    const d = distance(x, y);
    return new Point(x / d, y / d);
}

function distance(x, y) {
    return Math.sqrt(x * x + y * y);
}

function distanceSquared(x, y) {
    return x * x + y * y;
}

function radialToCartesian(radius, angleRadians, center = new Point(0, 0)) {
    return new Point(Math.cos(angleRadians), Math.sin(angleRadians))
        .times(radius)
        .plus(center);
}

function coerceIn(value, min, max) {
    if (max === undefined) {
        if (typeof min === 'object' && 'start' in min && 'endInclusive' in min) {
            return Math.max(min.start, Math.min(min.endInclusive, value));
        }
        throw new Error("Invalid arguments for coerceIn");
    }

    const [actualMin, actualMax] = min <= max ? [min, max] : [max, min];
    return Math.max(actualMin, Math.min(actualMax, value));
}

function positiveModulo(value, mod) {
    return ((value % mod) + mod) % mod;
}

