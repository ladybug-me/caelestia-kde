pragma Singleton
pragma ComponentBehavior: Bound

// Caelestia in-shell command gate — the execution boundary for the sidebar
// AI's state-changing tools.
//
// The settings tools have their validated gate (SettingsTools.qml: allow-list,
// preview, explicit confirm). This is the SAME gate shape for every other
// state-changing tool the sidebar's model can request: `caelestia_command`,
// `open_app`, `set_timer`. Nothing here executes anything — the gate only
// decides whether a request may run immediately (verified read-only
// allow-list) or must wait for the user's explicit approval on a preview
// card, and holds the pending payload until then. The caller executes; the
// gate never does. This closes the prompt-injection-to-execution path: a
// webpage's text can at worst produce a card the user ignores, never a
// silently-launched command.
//
// Allow-list provenance (verified 2026-09-26 against upstream
// src/bin/caelestia @ dev, read in full):
//   - `version` / `help` print and exit (cmd_version / usage bodies).
//   - `scheme list` / `scheme get` are the CLI usage's declared read forms
//     ("scheme <list|get|set> [...]  manage the color scheme"); `set` is the
//     write form and is NOT allow-listed. Only the bare read forms are
//     allow-listed — any extra argument falls back to confirmation.
//   - NOT allow-listed, each for a verified reason: `shell` (runs
//     `caelestia-shell-ipc start` on EVERY invocation, even for -s/-l),
//     `install` (runs the installer), `update` (updates and re-applies),
//     `wallpaper` (sets the wallpaper and derives the palette),
//     `screenshot` (spawns a capture), `record` (screen recording).
//
// One pending command at a time; a newer request supersedes an older
// unresolved one (which resolves as cancelled), mirroring SettingsTools.

import QtQuick
import Quickshell

Singleton {
    id: root

    // The payload of the request waiting for the user's Apply.
    property var pending: null

    // Verified read-only `caelestia` subcommands (see header for provenance).
    readonly property var caelestiaReadOnly: ["version", "help"]

    function isReadOnlyCaelestia(argv) {
        if (!argv || argv.length < 2 || String(argv[0]) !== "caelestia")
            return false;
        var sub = String(argv[1]);
        if (caelestiaReadOnly.indexOf(sub) !== -1)
            return true; // `caelestia version`, `caelestia help`
        if (sub === "scheme" && argv.length === 3) {
            // bare read forms only: `caelestia scheme list`, `caelestia scheme get`
            var mode = String(argv[2]);
            return mode === "list" || mode === "get";
        }
        return false;
    }

    // argv: the exact array that would run (["caelestia", sub, ...]).
    // Returns {ok, needsConfirm?, preview?, reason?}; the preview carries
    // what the confirmation card shows — the command itself, verbatim.
    function requestCaelestia(argv) {
        if (!Array.isArray(argv) || argv.length < 2) {
            return { ok: false, reason: "caelestia_command needs a subcommand" };
        }
        if (isReadOnlyCaelestia(argv)) {
            return { ok: true, needsConfirm: false }; // verified read-only: runs
        }
        pending = { kind: "caelestia", argv: argv.slice() };
        return { ok: true, needsConfirm: true, preview: {
            kind: "caelestia",
            label: qsTr("Run a caelestia command"),
            lines: [argv.join(" ")]
        } };
    }

    function requestOpenApp(appName) {
        var name = String(appName || "").trim();
        if (!name) {
            return { ok: false, reason: "open_app needs an app name" };
        }
        pending = { kind: "open_app", app: name };
        return { ok: true, needsConfirm: true, preview: {
            kind: "open_app",
            label: qsTr("Open an application"),
            lines: [name]
        } };
    }

    function requestTimer(seconds, message) {
        var secs = Number(seconds) || 0;
        if (secs <= 0) {
            return { ok: false, reason: "set_timer needs a positive number of seconds" };
        }
        pending = { kind: "set_timer", seconds: secs,
                    message: String(message || "Timer finished") };
        return { ok: true, needsConfirm: true, preview: {
            kind: "set_timer",
            label: qsTr("Set a timer"),
            lines: [Math.round(secs) + " s — " + String(message || "Timer finished")]
        } };
    }

    // The card's Apply: hands the payload back for the CALLER to execute.
    // The gate itself still executes nothing.
    function confirm() {
        if (!pending)
            return { ok: false, reason: "no pending command to confirm" };
        var p = pending;
        pending = null;
        return { ok: true, kind: p.kind, payload: p };
    }

    // The card's Cancel (or supersede): nothing runs, nothing is kept.
    function cancel() {
        if (!pending)
            return { ok: false, reason: "no pending command to cancel" };
        pending = null;
        return { ok: true, applied: false };
    }
}
