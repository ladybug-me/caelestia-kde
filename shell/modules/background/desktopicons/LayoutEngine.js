.pragma library

// Grid layout helpers for the desktop icons. Positions are plain objects
// mapping an item key to { col, row }; nothing here touches QML state.

function cellId(col, row) {
    return col + "," + row;
}

function inGrid(pos, cols, rows) {
    return pos.col >= 0 && pos.row >= 0 && pos.col < cols && pos.row < rows;
}

function occupancy(positions, excludeKeys) {
    const occ = {};
    for (const key in positions) {
        if (excludeKeys && excludeKeys.indexOf(key) !== -1)
            continue;
        const p = positions[key];
        occ[cellId(p.col, p.row)] = key;
    }
    return occ;
}

// Column-major index, the order icons fill the desktop in.
function orderIndex(pos, rows) {
    return pos.col * rows + pos.row;
}

function orderedKeys(positions, rows) {
    return Object.keys(positions).sort((a, b) => orderIndex(positions[a], rows) - orderIndex(positions[b], rows));
}

// First free cell in column-major order. Past a full grid, keeps counting
// into the columns beyond the right edge rather than stacking icons.
function firstFree(occ, cols, rows) {
    for (let i = 0; i < 100000; i++) {
        const col = Math.floor(i / rows);
        const row = i % rows;
        if (!(cellId(col, row) in occ))
            return { col, row };
    }
    return { col: cols, row: 0 };
}

// Free cell closest to (col, row), ties broken towards the fill order.
function nearestFree(occ, col, row, cols, rows) {
    let best = null;
    let bestDist = Infinity;
    for (let c = 0; c < cols; c++) {
        for (let r = 0; r < rows; r++) {
            if (cellId(c, r) in occ)
                continue;
            const d = (c - col) * (c - col) + (r - row) * (r - row);
            if (d < bestDist || (d === bestDist && orderIndex({ col: c, row: r }, rows) < orderIndex(best, rows))) {
                best = { col: c, row: r };
                bestDist = d;
            }
        }
    }
    return best ?? firstFree(occ, cols, rows);
}

function copyPositions(positions) {
    const out = {};
    for (const key in positions)
        out[key] = { col: positions[key].col, row: positions[key].row };
    return out;
}

// Moves the keys in `moving` so that `anchor` lands on `target`, keeping their
// relative placement. The shift is clamped so every moved item stays on the
// grid. Items already sitting on a destination cell step aside to the free
// cell nearest to where they were.
function planMove(positions, moving, anchor, target, cols, rows) {
    const out = copyPositions(positions);
    const from = positions[anchor];
    if (!from)
        return out;
    let dc = target.col - from.col;
    let dr = target.row - from.row;
    for (const key of moving) {
        const p = positions[key];
        if (!p)
            continue;
        dc = Math.max(dc, -p.col);
        dr = Math.max(dr, -p.row);
    }
    for (const key of moving) {
        const p = positions[key];
        if (!p)
            continue;
        dc = Math.min(dc, cols - 1 - p.col);
        dr = Math.min(dr, rows - 1 - p.row);
    }

    const dest = {};
    for (const key of moving) {
        const p = positions[key];
        if (!p)
            continue;
        out[key] = { col: p.col + dc, row: p.row + dr };
        dest[cellId(out[key].col, out[key].row)] = key;
    }

    // Everyone that is not moving keeps their cell unless a mover took it.
    const occ = Object.assign({}, dest);
    const displaced = [];
    for (const key in positions) {
        if (moving.indexOf(key) !== -1)
            continue;
        const id = cellId(positions[key].col, positions[key].row);
        if (id in dest)
            displaced.push(key);
        else
            occ[id] = key;
    }
    for (const key of displaced) {
        const p = positions[key];
        const cell = nearestFree(occ, p.col, p.row, cols, rows);
        out[key] = cell;
        occ[cellId(cell.col, cell.row)] = key;
    }
    return out;
}

// Lays the keys out back to back in column-major order.
function compact(keys, rows) {
    const out = {};
    for (let i = 0; i < keys.length; i++)
        out[keys[i]] = { col: Math.floor(i / rows), row: i % rows };
    return out;
}

// Auto-arrange drop: pulls the moving keys out of the order and inserts them
// where `target` is, then packs everything again.
function planInsert(positions, moving, target, rows) {
    const order = orderedKeys(positions, rows);
    const targetIndex = orderIndex(target, rows);
    const rest = [];
    let insertAt = -1;
    for (const key of order) {
        if (moving.indexOf(key) !== -1)
            continue;
        if (insertAt === -1 && orderIndex(positions[key], rows) >= targetIndex)
            insertAt = rest.length;
        rest.push(key);
    }
    if (insertAt === -1)
        insertAt = rest.length;
    const movers = order.filter(k => moving.indexOf(k) !== -1);
    rest.splice(insertAt, 0, ...movers);
    return compact(rest, rows);
}

// Pulls items that fell off a shrunken grid back onto it.
function fitIntoGrid(positions, cols, rows) {
    const out = {};
    const outside = [];
    const occ = {};
    for (const key of orderedKeys(positions, rows)) {
        const p = positions[key];
        const id = cellId(p.col, p.row);
        if (inGrid(p, cols, rows) && !(id in occ)) {
            out[key] = { col: p.col, row: p.row };
            occ[id] = key;
        } else {
            outside.push(key);
        }
    }
    for (const key of outside) {
        const p = positions[key];
        const cell = nearestFree(occ, Math.min(p.col, cols - 1), Math.min(p.row, rows - 1), cols, rows);
        out[key] = cell;
        occ[cellId(cell.col, cell.row)] = key;
    }
    return out;
}

// Stable sort for "Sort by". Items are { key, name, kind, type, modified, size };
// folders and groups always come first, like Plasma's "folders first".
function sortItems(items, sortKey) {
    const rank = it => it.kind === "dir" || it.kind === "group" ? 0 : 1;
    const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
    const cmp = {
        name: byName,
        type: (a, b) => (a.type || "").localeCompare(b.type || "") || byName(a, b),
        modified: (a, b) => (b.modified || 0) - (a.modified || 0) || byName(a, b),
        size: (a, b) => (b.size || 0) - (a.size || 0) || byName(a, b)
    }[sortKey] ?? byName;
    return items.slice().sort((a, b) => rank(a) - rank(b) || cmp(a, b));
}

// Where keyboard focus goes from `fromKey` for an arrow key. Prefers the
// closest item along the pressed axis, then the one closest to the same line.
function navigate(positions, fromKey, dir) {
    const from = positions[fromKey];
    if (!from)
        return null;
    let best = null;
    let bestScore = Infinity;
    for (const key in positions) {
        if (key === fromKey)
            continue;
        const p = positions[key];
        const dc = p.col - from.col;
        const dr = p.row - from.row;
        let primary;
        let secondary;
        if (dir === "left") {
            primary = -dc;
            secondary = Math.abs(dr);
        } else if (dir === "right") {
            primary = dc;
            secondary = Math.abs(dr);
        } else if (dir === "up") {
            primary = -dr;
            secondary = Math.abs(dc);
        } else {
            primary = dr;
            secondary = Math.abs(dc);
        }
        if (primary <= 0)
            continue;
        const score = primary + secondary * 2;
        if (score < bestScore) {
            best = key;
            bestScore = score;
        }
    }
    return best;
}

// Keys between a and b inclusive in fill order, for Shift selection.
function rangeBetween(positions, a, b, rows) {
    const order = orderedKeys(positions, rows);
    const ia = order.indexOf(a);
    const ib = order.indexOf(b);
    if (ia === -1 || ib === -1)
        return ib === -1 ? [] : [b];
    return order.slice(Math.min(ia, ib), Math.max(ia, ib) + 1);
}

// Keys whose cell rectangle intersects the given pixel rectangle.
function keysInRect(positions, rect, cellWidth, cellHeight, inset) {
    const out = [];
    for (const key in positions) {
        const p = positions[key];
        const x = p.col * cellWidth + inset;
        const y = p.row * cellHeight + inset;
        const w = cellWidth - inset * 2;
        const h = cellHeight - inset * 2;
        if (x < rect.x + rect.width && x + w > rect.x && y < rect.y + rect.height && y + h > rect.y)
            out.push(key);
    }
    return out;
}
