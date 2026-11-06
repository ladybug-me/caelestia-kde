pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    function getVolumeIcon(value: real, muted: bool): string {
        return Icons.getVolumeIcon(value, muted);
    }

    function getMicIcon(value: real, muted: bool): string {
        return Icons.getMicVolumeIcon(value, muted);
    }

    function getBrightnessIcon(value: real): string {
        return `brightness_${(Math.round(value * 6) + 1)}`;
    }

    function getIcon(type: string, value: real, muted: bool): string {
        if (type === "volume")
            return getVolumeIcon(value, muted);
        if (type === "mic")
            return getMicIcon(value, muted);
        if (type === "brightness")
            return getBrightnessIcon(value);
        return "";
    }

    function getTitle(type: string): string {
        if (type === "volume")
            return qsTr("Volume");
        if (type === "mic")
            return qsTr("Microphone");
        if (type === "brightness")
            return qsTr("Brightness");
        return "";
    }

    function isEnabled(type: string): bool {
        if (type === "volume")
            return GlobalConfig.osd.enableVolume;
        if (type === "mic")
            return GlobalConfig.osd.enableMicrophone;
        if (type === "brightness")
            return GlobalConfig.osd.enableBrightness;
        return false;
    }
}

