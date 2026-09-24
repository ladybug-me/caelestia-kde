pragma Singleton

import QtQuick

// Shared in-memory buffer for the password currently being typed in the
// greeter. The portrait and landscape password pills each bind to `password`
// so the entered text follows the active layout.
//
// Privacy invariants (do not regress):
// - The value lives ONLY for the current entry attempt. Every keystroke
//   restarts a short wipe timer, so an abandoned attempt never leaves the
//   secret sitting in the engine for the lifetime of the greeter; the value
//   is also wiped when a pill empties the field. The authenticator itself
//   always receives the password as a signal argument from the pill, never
//   from here.
// - Nothing here logs the value or writes it to any file. The only file the
//   lock screen ever writes is the wallpaper/theme config in kscreenlockerrc,
//   which never contains the password.
QtObject {
    id: sync

    property string password: ""

    // How long the value may survive after the last keystroke. Long enough
    // that slow typing and the submit -> respond hand-off never lose it
    // mid-attempt, short enough that a walked-away attempt does not linger.
    readonly property int wipeIntervalMs: 15000

    // The one sanctioned way to clear the buffer. Safe to call at any time;
    // the auth flow can also call it when an attempt completes.
    function wipe() {
        password = "";
    }

    onPasswordChanged: {
        // Every keystroke restarts the wipe timer; an emptied buffer stops it.
        if (password !== "")
            wipeTimer.restart();
        else
            wipeTimer.stop();
    }

    property Timer wipeTimer: Timer {
        interval: sync.wipeIntervalMs

        onTriggered: sync.wipe()
    }
}
