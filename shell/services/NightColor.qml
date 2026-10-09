pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Services

Singleton {
    id: root

    readonly property int currentTemperature: NightColorBridge.currentTemperature
    readonly property int dayTemperature: NightColorBridge.dayTemperature
    readonly property int nightTemperature: NightColorBridge.nightTemperature
    readonly property bool active: NightColorBridge.active
    readonly property bool available: NightColorBridge.available
    readonly property bool autoMode: NightColorBridge.autoMode

    function nightLightToast(message: string): void {
        if (GlobalConfig.utilities.toasts.nightLightChanged)
            Toaster.toast(qsTr("Night Light"), qsTr(message), "dark_mode");
    }

    function setDayTemperature(temp): void {
        if (temp !== undefined && temp !== null) {
            NightColorBridge.setDayTemperature(temp);
        }
    }

    function setNightTemperature(temp): void {
        if (temp !== undefined && temp !== null) {
            NightColorBridge.setNightTemperature(temp);
        }
    }

    function previewTemperature(temp): void {
        if (temp !== undefined && temp !== null) {
            NightColorBridge.previewTemperature(temp);
        }
    }

    function stopPreview(): void {
        NightColorBridge.stopPreview();
    }

    function toggleNightLight(): void {
        NightColorBridge.toggleNightLight();
    }

    function toggleAutoMode(): void {
        NightColorBridge.toggleAutoMode();
    }
}
