pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// KScreen owns the outputs. The shell reads its JSON and hands every change back to
/// `kscreen-doctor`, in the same one-shot form System Settings uses, so the two can never
/// disagree about the layout: there is no second copy of the screen setup to keep in step.
Singleton {
    id: root

    property var outputs: []
    /// False when KScreen could not be asked at all: an empty list would otherwise read as
    /// "no screens" rather than "kscreen is not installed".
    property bool available: true
    /// Which panels advertise an HDR transfer function, keyed by output name. KScreen stores
    /// whatever it is asked for, so the capability has to come from the panel's own EDID.
    property var panels: ({})

    readonly property var connected: root.outputs.filter(output => output.connected)
    readonly property var enabled: root.connected.filter(output => output.enabled)

    /// KScreen reports the rotation as a power of two; the CLI takes these names.
    readonly property var rotations: ({ 1: "none", 2: "left", 4: "inverted", 8: "right" })

    /// KWin resets a panel to full brightness whenever its colour mode or resolution
    /// changes, so everything that writes the layout announces it and lets brightness be
    /// put back afterwards.
    signal layoutApplied

    /// HDR is offered only for a panel that advertises an HDR transfer function, so the
    /// switch is not there to be flipped on a screen that cannot show the result.
    function supportsHdr(output: var): bool {
        return root.panels[output?.name]?.hdr === true;
    }

    function outputFor(name: string): var {
        return root.outputs.find(output => output.name === name) ?? null;
    }

    /// The modes worth offering, largest and fastest first, so the current one sits near
    /// the top of the menu instead of buried in the order the driver reports.
    function modesFor(output: var): var {
        return (output?.modes ?? []).slice().sort((a, b) => b.size.width * b.size.height - a.size.width * a.size.height || b.refreshRate - a.refreshRate);
    }

    function modeLabel(mode: var): string {
        return `${mode.size.width} x ${mode.size.height} · ${Math.round(mode.refreshRate)} Hz`;
    }

    function rotationName(rotation: int): string {
        return root.rotations[rotation] ?? "none";
    }

    /// The layout and the panels behind it are independent questions, so they are asked at
    /// the same time rather than one after the other.
    function refresh(): void {
        readProcess.running = false;
        readProcess.running = true;

        panelsProcess.running = false;
        panelsProcess.running = true;
    }

    function apply(settings: list<string>): void {
        if (settings.length === 0)
            return;

        writeProcess.command = ["kscreen-doctor", ...settings];
        writeProcess.running = true;
    }

    function setEnabled(name: string, on: bool): void {
        root.apply([`output.${name}.${on ? "enable" : "disable"}`]);
    }

    function setMode(name: string, modeId: string): void {
        root.apply([`output.${name}.mode.${modeId}`]);
    }

    function setScale(name: string, scale: real): void {
        root.apply([`output.${name}.scale.${scale}`]);
    }

    function setRotation(name: string, rotation: int): void {
        root.apply([`output.${name}.rotation.${root.rotationName(rotation)}`]);
    }

    /// The wide colour gamut goes with HDR rather than on its own, which is what KDE's own
    /// switch does: HDR content is graded in BT.2020, so enabling one without the other is
    /// a half-applied change.
    function setHdr(name: string, on: bool): void {
        root.apply([`output.${name}.hdr.${on ? "enable" : "disable"}`, `output.${name}.wcg.${on ? "enable" : "disable"}`]);
    }

    Component.onCompleted: root.refresh()

    Process {
        id: readProcess

        command: ["kscreen-doctor", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.outputs = JSON.parse(text).outputs ?? [];
                    root.available = true;
                } catch (error) {
                    root.outputs = [];
                    root.available = false;
                }
            }
        }

        onExited: code => {
            if (code !== 0) {
                root.outputs = [];
                root.available = false;
            }
        }
    }

    Process {
        id: panelsProcess

        command: ["python3", Quickshell.shellPath("scripts/panel_capabilities.py")]

        stdout: StdioCollector {
            onStreamFinished: {
                let reports = [];
                try {
                    reports = JSON.parse(text);
                } catch (error) {
                    // An unreadable EDID is not an error worth a page of its own: the HDR
                    // row simply stays away, because nothing claimed the screen can do it.
                    reports = [];
                }

                const panels = {};
                for (const report of reports)
                    panels[report.output] = report;
                root.panels = panels;
            }
        }
    }

    Process {
        id: writeProcess

        // KScreen answers the read with the layout it just applied, so the page shows what
        // really happened rather than what was asked for.
        onExited: {
            root.refresh();
            root.layoutApplied();
        }
    }
}
