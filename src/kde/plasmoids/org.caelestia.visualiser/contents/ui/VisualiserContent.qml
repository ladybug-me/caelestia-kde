// SPDX-FileCopyrightText: 2026 0x0nYx
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The visualiser itself, isolated from the applet plumbing in main.qml so the
// applet root keeps loading when this file cannot: the Caelestia C++ plugin is
// only importable where it was installed (QML2_IMPORT_PATH, see main.qml), and
// a build without libcava registers no CavaProvider at all. main.qml hands the
// KConfigXT values over as plain properties; nothing here talks to the
// plasmoid API.
//
// Rendering is the plugin's VisualiserBars - the same QQuickPaintedItem the
// quickshell visualiser uses - fed by the plugin's CavaProvider (PipeWire
// capture + cava FFT, monstercat-smoothed). Nothing visual is reimplemented.

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import Caelestia.Services
import Caelestia.Components

Item {
    id: root

    // Set by main.qml (bound in the Loader's onLoaded). Defaults mirror the
    // quickshell visualiser's tokens for a standalone load.
    property int barCount: 60
    property real roundingScale: 1
    property real spacingScale: 1
    property int animationDuration: 200
    property bool running: true

    // No hardcoded colours. The bars start on the Plasma theme - which the
    // Caelestia colour pipeline already drives through plasma-apply-colorscheme
    // - and switch to the same M3 pair the quickshell visualiser uses
    // (m3primary -> m3inversePrimary at 70% alpha) once the scheme state has
    // been read below.
    property color primaryColor: Qt.alpha(PlasmaCore.Theme.highlightColor, 0.7)
    property color secondaryColor: Qt.alpha(PlasmaCore.Theme.textColor, 0.7)

    // Same state file the lock screen greeter and the shell's Colours
    // singleton read; the colour pipeline rewrites it on every scheme change.
    readonly property string schemeCommand: "cat ~/.local/state/caelestia/scheme.json 2>/dev/null"

    // Rounding 12 and spacing 4 are Tokens.rounding.medium and
    // Tokens.spacing.extraSmall, the bases the quickshell visualiser scales.
    readonly property real barRounding: 12 * root.roundingScale
    readonly property real barSpacing: 4 * root.spacingScale

    function refreshScheme(): void {
        schemeSource.connectSource(root.schemeCommand)
    }

    anchors.fill: parent

    Component.onCompleted: {
        root.refreshScheme()
    }

    CavaProvider {
        id: cavaProvider

        bars: root.barCount
    }

    ServiceRef {
        id: cavaRef

        // Toggling the reference is the pause switch: dropping the last
        // reference stops the provider's analysis timer and tears down the
        // AudioCollector's PipeWire stream; re-adding it restarts both. In
        // plasmashell this applet is the only refholder, so "not running"
        // means no audio work happens in this process at all.
        service: root.running ? cavaProvider : null
    }

    VisualiserBars {
        id: bars

        anchors.fill: parent

        values: root.running ? cavaProvider.values : []
        primaryColor: root.primaryColor
        secondaryColor: root.secondaryColor
        rounding: root.barRounding
        spacing: root.barSpacing
        animationDuration: root.animationDuration
    }

    FrameAnimation {
        // Nothing to advance while the provider reports no values, and
        // spinning here is not free: every frame repaints this surface (the
        // same gate as the quickshell Visualiser.qml).
        running: root.running && !bars.settled && cavaProvider.values.length > 0
        onTriggered: bars.advance(frameTime)
    }

    Plasma5Support.DataSource {
        id: schemeSource

        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            const stdout = data["stdout"] || ""
            schemeSource.disconnectSource(source)
            if (!stdout)
                return
            try {
                const colours = JSON.parse(stdout).colours ?? {}
                if (colours.primary)
                    root.primaryColor = Qt.alpha("#" + colours.primary, 0.7)
                if (colours.inversePrimary)
                    root.secondaryColor = Qt.alpha("#" + colours.inversePrimary, 0.7)
            } catch (e) {
            }
        }
    }

    // The scheme file is rewritten atomically, which the DataSource cannot
    // watch; the plugin's SchemeLoader singleton re-arms a QFileSystemWatcher
    // on exactly this file (the same trigger the shell's Colours singleton
    // uses), so refetch on its signal rather than polling.
    Connections {
        target: SchemeLoader

        function onCurrentSchemeChanged(): void {
            root.refreshScheme()
        }
    }
}
