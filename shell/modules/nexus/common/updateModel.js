.pragma library

// The update history as data: which commit or release is which, which of them are
// worth reading, and how many a collapsed list keeps. Everything here is pure, so
// the page, the timeline and the tests all agree on one answer.

var internalTypes = ["refactor", "style", "docs", "test", "build", "ci", "chore"];

function normalizeVersion(version) {
    return (version || "").replace(/^v/i, "");
}

function commitTypeName(subject) {
    var match = /^(\w+)(\([^)]*\))?!?:\s*/.exec(subject || "");
    return match ? match[1].toLowerCase() : "";
}

function strippedSubject(subject) {
    var stripped = (subject || "").replace(/^\w+(\([^)]*\))?!?:\s*/, "");
    return stripped === "" ? (subject || "") : stripped;
}

function mergeSubject(subject) {
    var match = /^Merge pull request #(\d+) from [^/]+\/(.+)$/.exec(subject || "");
    return match ? "#" + match[1] + " · " + match[2] : (subject || "");
}

// Every field is always present, so no caller needs a guard or a fallback for a
// field that happens to be missing in one of the two modes.
function entry(fields) {
    return {
        id: fields.id || "",
        label: fields.label || "",
        state: fields.state,
        title: fields.title || "",
        type: fields.type || "",
        subject: fields.subject || "",
        author: fields.author || "",
        date: fields.date || "",
        details: fields.details || "",
        url: fields.url || "",
        isRelease: !!fields.isRelease,
        isMerge: !!fields.isMerge
    };
}

function releaseEntries(versions, currentVersion, commits) {
    const bodies = {};
    for (let c = 0; c < commits.length; c++) {
        if (commits[c].details)
            bodies[normalizeVersion(commits[c].subject)] = commits[c].details;
    }

    // -2 means the installed version is unknown, -1 that it is not in the list at
    // all: the first can never be an update, the second trusts the newest tag.
    var current = normalizeVersion(currentVersion);
    var index = currentVersion === "unknown" ? -2 : -1;
    for (var i = 0; index !== -2 && i < versions.length; i++) {
        if (normalizeVersion(versions[i]) === current) {
            index = i;
            break;
        }
    }

    var entries = [];
    for (var v = 0; v < versions.length; v++) {
        var state;
        if (index === -2)
            state = "past";
        else if (index === -1)
            state = v === 0 ? "current" : "past";
        else if (v < index)
            state = "available";
        else if (v === index)
            state = "current";
        else
            state = "past";

        var label = normalizeVersion(versions[v]);
        entries.push(entry({
            id: versions[v],
            label: label,
            state: state,
            title: label,
            details: bodies[normalizeVersion(versions[v])] || "",
            url: "https://github.com/caelestia-kde/caelestia/releases/tag/" + versions[v],
            isRelease: true
        }));
    }
    return entries;
}

function commitEntries(commits, installedHash) {
    var index = -1;
    if (installedHash !== "") {
        for (var i = 0; i < commits.length; i++) {
            if (commits[i].fullHash === installedHash || commits[i].hash === installedHash) {
                index = i;
                break;
            }
        }
    }

    var entries = [];
    for (var c = 0; c < commits.length; c++) {
        var commit = commits[c];
        var state;
        if (installedHash === "")
            state = c === 0 ? "current" : "past";
        else if (index === -1)
            state = "available";
        else if (c < index)
            state = "available";
        else if (c === index)
            state = "current";
        else
            state = "past";

        var isMerge = !!commit.isMerge;
        entries.push(entry({
            id: commit.hash,
            label: commit.hash,
            state: state,
            title: isMerge ? mergeSubject(commit.subject) : strippedSubject(commit.subject),
            type: commitTypeName(commit.subject),
            subject: commit.subject,
            author: commit.author,
            date: commit.date,
            isMerge: isMerge
        }));
    }
    return entries;
}

function deriveEntries(input) {
    if (input.versionSummaryMode && input.availableVersions.length > 0)
        return releaseEntries(input.availableVersions, input.currentVersion, input.commits || []);
    return commitEntries(input.commits || [], input.installedCommitHash || "");
}

// Merges and housekeeping commits are developer bookkeeping. They stay out of the
// release-level story unless the reader asks - except the version installed now,
// which is always how the list marks where the reader is.
function isInternal(item) {
    if (!item || item.isRelease || item.state === "current")
        return false;
    if (item.isMerge)
        return true;
    return internalTypes.indexOf(item.type) >= 0;
}

function readableEntries(entries, includeInternal) {
    if (includeInternal)
        return entries;
    return entries.filter(function(item) {
        return !isInternal(item);
    });
}

// Development moves several times a day, so a collapsed dev list opens on the two
// ends of the gap - the commit installed and the newest one. Releases are few, so
// they keep a short list instead.
function collapsedLimit(isCommitList, state, perGroup) {
    if (!isCommitList)
        return perGroup;
    return state === "past" ? 0 : 1;
}

function isCommitList(entries) {
    for (var i = 0; i < entries.length; i++) {
        if (!entries[i].isRelease && (entries[i].author || entries[i].subject))
            return true;
    }
    return false;
}

// Everything a list needs to decide what to show: the rows it may render, how many
// the cap is holding back, and how many internal commits are hidden.
function disclosure(entries, expanded, includeInternal, perGroup) {
    var readable = readableEntries(entries, includeInternal);
    var commitList = isCommitList(entries);
    var shown = [];
    var hidden = 0;
    var capped = false;
    var states = ["available", "current", "past"];

    for (var s = 0; s < states.length; s++) {
        var state = states[s];
        var group = readable.filter(function(item) {
            return item.state === state;
        });
        var cap = collapsedLimit(commitList, state, perGroup);
        if (group.length > cap)
            capped = true;
        var limit = expanded ? group.length : Math.min(group.length, cap);
        hidden += group.length - limit;
        shown = shown.concat(group.slice(0, limit));
    }

    var internalCount = 0;
    for (var i = 0; i < entries.length; i++) {
        if (isInternal(entries[i]))
            internalCount++;
    }

    return {
        entries: shown,
        hiddenByCap: hidden,
        capped: capped,
        internalCount: internalCount,
        isCommitList: commitList
    };
}

// What the page previews: the entry the reader picked, otherwise the newest release
// the check found. Both the notes and their link come from here so they cannot
// describe different versions.
function previewEntry(entries, selectedId) {
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === selectedId && entries[i].id !== "")
            return entries[i];
    }
    for (var a = 0; a < entries.length; a++) {
        if (entries[a].state === "available" && entries[a].isRelease)
            return entries[a];
    }
    return null;
}

function entryById(entries, id) {
    if (id === "")
        return null;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === id)
            return entries[i];
    }
    return null;
}

// Release bodies arrive as markdown bullets with links; this keeps the bullet and
// drops the link target so the card reads as a list rather than as markup.
function formatNotes(body, maxLines) {
    var limit = maxLines === undefined ? 12 : maxLines;
    if (!body || body === "")
        return "";

    var lines = body.split("\n");
    var out = [];
    for (var i = 0; i < lines.length && out.length < limit; i++) {
        var line = lines[i].trim();
        if (line === "" || line.charAt(0) === "#")
            continue;
        line = line.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1");
        line = line.replace(/^[*-]\s+/, "• ");
        out.push(line);
    }
    return out.join("\n");
}
