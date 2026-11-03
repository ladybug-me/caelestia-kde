pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

/// The standard corner rounding applied to shell panels and surfaces, linked to the
/// corner rounding tokens.
Singleton {
    readonly property real panelRounding: Config.appearance.rounding.extraLarge
}
