pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

// Single definition of the Nexus secondary text size. Every secondary
// text across Nexus points here, so future size tweaks are one line.
Singleton {
    readonly property font secondaryFont: Tokens.font.label.builders.small.size(10).build()
}
