.pragma library

// Reads a duration the way someone types one: `25` and `25m` are minutes, `90s` is
// seconds, and `1h30` is an hour and a half. Returns 0 when there is no number in it.
function parse(text) {
    var value = String(text ?? "").trim().toLowerCase();
    if (value === "")
        return 0;

    var seconds = 0;
    var found = false;
    var pattern = /(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)?/g;
    var match;
    while ((match = pattern.exec(value)) !== null) {
        var amount = Number(match[1]);
        if (!isFinite(amount))
            continue;

        found = true;
        var unit = match[2] ?? "";
        if (unit.startsWith("h"))
            seconds += amount * 3600;
        else if (unit.startsWith("s"))
            seconds += amount;
        else
            seconds += amount * 60;
    }

    return found ? Math.round(seconds) : 0;
}
