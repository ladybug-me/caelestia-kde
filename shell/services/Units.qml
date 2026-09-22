pragma Singleton

import QtQuick
import Caelestia.Config

QtObject {
    id: root

    // Converts a temperature in Celsius to the given TemperatureUnit
    function toTemperature(celsius: real, unit: int): real {
        if (Number(unit) === TemperatureUnit.Fahrenheit)
            return celsius * 9 / 5 + 32;
        if (Number(unit) === TemperatureUnit.Kelvin)
            return celsius + 273.15;
        return celsius;
    }

    // Formats an already converted temperature with the given TemperatureUnit's suffix
    function formatTemp(value: var, unit: int, compact = false): string {
        if (compact)
            return Number(unit) === TemperatureUnit.Kelvin ? String(value) : qsTr("%1°", "temperature").arg(value);

        if (Number(unit) === TemperatureUnit.Fahrenheit)
            return qsTr("%1°F", "temperature").arg(value);
        if (Number(unit) === TemperatureUnit.Kelvin)
            return qsTr("%1 K", "temperature").arg(value);
        return qsTr("%1°C", "temperature").arg(value);
    }

    // Converts and formats a sensor temperature in Celsius using the configured sensor units
    function formatSensorTemp(celsius: real): string {
        const unit = GlobalConfig.services.sensorUnits;
        return root.formatTemp(Math.round(root.toTemperature(celsius, unit)), unit);
    }

    // Formats an already scaled value with the given data unit suffix
    function withDataUnit(value: var, unit: string): string {
        const formats = {
            "B": qsTr("%1 B", "data unit"),
            "KB": qsTr("%1 KB", "data unit"),
            "MB": qsTr("%1 MB", "data unit"),
            "GB": qsTr("%1 GB", "data unit"),
            "TB": qsTr("%1 TB", "data unit"),
            "KiB": qsTr("%1 KiB", "data unit"),
            "MiB": qsTr("%1 MiB", "data unit"),
            "GiB": qsTr("%1 GiB", "data unit"),
            "TiB": qsTr("%1 TiB", "data unit"),
            "B/s": qsTr("%1 B/s", "data unit"),
            "KB/s": qsTr("%1 KB/s", "data unit"),
            "MB/s": qsTr("%1 MB/s", "data unit"),
            "GB/s": qsTr("%1 GB/s", "data unit"),
            "TB/s": qsTr("%1 TB/s", "data unit"),
            "KiB/s": qsTr("%1 KiB/s", "data unit"),
            "MiB/s": qsTr("%1 MiB/s", "data unit"),
            "GiB/s": qsTr("%1 GiB/s", "data unit"),
            "TiB/s": qsTr("%1 TiB/s", "data unit")
        };
        return (formats[unit] ?? qsTr("%1 %2", "value and data unit").arg(value).arg(unit)).arg(value);
    }

    function _scaleBytes(bytes: real, refBytes: real): var {
        const binary = Number(GlobalConfig.services.dataUnits) === DataUnit.Binary;
        const units = binary ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["B", "KB", "MB", "GB", "TB"];
        const k = binary ? 1024 : 1000;

        let value = isFinite(bytes) && bytes > 0 ? bytes : 0;
        let ref = isFinite(refBytes) && refBytes > 0 ? refBytes : 0;
        let i = 0;
        while (ref >= k && i < units.length - 1) {
            value /= k;
            ref /= k;
            i++;
        }

        return {
            value,
            unit: units[i]
        };
    }

    // Scales and formats a raw byte count
    function formatBytes(bytes: real, rate = false): string {
        const s = root._scaleBytes(bytes, bytes);
        return root.withDataUnit(s.value.toFixed(s.value < 10 && s.unit !== "B" ? 1 : 0), s.unit + (rate ? "/s" : ""));
    }

    // Formats a used/total pair given in KiB, both scaled to the total's magnitude
    function formatKibUsage(usedKib: real, totalKib: real): string {
        const refBytes = totalKib * 1024;
        const used = root._scaleBytes(usedKib * 1024, refBytes);
        const total = root._scaleBytes(refBytes, refBytes);
        const usedText = root.withDataUnit(+used.value.toFixed(1), used.unit);
        const totalText = root.withDataUnit(+total.value.toFixed(1), total.unit);
        return qsTr("%1 / %2", "used / total amount").arg(usedText).arg(totalText);
    }

    // Formats a duration in seconds into H:MM:SS or M:SS
    function formatDuration(seconds: int, alwaysHours = false): string {
        if (seconds < 0)
            return "-1:-1";

        const hours = Math.floor(seconds / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        const secs = Math.floor(seconds % 60).toString().padStart(2, "0");

        if (hours > 0 || alwaysHours)
            return `${hours}:${mins.toString().padStart(2, "0")}:${secs}`;
        return `${mins}:${secs}`;
    }

    // Formats a unit fraction (e.g. 0.75) into a percentage string (e.g. "75%")
    function formatPercent(value: real): string {
        return `${Math.round(value * 100)}%`;
    }

    // Formats a duration in seconds into short human-readable units (e.g. "2d 4h 15m", "4h 15m", "15m")
    function formatDurationShort(seconds: int, fallback = ""): string {
        if (seconds <= 0)
            return fallback;

        const day = Math.floor(seconds / 86400);
        const hr = Math.floor(seconds / 3600) % 24;
        const min = Math.floor(seconds / 60) % 60;

        let comps = [];
        if (day > 0) comps.push(`${day}d`);
        if (hr > 0) comps.push(`${hr}h`);
        if (min > 0) comps.push(`${min}m`);

        return comps.join(" ") || fallback;
    }

    // Formats system uptime in seconds into a natural language string (e.g. "2 days, 4 hours, 15 minutes")
    function formatUptime(seconds: int): string {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        let str = "";
        if (days > 0)
            str += `${days} day${days === 1 ? "" : "s"}`;
        if (hours > 0)
            str += `${str ? ", " : ""}${hours} hour${hours === 1 ? "" : "s"}`;
        if (minutes > 0 || !str)
            str += `${str ? ", " : ""}${minutes} minute${minutes === 1 ? "" : "s"}`;
        return str;
    }
}
