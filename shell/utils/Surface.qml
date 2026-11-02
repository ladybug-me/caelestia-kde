pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

/// The one number that keeps nested surfaces concentric: a panel sits inside the window
/// frame, so its corner radius is the frame's radius less the frame's thickness. Both the
/// panel background and the blur mask behind it read this, so neither can drift from the
/// frame when `border.rounding` changes.
Singleton {
    readonly property real panelRounding: Math.max(0, Config.border.rounding - Config.border.thickness)
}
