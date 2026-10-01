.pragma library

function createOffset(x, y) {
    return new Offset(x, y);
}

class Offset {
    constructor(x, y) {
        this.x = x;
        this.y = y;
    }

    copy(x = this.x, y = this.y) {
        return new Offset(x, y);
    }

    getDistance() {
        return Math.sqrt(this.x * this.x + this.y * this.y);
    }

    getDistanceSquared() {
        return this.x * this.x + this.y * this.y;
    }

    isValid() {
        return isFinite(this.x) && isFinite(this.y);
    }

    get isFinite() {
        return isFinite(this.x) && isFinite(this.y);
    }

    get isSpecified() {
        return !this.isUnspecified;
    }

    get isUnspecified() {
        return Object.is(this.x, NaN) && Object.is(this.y, NaN);
    }

    negate() {
        return new Offset(-this.x, -this.y);
    }

    minus(other) {
        return new Offset(this.x - other.x, this.y - other.y);
    }

    plus(other) {
        return new Offset(this.x + other.x, this.y + other.y);
    }

    times(operand) {
        return new Offset(this.x * operand, this.y * operand);
    }

    div(operand) {
        return new Offset(this.x / operand, this.y / operand);
    }

    rem(operand) {
        return new Offset(this.x % operand, this.y % operand);
    }

    toString() {
        if (this.isSpecified) {
            return `Offset(${this.x.toFixed(1)}, ${this.y.toFixed(1)})`;
        } else {
            return 'Offset.Unspecified';
        }
    }

    static lerp(start, stop, fraction) {
        return new Offset(
            start.x + (stop.x - start.x) * fraction,
            start.y + (stop.y - start.y) * fraction
        );
    }

    takeOrElse(block) {
        return this.isSpecified ? this : block();
    }

    angleDegrees() {
        return Math.atan2(this.y, this.x) * 180 / Math.PI;
    }

    rotateDegrees(angle, center = Offset.Zero) {
        const a = angle * Math.PI / 180;
        const off = this.minus(center);
        const cosA = Math.cos(a);
        const sinA = Math.sin(a);
        const newX = off.x * cosA - off.y * sinA;
        const newY = off.x * sinA + off.y * cosA;
        return new Offset(newX, newY).plus(center);
    }
}

Offset.Zero = new Offset(0, 0);
Offset.Infinite = new Offset(Infinity, Infinity);
Offset.Unspecified = new Offset(NaN, NaN);
