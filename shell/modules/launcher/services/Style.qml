pragma Singleton

import QtQuick
import QtCore

QtObject {
    id: root

    /// "classic" keeps the launcher as it shipped, "modern" is the profile
    /// picture header. Nexus writes it and the launcher reads it live.
    readonly property string launcherStyle: settings.launcherStyle

    property Settings settings: Settings {
        property string launcherStyle: "classic"

        category: "Launcher"
    }

    function setLauncherStyle(value: string): void {
        settings.launcherStyle = value;
    }
}
