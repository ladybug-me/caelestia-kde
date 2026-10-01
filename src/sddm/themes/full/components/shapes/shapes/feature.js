.pragma library
.import "cubic.js" as CubicModule

var Cubic = CubicModule.Cubic;

class Feature {
    constructor(cubics) {
        this.cubics = cubics;
    }

    buildIgnorableFeature(cubics) {
        return new Edge(cubics);
    }

    buildEdge(cubic) {
        return new Edge([cubic]);
    }

    buildConvexCorner(cubics) {
        return new Corner(cubics, true);
    }

    buildConcaveCorner(cubics) {
        return new Corner(cubics, false);
    }
}

class Edge extends Feature {
    constructor(cubics) {
        super(cubics);
        this.isIgnorableFeature = true;
        this.isEdge = true;
        this.isConvexCorner = false;
        this.isConcaveCorner = false;
    }

    transformed(f) {
        return new Edge(this.cubics.map(c => c.transformed(f)));
    }

    reversed() {
        return new Edge(this.cubics.map(c => c.reverse()));
    }
}

class Corner extends Feature {
    constructor(cubics, convex) {
        super(cubics);
        this.convex = convex;
        this.isIgnorableFeature = false;
        this.isEdge = false;
        this.isConvexCorner = convex;
        this.isConcaveCorner = !convex;
    }

    transformed(f) {
        return new Corner(this.cubics.map(c => c.transformed(f)), this.convex);
    }

    reversed() {
        return new Corner(this.cubics.map(c => c.reverse()), !this.convex);
    }
}