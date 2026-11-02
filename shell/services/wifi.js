.pragma library

// The link's own signal, as the wireless driver reports it.
//
// NetworkManager publishes the strength of the *associated* access point as a snapshot
// taken when that BSS was last scanned, and on a 6 GHz link that snapshot reads far lower
// than the link really is: -45 dBm at the router was published as 73 %, which is a
// three-bar icon next to a router. The driver knows better, and `iw` will say so.

/// The signal in dBm from `iw dev <interface> link`, or null when there is no link. A
/// multi-link (MLO) connection prints one `signal:` line for the aggregate.
function signalOf(iwLinkOutput) {
    var match = /^[\t ]*signal:[\t ]*(-?\d+(?:\.\d+)?)[\t ]*dBm/m.exec(String(iwLinkOutput ?? ""));
    return match ? Number(match[1]) : null;
}

/// dBm to the 0-100 scale the network icons are bucketed in: -50 dBm and better is a full
/// signal, -100 dBm and worse is none, and it is linear in between. That is the classic
/// wireless-extension mapping, so the number means what the old icon meant.
function qualityOf(dbm) {
    var value = Number(dbm);
    if (dbm === null || dbm === undefined || !isFinite(value))
        return null;

    return Math.max(0, Math.min(100, Math.round(2 * (value + 100))));
}

/// The whole reading in one step: the link's quality, or -1 when there was nothing to
/// read. One number and one "unknown", rather than a null a caller has to remember to
/// handle before it becomes a zero that looks like a dead link.
function qualityFromLink(iwLinkOutput) {
    var quality = qualityOf(signalOf(iwLinkOutput));
    return quality === null ? -1 : quality;
}
