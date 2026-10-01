.pragma library

function createPoint(x, y) {
    return new Point(x, y);
}

class Point {
    constructor(x, y) {
        this.x = x;
        this.y = y;
    }

    copy(x = this.x, y = this.y) {
        return new Point(x, y);
    }

    getDistance() {
        return Math.sqrt(this.x * this.x + this.y * this.y);
    }

    getDistanceSquared() {
        return this.x * this.x + this.y * this.y;
    }

    dotProduct(other) {
        return this.x * other.x + this.y * other.y;
    }

    dotProductScalar(otherX, otherY) {
        return this.x * otherX + this.y * otherY;
    }

    clockwise(other) {
        return this.x * other.y - this.y * other.x > 0;
    }

    getDirection() {
        const d = this.getDistance();
        return this.div(d);
    }

    negate() {
        return new Point(-this.x, -this.y);
    }

    minus(other) {
        return new Point(this.x - other.x, this.y - other.y);
    }

    plus(other) {
        return new Point(this.x + other.x, this.y + other.y);
    }

    times(operand) {
        return new Point(this.x * operand, this.y * operand);
    }

    div(operand) {
        return new Point(this.x / operand, this.y / operand);
    }

    rem(operand) {
        return new Point(this.x % operand, this.y % operand);
    }

    static interpolate(start, stop, fraction) {
        return new Point(
            start.x + (stop.x - start.x) * fraction,
            start.y + (stop.y - start.y) * fraction
        );
    }

    transformed(f) {
        const result = f(this.x, this.y);
        return new Point(result.x, result.y);
    }

    rotate90() {
        return new Point(-this.y, this.x);
    }
}

