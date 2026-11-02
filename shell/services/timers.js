.pragma library

// Splits the running timers into the ones that have ended at `now` and the ones that are
// still going. Pure, and given the clock as a value: the tick asks this once and then
// acts, rather than reading the clock again inside a predicate per timer.
function split(list, now) {
    var at = Number(now);
    var due = [];
    var running = [];
    for (var i = 0; i < list.length; i++) {
        var timer = list[i];
        if (Number(timer.ends) <= at)
            due.push(timer);
        else
            running.push(timer);
    }

    return { due: due, running: running };
}
