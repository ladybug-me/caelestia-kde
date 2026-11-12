pragma Singleton

import QtQuick
import QtCore

QtObject {
    id: root

    /// "classic" keeps the launcher as it shipped, "modern" is the profile
    /// picture header. Nexus writes it and the launcher reads it live.
    readonly property string launcherStyle: settings.launcherStyle

    /// Absolute path of an image to use as the launcher avatar. Empty means
    /// the system profile picture (~/.face) is used. The file itself is never
    /// touched, so the rest of the desktop keeps its own picture.
    readonly property string avatarPath: settings.avatarPath

    property Settings settings: Settings {
        property string launcherStyle: "classic"
        property string avatarPath: ""

        category: "Launcher"
    }

    function setLauncherStyle(value: string): void {
        settings.launcherStyle = value;
    }

    function setAvatarPath(value: string): void {
        settings.avatarPath = value;
    }
}
