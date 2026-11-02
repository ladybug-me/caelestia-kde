.pragma library

// What a notification search looks at. The three fields arrive already flattened by
// NotifData, so this is a pure predicate: no list, no config, nothing a test cannot run.
function matches(appName, summary, body, query) {
    var needle = String(query ?? "").trim().toLowerCase();
    if (needle === "")
        return true;

    return [appName, summary, body].some(function (field) {
        return String(field ?? "").toLowerCase().includes(needle);
    });
}
