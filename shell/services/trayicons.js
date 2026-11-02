.pragma library

// Tray icon identity and ordering. Per-icon settings are keyed by a value that
// survives the notifier id changing between launches, which is what makes a pinned
// or hidden icon stay that way after the app restarts.
//
// Kept free of QML types so the rules can be tested on their own; TrayRegistry.qml
// owns the state.

function pidOf(id) {
    const match = /^(\d+)-\d+$/.exec(id);
    return match ? match[1] : "";
}

// A notifier that ships no theme icon (a pixmap) names nothing stable, so it keeps
// its id as its key.
function themeIconName(icon) {
    if (!icon || !icon.startsWith("image://icon/"))
        return "";
    const name = icon.slice("image://icon/".length);
    return name && !name.includes("/") ? name : "";
}

function prettify(name) {
    return String(name ?? "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
}

// `comm` is the process behind the notifier, when it is known. Both forms name the
// app rather than the process hosting it, which is what changes between launches.
function keyOf(id, icon, comm) {
    if (comm)
        return `proc:${comm}`;
    const name = themeIconName(icon);
    return name ? `icon:${name}` : id;
}

function labelOf(key) {
    const value = String(key ?? "");
    return /^(proc|icon):/.test(value) ? prettify(value.replace(/^(proc|icon):/, "")) : value;
}

function iconNameOf(key) {
    return String(key ?? "").replace(/^(proc|icon):/, "");
}

// hidden wins over visible: an icon in both lists stays hidden.
function stateOf(key, hidden, visible) {
    if (hidden.includes(key))
        return "hidden";
    if (visible.includes(key))
        return "visible";
    return "collapsed";
}

// Rows carry a `key`. Listed keys come first, in the order the list gives them;
// everything else follows in the order it was handed in.
function ordered(rows, order) {
    if (order.length === 0)
        return rows;
    const rank = key => {
        const index = order.indexOf(key);
        return index < 0 ? order.length : index;
    };
    return rows.map((row, index) => ({
            row,
            index
        })).sort((a, b) => rank(a.row.key) - rank(b.row.key) || a.index - b.index).map(entry => entry.row);
}
