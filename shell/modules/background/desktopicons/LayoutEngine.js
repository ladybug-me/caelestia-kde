.pragma library

// Grid layout helpers for the desktop icons. Positions are plain objects
// mapping an item key to its top-left { col, row }; spans optionally map a key
// to its { w, h } in cells (icons are 1x1). Nothing here touches QML state.

function cellId(col, row) {
    return col + "," + row;
}

function spanOf(spans, key) {
    const s = spans ? spans[key] : null;
    return s ? { w: Math.max(1, s.w | 0), h: Math.max(1, s.h | 0) } : { w: 1, h: 1 };
}

function inGrid(pos, cols, rows, span) {
    const s = span ?? { w: 1, h: 1 };
    return pos.col >= 0 && pos.row >= 0 && pos.col + s.w <= cols && pos.row + s.h <= rows;
}

function markRect(occ, pos, span, key) {
    for (let c = 0; c < span.w; c++)
        for (let r = 0; r < span.h; r++)
            occ[cellId(pos.col + c, pos.row + r)] = key;
}

function occupancy(positions, excludeKeys, spans) {
    const occ = {};
    for (const key in positions) {
        if (excludeKeys && excludeKeys.indexOf(key) !== -1)
            continue;
        markRect(occ, positions[key], spanOf(spans, key), key);
    }
    return occ;
}

function rectFree(occ, pos, span) {
    for (let c = 0; c < span.w; c++)
        for (let r = 0; r < span.h; r++)
            if (cellId(pos.col + c, pos.row + r) in occ)
                return false;
    return true;
}

// Column-major index, the order icons fill the desktop in.
function orderIndex(pos, rows) {
    return pos.col * rows + pos.row;
}

function orderedKeys(positions, rows) {
    return Object.keys(positions).sort((a, b) => orderIndex(positions[a], rows) - orderIndex(positions[b], rows));
}

// First free place in column-major order. Past a full grid, keeps counting
// into the columns beyond the right edge rather than stacking items.
function firstFree(occ, cols, rows, span) {
    const s = span ?? { w: 1, h: 1 };
    const h = Math.min(s.h, rows);
    for (let i = 0; i < 100000; i++) {
        const pos = { col: Math.floor(i / rows), row: i % rows };
        if (pos.row + h > rows)
            continue;
        if (rectFree(occ, pos, { w: s.w, h }))
            return pos;
    }
    return { col: cols, row: 0 };
}

// Free place closest to (col, row), ties broken towards the fill order.
function nearestFree(occ, col, row, cols, rows, span) {
    const s = span ?? { w: 1, h: 1 };
    let best = null;
    let bestDist = Infinity;
    for (let c = 0; c + s.w <= cols; c++) {
        for (let r = 0; r + s.h <= rows; r++) {
            const d = (c - col) * (c - col) + (r - row) * (r - row);
            if (d > bestDist)
                continue;
            const pos = { col: c, row: r };
            if (d === bestDist && orderIndex(pos, rows) >= orderIndex(best, rows))
                continue;
            if (!rectFree(occ, pos, s))
                continue;
            best = pos;
            bestDist = d;
        }
    }
    return best ?? firstFree(occ, cols, rows, s);
}

function copyPositions(positions) {
    const out = {};
    for (const key in positions)
        out[key] = { col: positions[key].col, row: positions[key].row };
    return out;
}

function rectsOverlap(a, sa, b, sb) {
    return a.col < b.col + sb.w && b.col < a.col + sa.w && a.row < b.row + sb.h && b.row < a.row + sa.h;
}

// Moves the keys in `moving` so that `anchor` lands on `target`, keeping their
// relative placement. The shift is clamped so every moved item stays on the
// grid. Items overlapping a destination step aside to the free place nearest
// to where they were. `spans` may give new sizes, which also makes this the
// resize operation.
function planMove(positions, moving, anchor, target, cols, rows, spans) {
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
        const s = spanOf(spans, key);
        dc = Math.max(dc, -p.col);
        dr = Math.max(dr, -p.row);
        dc = Math.min(dc, Math.max(-p.col, cols - s.w - p.col));
        dr = Math.min(dr, Math.max(-p.row, rows - s.h - p.row));
    }

    const occ = {};
    const moved = [];
    for (const key of moving) {
        const p = positions[key];
        if (!p)
            continue;
        out[key] = { col: p.col + dc, row: p.row + dr };
        markRect(occ, out[key], spanOf(spans, key), key);
        moved.push(key);
    }

    // Everyone that is not moving keeps their place unless a mover covers it.
    const displaced = [];
    for (const key of orderedKeys(positions, rows)) {
        if (moving.indexOf(key) !== -1)
            continue;
        const s = spanOf(spans, key);
        if (moved.some(m => rectsOverlap(positions[key], s, out[m], spanOf(spans, m))))
            displaced.push(key);
        else
            markRect(occ, positions[key], s, key);
    }
    for (const key of displaced) {
        const p = positions[key];
        const s = spanOf(spans, key);
        const cell = nearestFree(occ, p.col, p.row, cols, rows, s);
        out[key] = cell;
        markRect(occ, cell, s, key);
    }
    return out;
}

// Packs the keys in column-major order, each into the first place it fits.
function compact(keys, rows, spans) {
    const out = {};
    const occ = {};
    for (const key of keys) {
        const s = spanOf(spans, key);
        const pos = firstFree(occ, Infinity, rows, s);
        out[key] = pos;
        markRect(occ, pos, s, key);
    }
    return out;
}

// Auto-arrange drop: pulls the moving keys out of the order and inserts them
// where `target` is, then packs everything again.
function planInsert(positions, moving, target, rows, spans) {
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
    return compact(rest, rows, spans);
}

function overflowCount(positions, cols, rows, spans) {
    let n = 0;
    for (const key in positions)
        if (!inGrid(positions[key], cols, rows, spanOf(spans, key)))
            n++;
    return n;
}

// Pulls items that fell off a shrunken grid, or overlap, back onto it. When the
// gaps left between the items that stayed are too scattered for the rest, packs
// everything again in fill order instead, which keeps more of it on screen.
function fitIntoGrid(positions, cols, rows, spans) {
    const kept = keepAndPlace(positions, cols, rows, spans);
    const keptOver = overflowCount(kept, cols, rows, spans);
    if (keptOver === 0)
        return kept;
    const packed = compact(orderedKeys(positions, rows), rows, spans);
    return overflowCount(packed, cols, rows, spans) < keptOver ? packed : kept;
}

function keepAndPlace(positions, cols, rows, spans) {
    const out = {};
    const outside = [];
    const occ = {};
    for (const key of orderedKeys(positions, rows)) {
        const p = positions[key];
        const s = spanOf(spans, key);
        if (inGrid(p, cols, rows, s) && rectFree(occ, p, s)) {
            out[key] = { col: p.col, row: p.row };
            markRect(occ, p, s, key);
        } else {
            outside.push(key);
        }
    }
    for (const key of outside) {
        const p = positions[key];
        const s = spanOf(spans, key);
        const cell = nearestFree(occ, Math.min(p.col, cols - s.w), Math.min(p.row, rows - s.h), cols, rows, s);
        out[key] = cell;
        markRect(occ, cell, s, key);
    }
    return out;
}

// Stable sort for "Sort by". Items are { key, name, kind, type, modified, size };
// widgets, then folders and groups come first, like Plasma's "folders first".
function sortItems(items, sortKey) {
    const rank = it => it.kind === "widget" ? 0 : it.kind === "dir" || it.kind === "group" ? 1 : 2;
    const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
    const cmp = {
        name: byName,
        type: (a, b) => (a.type || "").localeCompare(b.type || "") || byName(a, b),
        modified: (a, b) => (b.modified || 0) - (a.modified || 0) || byName(a, b),
        size: (a, b) => (b.size || 0) - (a.size || 0) || byName(a, b)
    }[sortKey] ?? byName;
    return items.slice().sort((a, b) => rank(a) - rank(b) || cmp(a, b));
}

// Where keyboard focus goes from `fromKey` for an arrow key. Measures from
// the centre of each item, preferring the closest one along the pressed axis
// and then the one closest to the same line.
function navigate(positions, fromKey, dir, spans) {
    const from = positions[fromKey];
    if (!from)
        return null;
    const fs = spanOf(spans, fromKey);
    const fx = from.col + fs.w / 2;
    const fy = from.row + fs.h / 2;
    let best = null;
    let bestScore = Infinity;
    for (const key in positions) {
        if (key === fromKey)
            continue;
        const p = positions[key];
        const s = spanOf(spans, key);
        const dc = p.col + s.w / 2 - fx;
        const dr = p.row + s.h / 2 - fy;
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

// Keys whose rectangle intersects the given pixel rectangle.
function keysInRect(positions, rect, cellWidth, cellHeight, inset, spans) {
    const out = [];
    for (const key in positions) {
        const p = positions[key];
        const s = spanOf(spans, key);
        const x = p.col * cellWidth + inset;
        const y = p.row * cellHeight + inset;
        const w = s.w * cellWidth - inset * 2;
        const h = s.h * cellHeight - inset * 2;
        if (x < rect.x + rect.width && x + w > rect.x && y < rect.y + rect.height && y + h > rect.y)
            out.push(key);
    }
    return out;
}

// Key covering the cell, if any.
function occupantAt(positions, col, row, exclude, spans) {
    for (const key in positions) {
        if (exclude && exclude.indexOf(key) !== -1)
            continue;
        const p = positions[key];
        const s = spanOf(spans, key);
        if (col >= p.col && col < p.col + s.w && row >= p.row && row < p.row + s.h)
            return key;
    }
    return "";
}
