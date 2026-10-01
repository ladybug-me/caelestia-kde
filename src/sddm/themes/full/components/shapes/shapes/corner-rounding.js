.pragma library

class CornerRounding {
    constructor(radius = 0, smoothing = 0) {
        this.radius = radius;
        this.smoothing = smoothing;
    }
}

CornerRounding.Unrounded = new CornerRounding();