// SPDX-FileCopyrightText: 2026 0x0nYx
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Caelestia audio visualiser as a native Plasma 6 desktop applet (upstream
// issue #673: "Plasmoid for visualizer instead of quickshell"). The bars are
// rendered by the same C++ pieces the quickshell shell uses - CavaProvider
// (FFT + PipeWire capture) and VisualiserBars (the painted bar renderer) from
// the host-agnostic Caelestia QML plugin - so the look and the audio pipeline
// match the shell exactly while running inside plasmashell.
//
// How plasmashell finds the C++ plugin: no extra wiring is needed, because the
// shell's installer (scripts/08-build-shell.sh, write_shell_environment) already
// exports QML2_IMPORT_PATH with the plugin's module root
// (~/.local/lib/qt6/qml for a checkout install, /usr/lib/qt6/qml when packaged)
// through BOTH mechanisms a Plasma 6 session provides:
//   * ~/.config/environment.d/caelestia.conf - read by the systemd user
//     manager, which runs plasmashell as org.kde.plasmashell.service on the
//     default systemd startup.
//   * ~/.config/plasma-workspace/env/caelestia.sh - sourced by startplasma for
//     a session-started plasmashell.
// kscreenlocker_greet loads the same plugin through the same pair for the
// native lock screen, which is what proves the path works in KDE hosts.
//
// This file deliberately imports nothing Caelestia: the plugin may be absent
// (a build without libcava registers no CavaProvider). The visualiser itself
// lives in VisualiserContent.qml, loaded by the Loader below, so a missing
// plugin degrades to the placeholder message instead of failing the applet.

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // KConfigXT-backed configuration (contents/config/main.xml, edited through
    // contents/config/config.qml). Defaults mirror the quickshell visualiser:
    // 60 bars (GlobalConfig.services.visualiserBars), rounding/spacing
    // multipliers of 1 (Config.background.visualiser), a 200 ms settle
    // animation (Tokens.anim.durations.expressiveDefaultEffects).
    readonly property int barCount: Math.max(1, Plasmoid.configuration.barCount)
    readonly property real roundingScale: Math.min(5, Math.max(0, Plasmoid.configuration.rounding))
    readonly property real spacingScale: Math.min(5, Math.max(0, Plasmoid.configuration.spacing))
    readonly property int animationDuration: Math.max(0, Plasmoid.configuration.animationDuration)
    // The resource-saving point of this plasmoid (#673): while not running, the
    // CavaProvider is unref'd, which stops the cava analysis timer and tears
    // down the whole PipeWire capture stream (AudioCollector::stop). "Not
    // running" means the applet is not visible - its activity is not the
    // current one, the containment or the widget itself is hidden - or the
    // Plasma configuration dialog is open over the desktop.
    readonly property bool pauseWhenHidden: Plasmoid.configuration.pauseWhenHidden
    readonly property bool showUnavailableMessage: Plasmoid.configuration.showUnavailableMessage
    readonly property bool running: !pauseWhenHidden || (root.visible && !Plasmoid.userConfiguring)

    Plasmoid.title: i18n("Caelestia Visualiser")
    Plasmoid.toolTipSubText: i18n("Audio spectrum from the Caelestia cava provider")

    // A desktop applet starts around this size and scales its bars with
    // whatever size it is resized to.
    implicitWidth: Kirigami.Units.gridUnit * 20
    implicitHeight: Kirigami.Units.gridUnit * 8

    Loader {
        id: visualiser

        anchors.fill: parent
        visible: status === Loader.Ready
        source: "VisualiserContent.qml"

        onLoaded: {
            // The content is a plain Item with plain properties; the applet
            // configuration is read once, here, so VisualiserContent.qml needs
            // no plasmoid API at all.
            item.barCount = Qt.binding(() => root.barCount)
            item.roundingScale = Qt.binding(() => root.roundingScale)
            item.spacingScale = Qt.binding(() => root.spacingScale)
            item.animationDuration = Qt.binding(() => root.animationDuration)
            item.running = Qt.binding(() => root.running)
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("Caelestia: visualiser content failed to load:", errorString)
        }
    }

    Column {
        id: unavailable

        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing
        visible: root.showUnavailableMessage && visualiser.status === Loader.Error

        PlasmaComponents3.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            color: PlasmaCore.Theme.textColor
            font.weight: Font.Bold
            text: i18n("Caelestia Visualiser unavailable")
        }

        PlasmaComponents3.Label {
            color: PlasmaCore.Theme.disabledTextColor
            horizontalAlignment: Text.AlignHCenter
            text: i18n("The Caelestia plugin with the cava audio analyser is not loaded by plasmashell. Build the shell with libcava available and restart the Plasma session.")
            wrapMode: Text.WordWrap
            width: Math.min(root.width - Kirigami.Units.gridUnit * 2, implicitWidth)
        }
    }
}
