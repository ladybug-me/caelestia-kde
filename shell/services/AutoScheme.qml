pragma Singleton

import "../utils/scripts/solartime.js" as Solar
import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

/// Switches the colour scheme between light and dark on a schedule, either at
/// fixed times or at local sunrise and sunset.
///
/// The check is driven by the ticking clock rather than a one-shot timer armed
/// for the next boundary, because a timer set eight hours ahead does not
/// survive a suspend/resume or a system clock change.
Singleton {
    id: root

    readonly property bool enabled: GlobalConfig.services.autoSchemeEnabled
    readonly property bool solar: GlobalConfig.services.autoSchemeMode === "solar"

    /// Reuses the coordinates already configured or auto-detected for the
    /// weather service, so this needs no location setting of its own.
    readonly property var coords: Solar.parseCoords(GlobalConfig.services.weatherLocation || Weather.loc)

    /// The last mode this service applied, so a manual switch is not undone on
    /// the next tick — it stands until the next real boundary.
    property string lastApplied: ""

    /// The two boundaries for the given moment, as minutes since local
    /// midnight. Falls back to the fixed times whenever solar times are
    /// unavailable, so enabling this without a location still does something
    /// sensible.
    function boundariesFor(date: date): var {
        if (root.solar && root.coords) {
            const times = Solar.solarTimes(date, root.coords.lat, root.coords.lon);
            if (times)
                return {
                    light: times.sunrise,
                    dark: times.sunset
                };
        }

        const light = Solar.parseTime(GlobalConfig.services.autoSchemeLightTime);
        const dark = Solar.parseTime(GlobalConfig.services.autoSchemeDarkTime);
        if (light < 0 || dark < 0 || light === dark)
            return null;
        return {
            light: light,
            dark: dark
        };
    }

    /// `force` applies the mode even when this service did not choose the
    /// current one, which is what startup and the enable toggle want.
    function apply(force: bool): void {
        if (!root.enabled)
            return;

        const now = Time.date;
        const bounds = root.boundariesFor(now);
        if (!bounds)
            return;

        const minutes = now.getHours() * 60 + now.getMinutes();
        const target = Solar.isLightAt(minutes, bounds.light, bounds.dark) ? "light" : "dark";

        // Only act on a boundary crossing. Between boundaries a manual switch
        // is left alone rather than being reverted a minute later.
        if (!force && target === root.lastApplied)
            return;

        root.lastApplied = target;

        if ((target === "light") !== Colours.light)
            Colours.setMode(target);
    }

    onEnabledChanged: {
        if (root.enabled)
            root.apply(true);
        else
            root.lastApplied = "";
    }

    Component.onCompleted: root.apply(true)

    Connections {
        // Minute precision is plenty, and keeps this off the per-second tick.
        function onMinutesChanged(): void {
            root.apply(false);
        }

        target: Time
        enabled: root.enabled
    }

    Connections {
        function onAutoSchemeModeChanged(): void { root.apply(true); }

        function onAutoSchemeLightTimeChanged(): void { root.apply(true); }

        function onAutoSchemeDarkTimeChanged(): void { root.apply(true); }

        function onWeatherLocationChanged(): void { root.apply(true); }

        target: GlobalConfig.services
        enabled: root.enabled
    }

    Connections {
        function onLocChanged(): void { root.apply(true); }

        target: Weather
        enabled: root.enabled
    }
}
