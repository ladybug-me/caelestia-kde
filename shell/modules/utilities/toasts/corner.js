.pragma library

// The corner vocabulary in one place: the names the setting stores, the rule that turns
// `auto` into a real corner, and the two questions the layout asks about one. Nothing
// else parses a corner name.
var VALUES = ["auto", "top-left", "top-right", "bottom-left", "bottom-right"];

// `auto` is the spot the shell has always used: the bottom, on the side away from a
// vertical bar, which is the left when the bar runs along the bottom. A value the setting
// has no name for is treated as `auto`, so a hand-edited file cannot place the stack
// somewhere no row can show.
function resolve(name, barPosition) {
    if (name !== "auto" && VALUES.indexOf(name) !== -1)
        return name;

    return barPosition === "bottom" || barPosition === "right" ? "bottom-left" : "bottom-right";
}

// Which row a stored value belongs to, paired with resolve: the row says automatic
// exactly when the layout falls back to automatic's corner.
function index(name) {
    var i = VALUES.indexOf(name);
    return i === -1 ? 0 : i;
}

function isTop(name) {
    return name.startsWith("top");
}

function isLeft(name) {
    return name.endsWith("left");
}
