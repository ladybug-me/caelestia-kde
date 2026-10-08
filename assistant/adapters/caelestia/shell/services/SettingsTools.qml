pragma Singleton
pragma ComponentBehavior: Bound

// Caelestia in-shell settings tool service (issue #120).
//
// One native QML boundary between the sidebar AI assistant's tool loop and
// ConfigObject: the same 277-tool validated registry the offline Python CLI
// uses (assistant/settings/tools.json), applied through the same property
// writes every Nexus page performs (GlobalConfig.<path> = value), with
// these behaviors:
//   - preview-then-confirm for any request resolving to more than one tool
//     call (single-setting requests apply directly, exactly as the issue
//     frames it);
//   - a bounded undo history (12 applies, oldest evicted first) persisted at
//     ~/.local/state/caelestia/assistant-settings-history.json;
//   - read-only explainability grounded in the same registry + citations;
//   - named presets as bundles of validated tool calls, never bespoke code.
//
// The registry/preset/explain tables below are GENERATED from tools.json
// and committed verbatim; a Python unittest (test_qml_service.py) asserts
// the shipped table matches tools.json byte-for-byte. Validation mirrors
// assistant/settings/planner.py's set-branch semantics: out-of-range values
// are rejected, never clamped; type mismatches are rejected, never coerced.

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    // How many applies the undo history remembers (issue #120: "a small
    // history"; >= 10 required — 12 chosen).
    readonly property int maxHistory: 12
    readonly property string historyPath: `${Paths.state}/assistant-settings-history.json`

    // A pending multi-op plan awaiting the user's Apply/Cancel (the
    // preview-then-confirm flow). Null when none is pending.
    property var pendingPlan: null

    property var history: []

    property var toolsByName: ({})
    property var toolsByPath: ({})
    property var groups: []

    // Generated from assistant/settings/tools.json by
    // scripts/assemble_settings_tools.py — DO NOT EDIT BY HAND.
    // A unittest re-renders this block from tools.json and asserts
    // byte-identity; regenerate via the script after rebuilding tools.json.
    // Fields: n name, p path, g group, k kind, d default, lo/hi range,
    // st step, en enum (array|null), sl stringMaxLen, go globalOnly.
    readonly property var toolTable: [
        { n: "setBarDragThreshold", p: "bar.dragThreshold", g: "bar", k: "int", d: 20, lo: 0, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:237", "CONFIG declaration: int dragThreshold = 20"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:107", "shipped Nexus control (StepperRow)"]] },
        { n: "setBarPersistent", p: "bar.persistent", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:233", "CONFIG declaration: bool persistent = true"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:67", "shipped Nexus control (ToggleRow)"], ["shell/modules/bar/BarWrapper.qml:27", "persistent reader"]] },
        { n: "setBarPosition", p: "bar.position", g: "bar", k: "enum", d: "bottom", lo: null, hi: null, st: null, en: ["top", "bottom", "left", "right"], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:238", "CONFIG declaration: QString position = u\"bottom\"_s"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:91", "shipped Nexus control (SelectRow)"], ["shell/modules/bar/BarWrapper.qml:23", "position-driven anchoring"]] },
        { n: "setBarScale", p: "bar.scale", g: "bar", k: "float", d: 1.0, lo: 0.6, hi: 1.6, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:224", "CONFIG declaration: qreal scale = 1.0"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:157", "shipped Nexus control (StepperRow)"], ["shell/modules/bar/BarWrapper.qml:24", "contentWidth = innerWidth * barScale; floor 0.6"]] },
        { n: "setBarShowOnHover", p: "bar.showOnHover", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:236", "CONFIG declaration: bool showOnHover = true"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:100", "shipped Nexus control (ToggleRow)"]] },
        { n: "setClockBackground", p: "bar.clock.background", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:138", "CONFIG declaration: bool background = false"], ["shell/modules/nexus/pages/panels/taskbar/BarClock.qml:19", "shipped Nexus control (ToggleRow)"]] },
        { n: "setClockShowDate", p: "bar.clock.showDate", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:139", "CONFIG declaration: bool showDate = false"], ["shell/modules/nexus/pages/panels/taskbar/BarClock.qml:26", "shipped Nexus control (ToggleRow)"]] },
        { n: "setClockShowIcon", p: "bar.clock.showIcon", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:140", "CONFIG declaration: bool showIcon = true"], ["shell/modules/nexus/pages/panels/taskbar/BarClock.qml:32", "shipped Nexus control (ToggleRow)"]] },
        { n: "setClockShowSeconds", p: "bar.clock.showSeconds", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:142", "CONFIG declaration: bool showSeconds = false"], ["shell/modules/nexus/pages/panels/taskbar/BarClock.qml:38", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDodgeFocusedOnly", p: "bar.dodgeFocusedOnly", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:235", "CONFIG declaration: bool dodgeFocusedOnly = false"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:83", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDodgeWindows", p: "bar.dodgeWindows", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:234", "CONFIG declaration: bool dodgeWindows = false"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:75", "shipped Nexus control (ToggleRow)"]] },
        { n: "setFontScaleOffset", p: "bar.fontScaleOffset", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:229", "CONFIG declaration: qreal fontScaleOffset = 0.0"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:192", "shipped Nexus control (StepperRow)"]] },
        { n: "setGithubBackground", p: "bar.github.background", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:161", "CONFIG declaration: bool background = false"], ["shell/modules/nexus/pages/panels/taskbar/BarGithub.qml:99", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGreeterAfternoonStart", p: "bar.greeter.afternoonStart", g: "bar", k: "int", d: 12, lo: 0, hi: 23, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:82", "CONFIG declaration: int afternoonStart = 12"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:228", "shipped Nexus control (StepperRow)"]] },
        { n: "setGreeterEveningStart", p: "bar.greeter.eveningStart", g: "bar", k: "int", d: 17, lo: 0, hi: 23, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:83", "CONFIG declaration: int eveningStart = 17"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:273", "shipped Nexus control (StepperRow)"]] },
        { n: "setGreeterInverted", p: "bar.greeter.inverted", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:71", "CONFIG declaration: bool inverted = false"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:107", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGreeterMode", p: "bar.greeter.mode", g: "bar", k: "enum", d: "timeOfDay", lo: null, hi: null, st: null, en: ["timeOfDay", "slideshow"], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:74", "CONFIG declaration: QString mode = u\"timeOfDay\"_s"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:141", "shipped Nexus control (SelectRow)"]] },
        { n: "setGreeterMorningStart", p: "bar.greeter.morningStart", g: "bar", k: "int", d: 5, lo: 0, hi: 23, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:81", "CONFIG declaration: int morningStart = 5"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:183", "shipped Nexus control (StepperRow)"]] },
        { n: "setGreeterNightStart", p: "bar.greeter.nightStart", g: "bar", k: "int", d: 20, lo: 0, hi: 23, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:84", "CONFIG declaration: int nightStart = 20"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:318", "shipped Nexus control (StepperRow)"]] },
        { n: "setGreeterShowOnHover", p: "bar.greeter.showOnHover", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:72", "CONFIG declaration: bool showOnHover = true"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:116", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGreeterSlideshowInterval", p: "bar.greeter.slideshowInterval", g: "bar", k: "float", d: 60.0, lo: 5, hi: 3600, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:95", "CONFIG declaration: qreal slideshowInterval = 60.0"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:352", "shipped Nexus control (StepperRow)"]] },
        { n: "setGreeterSlideshowRandom", p: "bar.greeter.slideshowRandom", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:96", "CONFIG declaration: bool slideshowRandom = false"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:367", "shipped Nexus control (ToggleRow)"]] },
        { n: "setLivePreviews", p: "bar.livePreviews", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:230", "CONFIG declaration: bool livePreviews = true"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:178", "shipped Nexus control (ToggleRow)"], ["shell/components/images/WindowPreview.qml:42", "live reader"]] },
        { n: "setPopoutsGreeter", p: "bar.popouts.greeter", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:27", "CONFIG declaration: bool greeter = false"], ["shell/modules/nexus/pages/panels/taskbar/BarGreeter.qml:126", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPopoutsStatusIcons", p: "bar.popouts.statusIcons", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:29", "CONFIG declaration: bool statusIcons = true"], ["shell/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml:101", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPopoutsTray", p: "bar.popouts.tray", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:28", "CONFIG declaration: bool tray = true"], ["shell/modules/nexus/pages/panels/taskbar/BarTray.qml:39", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPreviewScale", p: "bar.previewScale", g: "bar", k: "float", d: 1.0, lo: 0.5, hi: 1.6, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:225", "CONFIG declaration: qreal previewScale = 1.0"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:168", "shipped Nexus control (StepperRow)"]] },
        { n: "setPreviewScaleWithBar", p: "bar.previewScaleWithBar", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:226", "CONFIG declaration: bool previewScaleWithBar = false"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:185", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPreviewScalesAudio", p: "bar.previewScales.audio", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:185", "CONFIG declaration: qreal audio = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:100", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesBattery", p: "bar.previewScales.battery", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:186", "CONFIG declaration: qreal battery = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:113", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesBluetooth", p: "bar.previewScales.bluetooth", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:187", "CONFIG declaration: qreal bluetooth = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:126", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesDock", p: "bar.previewScales.dock", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:189", "CONFIG declaration: qreal dock = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:139", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesGithub", p: "bar.previewScales.github", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:190", "CONFIG declaration: qreal github = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:152", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesGreeter", p: "bar.previewScales.greeter", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:184", "CONFIG declaration: qreal greeter = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:81", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesLockStatus", p: "bar.previewScales.lockStatus", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:193", "CONFIG declaration: qreal lockStatus = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:165", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesNetwork", p: "bar.previewScales.network", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:194", "CONFIG declaration: qreal network = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:178", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesNotifications", p: "bar.previewScales.notifications", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:195", "CONFIG declaration: qreal notifications = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:191", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesPeripheralBattery", p: "bar.previewScales.peripheralBattery", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:196", "CONFIG declaration: qreal peripheralBattery = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:204", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesTrayMenu", p: "bar.previewScales.trayMenu", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:197", "CONFIG declaration: qreal trayMenu = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:217", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setPreviewScalesWirelessPassword", p: "bar.previewScales.wirelessPassword", g: "bar", k: "float", d: 0.0, lo: -1.0, hi: 1.0, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:198", "CONFIG declaration: qreal wirelessPassword = 0.0"], ["shell/modules/nexus/pages/panels/taskbar/BarPreviewScales.qml:230", "shipped Nexus control (DoubleStepperRow)"]] },
        { n: "setScrollActionsBrightness", p: "bar.scrollActions.brightness", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:21", "CONFIG declaration: bool brightness = true"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:249", "shipped Nexus control (ToggleRow)"]] },
        { n: "setScrollActionsVolume", p: "bar.scrollActions.volume", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:20", "CONFIG declaration: bool volume = true"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:242", "shipped Nexus control (ToggleRow)"]] },
        { n: "setScrollActionsWorkspaces", p: "bar.scrollActions.workspaces", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:19", "CONFIG declaration: bool workspaces = true"], ["shell/modules/nexus/pages/panels/TaskbarPanel.qml:234", "shipped Nexus control (ToggleRow)"]] },
        { n: "setStatusShowWifi", p: "bar.status.showWifi", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:125", "CONFIG declaration: bool showWifi = true"], ["shell/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml:88", "shipped Nexus control (ToggleRow)"]] },
        { n: "setTrayBackground", p: "bar.tray.background", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:111", "CONFIG declaration: bool background = false"], ["shell/modules/nexus/pages/panels/taskbar/BarTray.qml:20", "shipped Nexus control (ToggleRow)"]] },
        { n: "setTrayCompact", p: "bar.tray.compact", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:113", "CONFIG declaration: bool compact = true"], ["shell/modules/nexus/pages/panels/taskbar/BarTray.qml:33", "shipped Nexus control (ToggleRow)"]] },
        { n: "setTrayRecolour", p: "bar.tray.recolour", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:112", "CONFIG declaration: bool recolour = false"], ["shell/modules/nexus/pages/panels/taskbar/BarTray.qml:27", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesActiveIndicator", p: "bar.workspaces.activeIndicator", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:37", "CONFIG declaration: bool activeIndicator = true"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:77", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesActiveTrail", p: "bar.workspaces.activeTrail", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:43", "CONFIG declaration: bool activeTrail = true"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:83", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesDisplayType", p: "bar.workspaces.displayType", g: "bar", k: "enum", d: "Shapes", lo: null, hi: null, st: null, en: ["Shapes", "Text"], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:49", "CONFIG declaration: caelestia::config::BarWorkspaceDisplay::Enum displayType = BarWorkspaceDisplay::Shapes"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:95", "shipped Nexus control (SelectRow)"]] },
        { n: "setWorkspacesMaxWindowIcons", p: "bar.workspaces.maxWindowIcons", g: "bar", k: "int", d: 5, lo: 0, hi: 20, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:42", "CONFIG declaration: int maxWindowIcons = 5"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:126", "shipped Nexus control (StepperRow)"]] },
        { n: "setWorkspacesOccupiedBg", p: "bar.workspaces.occupiedBg", g: "bar", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:38", "CONFIG declaration: bool occupiedBg = false"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:89", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesPerMonitor", p: "bar.workspaces.perMonitor", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:45", "CONFIG declaration: bool perMonitor = true"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:137", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesShowUnoccupied", p: "bar.workspaces.showUnoccupied", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:39", "CONFIG declaration: bool showUnoccupied = true"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:112", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesShowWindows", p: "bar.workspaces.showWindows", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:40", "CONFIG declaration: bool showWindows = true"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:104", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesShowWindowsOnSpecialWorkspaces", p: "bar.workspaces.showWindowsOnSpecialWorkspaces", g: "bar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:41", "CONFIG declaration: bool showWindowsOnSpecialWorkspaces = true"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:120", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWorkspacesShown", p: "bar.workspaces.shown", g: "bar", k: "int", d: 5, lo: 1, hi: 20, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:36", "CONFIG declaration: int shown = 5"], ["shell/modules/nexus/pages/panels/taskbar/BarWorkspaces.qml:53", "shipped Nexus control (StepperRow)"]] },
        { n: "setDockBadges", p: "bar.dock.showBadges", g: "dock", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:150", "CONFIG declaration: bool showBadges = true"], ["shell/modules/nexus/pages/panels/taskbar/BarDock.qml:75", "shipped Nexus control (ToggleRow)"], ["shell/modules/bar/components/Dock.qml:630", "badge over LauncherEntry.forApp, ?? true"]] },
        { n: "setDockCurrentDesktopOnly", p: "bar.dock.currentDesktopOnly", g: "dock", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:152", "CONFIG declaration: bool currentDesktopOnly = false"], ["shell/modules/nexus/pages/panels/taskbar/BarDock.qml:83", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDockIconSize", p: "bar.dock.iconSize", g: "dock", k: "int", d: 32, lo: 16, hi: 96, st: 4, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:151", "CONFIG declaration: int iconSize = 32"], ["shell/modules/nexus/pages/panels/taskbar/BarDock.qml:54", "shipped Nexus control (StepperRow)"], ["shell/modules/bar/components/Dock.qml:38", "QML floor 16"]] },
        { n: "setDockPreviewOnDesktop", p: "bar.dock.previewOnDesktop", g: "dock", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:154", "CONFIG declaration: bool previewOnDesktop = true"], ["shell/modules/nexus/pages/panels/taskbar/BarDock.qml:91", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDockRecolourIcons", p: "bar.dock.recolourIcons", g: "dock", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/barconfig.hpp:149", "CONFIG declaration: bool recolourIcons = false"], ["shell/modules/nexus/pages/panels/taskbar/BarDock.qml:67", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDeformScale", p: "appearance.deformScale", g: "appearance", k: "float", d: 1.0, lo: 0, hi: 1.5, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:316", "CONFIG declaration: qreal deformScale = 1"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:357", "shipped Nexus control (StepperRow)"]] },
        { n: "setFontScale", p: "appearance.font.scale", g: "appearance", k: "float", d: 1.0, lo: 0.5, hi: 2.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:251", "CONFIG declaration: qreal scale = 1"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:285", "shipped Nexus control (StepperRow)"]] },
        { n: "setPaddingScale", p: "appearance.padding.scale", g: "appearance", k: "float", d: 1.0, lo: 0.5, hi: 2.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:90", "CONFIG declaration: qreal scale = 1"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:306", "shipped Nexus control (StepperRow)"]] },
        { n: "setRoundingScale", p: "appearance.rounding.scale", g: "appearance", k: "float", d: 1.0, lo: 0.5, hi: 2.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:22", "CONFIG declaration: qreal scale = 1"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:118", "shipped Nexus control (StepperRow)"]] },
        { n: "setSpacingScale", p: "appearance.spacing.scale", g: "appearance", k: "float", d: 1.0, lo: 0.5, hi: 2.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:57", "CONFIG declaration: qreal scale = 1"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:296", "shipped Nexus control (StepperRow)"]] },
        { n: "setAmbientColor", p: "appearance.ambientColor", g: "effects", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:328", "CONFIG declaration: bool ambientColor = true"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:158", "shipped Nexus control (ToggleRow)"]] },
        { n: "setAmbientOpacity", p: "appearance.ambientOpacity", g: "effects", k: "float", d: 0.45, lo: 0, hi: 1, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:329", "CONFIG declaration: qreal ambientOpacity = 0.45"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:167", "shipped Nexus control (SliderRow)"]] },
        { n: "setBlurEnabled", p: "appearance.blur", g: "effects", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:326", "CONFIG declaration: bool blur = true"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:222", "shipped Nexus control (ToggleRow)"], ["shell/modules/drawers/blur/BlurOffsets.qml:17", "isActive = transparency.enabled && blur"]] },
        { n: "setBlurMask", p: "appearance.blurMask", g: "effects", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:327", "CONFIG declaration: bool blurMask = true"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:246", "shipped Nexus control (ToggleRow)"]] },
        { n: "setIslands", p: "appearance.islands", g: "effects", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:325", "CONFIG declaration: bool islands = false"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:100", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPitchBlack", p: "appearance.pitchBlack", g: "effects", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:324", "CONFIG declaration: bool pitchBlack = false"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:92", "shipped Nexus control (ToggleRow)"], ["shell/modules/drawers/ContentWindow.qml:394", "#000000 surface when pitchBlack"]] },
        { n: "setTransparencyBase", p: "appearance.transparency.base", g: "effects", k: "float", d: 0.85, lo: 0.0, hi: 1.0, st: 0.05, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:309", "CONFIG declaration: qreal base = 0.85"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:141", "shipped Nexus control (SliderRow)"], ["shell/modules/drawers/ContentWindow.qml:383", "surface opacity reader"]] },
        { n: "setTransparencyEnabled", p: "appearance.transparency.enabled", g: "effects", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:308", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:128", "shipped Nexus control (ToggleRow)"]] },
        { n: "setTransparencyLayers", p: "appearance.transparency.layers", g: "effects", k: "float", d: 0.4, lo: 0, hi: 1, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:310", "CONFIG declaration: qreal layers = 0.4"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:149", "shipped Nexus control (SliderRow)"]] },
        { n: "setAnimationSpeed", p: "appearance.anim.durations.scale", g: "animations", k: "float", d: 1.0, lo: 0.25, hi: 4.0, st: 0.25, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/appearanceconfig.hpp:265", "CONFIG declaration: qreal scale = 1"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:316", "shipped Nexus control (StepperRow)"], ["shell/plugin/src/Caelestia/Config/appearanceconfig.cpp:207", "durations multiplied by scale"]] },
        { n: "setActionOnClick", p: "notifs.actionOnClick", g: "notifications", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:20", "CONFIG declaration: bool actionOnClick = false"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:162", "shipped Nexus control (ToggleRow)"]] },
        { n: "setClearThreshold", p: "notifs.clearThreshold", g: "notifications", k: "float", d: 0.3, lo: 0, hi: 1, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:18", "CONFIG declaration: qreal clearThreshold = 0.3"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:190", "shipped Nexus control (SliderRow)"]] },
        { n: "setDefaultExpireTimeout", p: "notifs.defaultExpireTimeout", g: "notifications", k: "int", d: 5000, lo: 1000, hi: 60000, st: 1000, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:16", "CONFIG declaration: int defaultExpireTimeout = 5000"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:117", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:120", "stepper displays seconds (value: x/1000; onMoved: Math.round(v*1000)); stored unit is ms — range converted x1000"]] },
        { n: "setExpandThreshold", p: "notifs.expandThreshold", g: "notifications", k: "int", d: 20, lo: 5, hi: 100, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:19", "CONFIG declaration: int expandThreshold = 20"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:170", "shipped Nexus control (StepperRow)"]] },
        { n: "setExpire", p: "notifs.expire", g: "notifications", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:13", "CONFIG declaration: bool expire = true"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:103", "shipped Nexus control (ToggleRow)"]] },
        { n: "setFullscreen", p: "notifs.fullscreen", g: "notifications", k: "enum", d: "off", lo: null, hi: null, st: null, en: ["off", "on"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:14", "CONFIG declaration: QString fullscreen = QStringLiteral(\"off\")"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:78", "shipped Nexus control (SelectRow)"]] },
        { n: "setFullscreenExpireTimeout", p: "notifs.fullscreenExpireTimeout", g: "notifications", k: "int", d: 2000, lo: 1000, hi: 30000, st: 1000, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:17", "CONFIG declaration: int fullscreenExpireTimeout = 2000"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:180", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:183", "stepper displays seconds (value: x/1000; onMoved: Math.round(value*1000)); stored unit is ms — range converted x1000"]] },
        { n: "setGroupPreviewNum", p: "notifs.groupPreviewNum", g: "notifications", k: "int", d: 3, lo: 1, hi: 10, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:21", "CONFIG declaration: int groupPreviewNum = 3"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:127", "shipped Nexus control (StepperRow)"]] },
        { n: "setMonitor", p: "notifs.monitor", g: "notifications", k: "enum", d: "all", lo: null, hi: null, st: null, en: ["all", "focused"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:15", "CONFIG declaration: QString monitor = QStringLiteral(\"all\")"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:87", "shipped Nexus control (SelectRow)"]] },
        { n: "setNotifsMaxNotifs", p: "notifs.maxNotifs", g: "notifications", k: "int", d: 50, lo: 20, hi: 2000, st: 50, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:25", "CONFIG declaration: int maxNotifs = 50"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:147", "shipped Nexus control (StepperRow)"]] },
        { n: "setNotifsMaxPopups", p: "notifs.maxPopups", g: "notifications", k: "int", d: 8, lo: 0, hi: 30, st: 1, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:24", "CONFIG declaration: int maxPopups = 8"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:137", "shipped Nexus control (StepperRow)"]] },
        { n: "setOpenExpanded", p: "notifs.openExpanded", g: "notifications", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:22", "CONFIG declaration: bool openExpanded = false"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:110", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPosition", p: "notifs.position", g: "notifications", k: "enum", d: "auto", lo: null, hi: null, st: null, en: ["auto", "top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/notifsconfig.hpp:23", "CONFIG declaration: QString position = QStringLiteral(\"auto\")"], ["shell/modules/nexus/pages/services/NotificationPreferencesPage.qml:95", "shipped Nexus control (SelectRow)"]] },
        { n: "setClipboardMaxEntries", p: "launcher.clipboardMaxEntries", g: "launcher", k: "int", d: 20, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:47", "CONFIG declaration: int clipboardMaxEntries = 20"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:193", "shipped Nexus control (StepperRow)"]] },
        { n: "setConfirmClearClipboard", p: "launcher.confirmClearClipboard", g: "launcher", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:58", "CONFIG declaration: bool confirmClearClipboard = true"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:204", "shipped Nexus control (ToggleRow)"]] },
        { n: "setEnableDangerousActions", p: "launcher.enableDangerousActions", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:50", "CONFIG declaration: bool enableDangerousActions = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:225", "shipped Nexus control (ToggleRow)"]] },
        { n: "setLauncherDragThreshold", p: "launcher.dragThreshold", g: "launcher", k: "int", d: 50, lo: 0, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:51", "CONFIG declaration: int dragThreshold = 50"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:177", "shipped Nexus control (StepperRow)"]] },
        { n: "setLauncherEnabled", p: "launcher.enabled", g: "launcher", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:43", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:30", "shipped Nexus control (ToggleRow)"]] },
        { n: "setLauncherHoverThickness", p: "launcher.hoverThickness", g: "launcher", k: "int", d: 10, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:55", "CONFIG declaration: int hoverThickness = 10"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:157", "shipped Nexus control (StepperRow)"]] },
        { n: "setLauncherHoverWidth", p: "launcher.hoverWidth", g: "launcher", k: "int", d: 50, lo: 10, hi: 100, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:56", "CONFIG declaration: int hoverWidth = 50"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:167", "shipped Nexus control (StepperRow)"]] },
        { n: "setLauncherMaxShown", p: "launcher.maxShown", g: "launcher", k: "int", d: 7, lo: 1, hi: 20, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:45", "CONFIG declaration: int maxShown = 7"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:139", "shipped Nexus control (StepperRow)"]] },
        { n: "setLauncherShowOnHover", p: "launcher.showOnHover", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:44", "CONFIG declaration: bool showOnHover = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:111", "shipped Nexus control (ToggleRow)"]] },
        { n: "setLauncherVimKeybinds", p: "launcher.vimKeybinds", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:57", "CONFIG declaration: bool vimKeybinds = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:217", "shipped Nexus control (ToggleRow)"]] },
        { n: "setMaxWallpapers", p: "launcher.maxWallpapers", g: "launcher", k: "int", d: 9, lo: 1, hi: 30, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:46", "CONFIG declaration: int maxWallpapers = 9"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:148", "shipped Nexus control (StepperRow)"]] },
        { n: "setShowBrowseOnEmpty", p: "launcher.showBrowseOnEmpty", g: "launcher", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:53", "CONFIG declaration: bool showBrowseOnEmpty = true"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:124", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowPowerMenu", p: "launcher.showPowerMenu", g: "launcher", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:52", "CONFIG declaration: bool showPowerMenu = true"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:132", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUseFuzzyActions", p: "launcher.useFuzzy.actions", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:20", "CONFIG declaration: bool actions = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:245", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUseFuzzyApps", p: "launcher.useFuzzy.apps", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:19", "CONFIG declaration: bool apps = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:238", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUseFuzzySchemes", p: "launcher.useFuzzy.schemes", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:21", "CONFIG declaration: bool schemes = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:251", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUseFuzzyVariants", p: "launcher.useFuzzy.variants", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:22", "CONFIG declaration: bool variants = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:257", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUseFuzzyWallpapers", p: "launcher.useFuzzy.wallpapers", g: "launcher", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/launcherconfig.hpp:23", "CONFIG declaration: bool wallpapers = false"], ["shell/modules/nexus/pages/panels/LauncherPanel.qml:263", "shipped Nexus control (ToggleRow)"]] },
        { n: "setBlurWallpaper", p: "lock.blurWallpaper", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:22", "CONFIG declaration: bool blurWallpaper = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:184", "shipped Nexus control (ToggleRow)"]] },
        { n: "setEnableFprint", p: "lock.enableFprint", g: "lockscreen", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:12", "CONFIG declaration: bool enableFprint = true"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:201", "shipped Nexus control (ToggleRow)"]] },
        { n: "setHideNotifs", p: "lock.hideNotifs", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:19", "CONFIG declaration: bool hideNotifs = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:280", "shipped Nexus control (ToggleRow)"]] },
        { n: "setLockOnStartup", p: "lock.lockOnStartup", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:20", "CONFIG declaration: bool lockOnStartup = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:269", "shipped Nexus control (ToggleRow)"]] },
        { n: "setMaxFprintTries", p: "lock.maxFprintTries", g: "lockscreen", k: "int", d: 3, lo: 1, hi: 5, st: 1, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:13", "CONFIG declaration: int maxFprintTries = 3"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:213", "shipped Nexus control (SelectRow)"]] },
        { n: "setRecolourLogo", p: "lock.recolourLogo", g: "lockscreen", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:11", "CONFIG declaration: bool recolourLogo = true"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:291", "shipped Nexus control (ToggleRow)"]] },
        { n: "setRotateProfilePic", p: "lock.rotateProfilePic", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:18", "CONFIG declaration: bool rotateProfilePic = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:258", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowHibernate", p: "lock.showHibernate", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:24", "CONFIG declaration: bool showHibernate = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:320", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowLogout", p: "lock.showLogout", g: "lockscreen", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:26", "CONFIG declaration: bool showLogout = true"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:342", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowReboot", p: "lock.showReboot", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:27", "CONFIG declaration: bool showReboot = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:353", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowShutdown", p: "lock.showShutdown", g: "lockscreen", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:28", "CONFIG declaration: bool showShutdown = false"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:364", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowSleep", p: "lock.showSleep", g: "lockscreen", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:23", "CONFIG declaration: bool showSleep = true"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:308", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowSwitchUser", p: "lock.showSwitchUser", g: "lockscreen", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:25", "CONFIG declaration: bool showSwitchUser = true"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:331", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSyncWallpaper", p: "lock.syncWallpaper", g: "lockscreen", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/lockconfig.hpp:21", "CONFIG declaration: bool syncWallpaper = true"], ["shell/modules/nexus/pages/wallandstyle/LockScreenPage.qml:147", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopClockEnabled", p: "background.desktopClock.enabled", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:29", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:89", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopClockInvertColors", p: "background.desktopClock.invertColors", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:34", "CONFIG declaration: bool invertColors = false"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:213", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopClockPosition", p: "background.desktopClock.position", g: "wallpaper-scheme", k: "enum", d: "bottom-right", lo: null, hi: null, st: null, en: ["top-left", "top-center", "top-right", "center", "bottom-left", "bottom-center", "bottom-right"], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:31", "CONFIG declaration: QString position = QStringLiteral(\"bottom-right\")"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:197", "shipped Nexus control (SelectRow)"]] },
        { n: "setDesktopClockScale", p: "background.desktopClock.scale", g: "wallpaper-scheme", k: "float", d: 1.0, lo: 0.5, hi: 3, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:30", "CONFIG declaration: qreal scale = 1.0"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:186", "shipped Nexus control (StepperRow)"]] },
        { n: "setDesktopIconsEnabled", p: "background.desktopIconsEnabled", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:108", "CONFIG declaration: bool desktopIconsEnabled = true"], ["shell/modules/nexus/pages/DesktopPage.qml:40", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopLyricsAlignment", p: "background.desktopLyrics.alignment", g: "wallpaper-scheme", k: "int", d: 1, lo: 0, hi: 2, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:76", "CONFIG declaration: int alignment = 1"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:294", "shipped Nexus control (SelectRow)"]] },
        { n: "setDesktopLyricsAutoHide", p: "background.desktopLyrics.autoHide", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:71", "CONFIG declaration: bool autoHide = true"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:131", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopLyricsEnabled", p: "background.desktopLyrics.enabled", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:70", "CONFIG declaration: bool enabled = false"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:119", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopLyricsInvertColors", p: "background.desktopLyrics.invertColors", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:77", "CONFIG declaration: bool invertColors = false"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:308", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopLyricsPosition", p: "background.desktopLyrics.position", g: "wallpaper-scheme", k: "enum", d: "bottom-center", lo: null, hi: null, st: null, en: ["top-left", "top-center", "top-right", "center", "bottom-left", "bottom-center", "bottom-right"], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:73", "CONFIG declaration: QString position = QStringLiteral(\"bottom-center\")"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:278", "shipped Nexus control (SelectRow)"]] },
        { n: "setDesktopLyricsScale", p: "background.desktopLyrics.scale", g: "wallpaper-scheme", k: "float", d: 1.0, lo: 0.5, hi: 3, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:72", "CONFIG declaration: qreal scale = 1.0"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:267", "shipped Nexus control (StepperRow)"]] },
        { n: "setDesktopShapesAutoHide", p: "background.desktopShapes.autoHide", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:86", "CONFIG declaration: bool autoHide = true"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:109", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopShapesEnabled", p: "background.desktopShapes.enabled", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:85", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:97", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDesktopShapesPosition", p: "background.desktopShapes.position", g: "wallpaper-scheme", k: "enum", d: "bottom-center", lo: null, hi: null, st: null, en: ["top-left", "top-center", "top-right", "center", "bottom-left", "bottom-center", "bottom-right"], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:88", "CONFIG declaration: QString position = QStringLiteral(\"bottom-center\")"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:241", "shipped Nexus control (SelectRow)"]] },
        { n: "setDesktopShapesScale", p: "background.desktopShapes.scale", g: "wallpaper-scheme", k: "float", d: 1.0, lo: 0.5, hi: 3, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:87", "CONFIG declaration: qreal scale = 1.0"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:230", "shipped Nexus control (StepperRow)"]] },
        { n: "setMaterialYouIconsEnabled", p: "background.materialYouIconsEnabled", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:109", "CONFIG declaration: bool materialYouIconsEnabled = true"], ["shell/modules/nexus/pages/DesktopPage.qml:57", "shipped Nexus control (ToggleRow)"]] },
        { n: "setMaterialYouIconsVibrant", p: "background.materialYouIconsVibrant", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:110", "CONFIG declaration: bool materialYouIconsVibrant = true"], ["shell/modules/nexus/pages/DesktopPage.qml:74", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSlideshowEnabled", p: "background.slideshowEnabled", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:99", "CONFIG declaration: bool slideshowEnabled = false"], ["shell/modules/nexus/pages/wallandstyle/SlideshowAndOrderPage.qml:33", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSlideshowInterval", p: "background.slideshowInterval", g: "wallpaper-scheme", k: "float", d: 0.16, lo: 0, hi: 1, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:100", "CONFIG declaration: qreal slideshowInterval = 0.16"], ["shell/modules/nexus/pages/wallandstyle/SlideshowAndOrderPage.qml:43", "shipped Nexus control (SliderRow)"]] },
        { n: "setSlideshowRandom", p: "background.slideshowRandom", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:101", "CONFIG declaration: bool slideshowRandom = true"], ["shell/modules/nexus/pages/wallandstyle/SlideshowAndOrderPage.qml:54", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVideoWallpaperMuteOnMedia", p: "background.videoWallpaperMuteOnMedia", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:107", "CONFIG declaration: bool videoWallpaperMuteOnMedia = false"], ["shell/modules/nexus/pages/wallandstyle/VideoWallpapersPage.qml:61", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVideoWallpaperPauseOnAllDisplays", p: "background.videoWallpaperPauseOnAllDisplays", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:106", "CONFIG declaration: bool videoWallpaperPauseOnAllDisplays = false"], ["shell/modules/nexus/pages/wallandstyle/VideoWallpapersPage.qml:55", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVideoWallpaperPauseOnFullscreen", p: "background.videoWallpaperPauseOnFullscreen", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:104", "CONFIG declaration: bool videoWallpaperPauseOnFullscreen = false"], ["shell/modules/nexus/pages/wallandstyle/VideoWallpapersPage.qml:41", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVideoWallpaperPauseOnTiled", p: "background.videoWallpaperPauseOnTiled", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:105", "CONFIG declaration: bool videoWallpaperPauseOnTiled = false"], ["shell/modules/nexus/pages/wallandstyle/VideoWallpapersPage.qml:48", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVideoWallpaperPaused", p: "background.videoWallpaperPaused", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:102", "CONFIG declaration: bool videoWallpaperPaused = false"], ["shell/modules/nexus/pages/wallandstyle/VideoWallpapersPage.qml:28", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVideoWallpaperSoundEnabled", p: "background.videoWallpaperSoundEnabled", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:103", "CONFIG declaration: bool videoWallpaperSoundEnabled = false"], ["shell/modules/nexus/pages/wallandstyle/VideoWallpapersPage.qml:35", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVisualiserAutoHide", p: "background.visualiser.autoHide", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:43", "CONFIG declaration: bool autoHide = true"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:155", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVisualiserBlur", p: "background.visualiser.blur", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:45", "CONFIG declaration: bool blur = false"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:325", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVisualiserEnabled", p: "background.visualiser.enabled", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:42", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:141", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVisualiserHideOnAllMonitors", p: "background.visualiser.hideOnAllMonitors", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:44", "CONFIG declaration: bool hideOnAllMonitors = false"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:165", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVisualiserRounding", p: "background.visualiser.rounding", g: "wallpaper-scheme", k: "float", d: 1.0, lo: 0, hi: 1, st: 0.05, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:46", "CONFIG declaration: qreal rounding = 1"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:333", "shipped Nexus control (StepperRow)"]] },
        { n: "setVisualiserSpacing", p: "background.visualiser.spacing", g: "wallpaper-scheme", k: "float", d: 1.0, lo: 0.5, hi: 3, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:47", "CONFIG declaration: qreal spacing = 1"], ["shell/modules/nexus/pages/wallandstyle/DesktopAddonsPage.qml:343", "shipped Nexus control (StepperRow)"]] },
        { n: "setWallpaperEnabled", p: "background.wallpaperEnabled", g: "wallpaper-scheme", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:95", "CONFIG declaration: bool wallpaperEnabled = true"], ["shell/modules/nexus/pages/DesktopPage.qml:24", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWallpaperFillMode", p: "background.wallpaperFillMode", g: "wallpaper-scheme", k: "enum", d: 2, lo: null, hi: null, st: null, en: [0, 1, 2], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:96", "CONFIG declaration: int wallpaperFillMode = 2"], ["shell/modules/nexus/pages/wallandstyle/WallpaperSettingsPage.qml:49", "shipped Nexus control (SelectRow)"], ["shell/modules/nexus/pages/wallandstyle/WallpaperSettingsPage.qml:26", "scalingValues: [Image.PreserveAspectCrop, Image.PreserveAspectFit, Image.Stretch] = [2, 1, 0]; the SelectRow writes these ints"]] },
        { n: "setWallpaperRecolor", p: "background.wallpaperRecolor", g: "wallpaper-scheme", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:97", "CONFIG declaration: bool wallpaperRecolor = false"], ["shell/modules/nexus/pages/wallandstyle/WallpaperSettingsPage.qml:68", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWallpaperRecolorStrength", p: "background.wallpaperRecolorStrength", g: "wallpaper-scheme", k: "float", d: 0.5, lo: 0, hi: 1, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/backgroundconfig.hpp:98", "CONFIG declaration: qreal wallpaperRecolorStrength = 0.5"], ["shell/modules/nexus/pages/wallandstyle/WallpaperSettingsPage.qml:85", "shipped Nexus control (SliderRow)"]] },
        { n: "setBaseDuration", p: "overview.baseDuration", g: "overview", k: "int", d: 300, lo: 100, hi: 1000, st: 50, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:22", "CONFIG declaration: int baseDuration = 300"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:225", "shipped Nexus control (StepperRow)"]] },
        { n: "setBlobScaleSpeed", p: "overview.blobScaleSpeed", g: "overview", k: "float", d: 1.0, lo: 0.1, hi: 5.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:23", "CONFIG declaration: qreal blobScaleSpeed = 1.0"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:234", "shipped Nexus control (StepperRow)"]] },
        { n: "setDisableWallpaperBlur", p: "overview.disableWallpaperBlur", g: "overview", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:12", "CONFIG declaration: bool disableWallpaperBlur = true"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:191", "shipped Nexus control (ToggleRow)"]] },
        { n: "setEasingType", p: "overview.easingType", g: "overview", k: "enum", d: 2, lo: null, hi: null, st: null, en: [0, 2, 3, 6, 10, 14, 18, 22, 26, 30, 33, 34, 38], sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:26", "CONFIG declaration: int easingType = 2"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:207", "shipped Nexus control (SelectRow)"]] },
        { n: "setEnableOverviewBlur", p: "overview.enableOverviewBlur", g: "overview", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:13", "CONFIG declaration: bool enableOverviewBlur = true"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:197", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGridFadeSpeed", p: "overview.gridFadeSpeed", g: "overview", k: "float", d: 1.0, lo: 0.1, hi: 5.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:25", "CONFIG declaration: qreal gridFadeSpeed = 1.0"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:252", "shipped Nexus control (StepperRow)"]] },
        { n: "setHoverBottomLeft", p: "overview.hoverBottomLeft", g: "overview", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:19", "CONFIG declaration: bool hoverBottomLeft = false"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:159", "shipped Nexus control (ToggleRow)"]] },
        { n: "setHoverBottomRight", p: "overview.hoverBottomRight", g: "overview", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:20", "CONFIG declaration: bool hoverBottomRight = false"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:164", "shipped Nexus control (ToggleRow)"]] },
        { n: "setHoverTopLeft", p: "overview.hoverTopLeft", g: "overview", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:17", "CONFIG declaration: bool hoverTopLeft = true"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:148", "shipped Nexus control (ToggleRow)"]] },
        { n: "setHoverTopRight", p: "overview.hoverTopRight", g: "overview", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:18", "CONFIG declaration: bool hoverTopRight = false"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:154", "shipped Nexus control (ToggleRow)"]] },
        { n: "setLayoutType", p: "overview.layoutType", g: "overview", k: "int", d: 1, lo: 0, hi: 1, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:27", "CONFIG declaration: int layoutType = 1"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:173", "shipped Nexus control (SelectRow)"]] },
        { n: "setOverviewDragThreshold", p: "overview.dragThreshold", g: "overview", k: "int", d: 30, lo: 10, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:15", "CONFIG declaration: int dragThreshold = 30"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:131", "shipped Nexus control (StepperRow)"]] },
        { n: "setOverviewEnabled", p: "overview.enabled", g: "overview", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:11", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:108", "shipped Nexus control (ToggleRow)"]] },
        { n: "setOverviewHoverThickness", p: "overview.hoverThickness", g: "overview", k: "int", d: 20, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:16", "CONFIG declaration: int hoverThickness = 20"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:120", "shipped Nexus control (StepperRow)"]] },
        { n: "setOverviewShowOnHover", p: "overview.showOnHover", g: "overview", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:14", "CONFIG declaration: bool showOnHover = true"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:114", "shipped Nexus control (ToggleRow)"]] },
        { n: "setWallpaperFadeSpeed", p: "overview.wallpaperFadeSpeed", g: "overview", k: "float", d: 1.0, lo: 0.1, hi: 5.0, st: 0.1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/overviewconfig.hpp:24", "CONFIG declaration: qreal wallpaperFadeSpeed = 1.0"], ["shell/modules/nexus/pages/panels/OverviewPanel.qml:243", "shipped Nexus control (StepperRow)"]] },
        { n: "setEnableBrightness", p: "osd.enableBrightness", g: "osd", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:15", "CONFIG declaration: bool enableBrightness = true"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:45", "shipped Nexus control (ToggleRow)"]] },
        { n: "setEnableMicrophone", p: "osd.enableMicrophone", g: "osd", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:16", "CONFIG declaration: bool enableMicrophone = false"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:38", "shipped Nexus control (ToggleRow)"]] },
        { n: "setEnableVolume", p: "osd.enableVolume", g: "osd", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:17", "CONFIG declaration: bool enableVolume = true"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:31", "shipped Nexus control (ToggleRow)"]] },
        { n: "setHideDelay", p: "osd.hideDelay", g: "osd", k: "int", d: 2000, lo: 1000, hi: 10000, st: 1000, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:12", "CONFIG declaration: int hideDelay = 2000"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:83", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:88", "stepper displays seconds (value: x/1000; onMoved: Math.round(value*1000)); stored unit is ms — range converted x1000"]] },
        { n: "setOsdEnabled", p: "osd.enabled", g: "osd", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:11", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:23", "shipped Nexus control (ToggleRow)"]] },
        { n: "setOsdHoverThickness", p: "osd.hoverThickness", g: "osd", k: "int", d: 10, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:13", "CONFIG declaration: int hoverThickness = 10"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:57", "shipped Nexus control (StepperRow)"]] },
        { n: "setOsdHoverWidth", p: "osd.hoverWidth", g: "osd", k: "int", d: 50, lo: 10, hi: 100, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/osdconfig.hpp:14", "CONFIG declaration: int hoverWidth = 50"], ["shell/modules/nexus/pages/utilities/OsdPage.qml:68", "shipped Nexus control (StepperRow)"]] },
        { n: "setColorizeMediaGif", p: "dashboard.colorizeMediaGif", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:31", "CONFIG declaration: bool colorizeMediaGif = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:174", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDashboardDragThreshold", p: "dashboard.dragThreshold", g: "dashboard", k: "int", d: 50, lo: 0, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:37", "CONFIG declaration: int dragThreshold = 50"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:269", "shipped Nexus control (StepperRow)"]] },
        { n: "setDashboardEnabled", p: "dashboard.enabled", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:22", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:94", "shipped Nexus control (ToggleRow)"]] },
        { n: "setDashboardHoverThickness", p: "dashboard.hoverThickness", g: "dashboard", k: "int", d: 10, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:38", "CONFIG declaration: int hoverThickness = 10"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:248", "shipped Nexus control (StepperRow)"]] },
        { n: "setDashboardHoverWidth", p: "dashboard.hoverWidth", g: "dashboard", k: "int", d: 50, lo: 10, hi: 100, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:39", "CONFIG declaration: int hoverWidth = 50"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:259", "shipped Nexus control (StepperRow)"]] },
        { n: "setDashboardShowOnHover", p: "dashboard.showOnHover", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:23", "CONFIG declaration: bool showOnHover = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:101", "shipped Nexus control (ToggleRow)"]] },
        { n: "setMediaUpdateInterval", p: "dashboard.mediaUpdateInterval", g: "dashboard", k: "int", d: 500, lo: 100, hi: 2000, st: 50, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:35", "CONFIG declaration: int mediaUpdateInterval = 500"], ["shell/modules/nexus/pages/ServicesPage.qml:89", "shipped Nexus control (StepperRow)"]] },
        { n: "setPerformanceShowBattery", p: "dashboard.performance.showBattery", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:11", "CONFIG declaration: bool showBattery = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:205", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPerformanceShowCpu", p: "dashboard.performance.showCpu", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:13", "CONFIG declaration: bool showCpu = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:218", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPerformanceShowGpu", p: "dashboard.performance.showGpu", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:12", "CONFIG declaration: bool showGpu = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:212", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPerformanceShowMemory", p: "dashboard.performance.showMemory", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:14", "CONFIG declaration: bool showMemory = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:224", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPerformanceShowNetwork", p: "dashboard.performance.showNetwork", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:16", "CONFIG declaration: bool showNetwork = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:236", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPerformanceShowStorage", p: "dashboard.performance.showStorage", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:15", "CONFIG declaration: bool showStorage = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:230", "shipped Nexus control (ToggleRow)"]] },
        { n: "setResourceUpdateInterval", p: "dashboard.resourceUpdateInterval", g: "dashboard", k: "int", d: 1000, lo: 500, hi: 10000, st: 500, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:36", "CONFIG declaration: int resourceUpdateInterval = 1000"], ["shell/modules/nexus/pages/ServicesPage.qml:100", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/ServicesPage.qml:111", "stepper displays seconds (value: x/1000; onMoved: Math.round(v*1000)); stored unit is ms — range converted x1000"]] },
        { n: "setShowClockSeconds", p: "dashboard.showClockSeconds", g: "dashboard", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:33", "CONFIG declaration: bool showClockSeconds = false"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:128", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowDashboard", p: "dashboard.showDashboard", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:24", "CONFIG declaration: bool showDashboard = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:141", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowMedia", p: "dashboard.showMedia", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:25", "CONFIG declaration: bool showMedia = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:148", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowPerformance", p: "dashboard.showPerformance", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:26", "CONFIG declaration: bool showPerformance = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:154", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowTerminal", p: "dashboard.showTerminal", g: "dashboard", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:29", "CONFIG declaration: bool showTerminal = false"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:167", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowWeather", p: "dashboard.showWeather", g: "dashboard", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:27", "CONFIG declaration: bool showWeather = true"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:160", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUseMediaShapes", p: "dashboard.useMediaShapes", g: "dashboard", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/dashboardconfig.hpp:32", "CONFIG declaration: bool useMediaShapes = false"], ["shell/modules/nexus/pages/panels/DashboardPanel.qml:182", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGrabWidth", p: "sidebar.grabWidth", g: "sidebar", k: "int", d: 12, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/sidebarconfig.hpp:17", "CONFIG declaration: int grabWidth = 12"], ["shell/modules/nexus/pages/panels/SidebarPanel.qml:48", "shipped Nexus control (StepperRow)"]] },
        { n: "setSidebarDragThreshold", p: "sidebar.dragThreshold", g: "sidebar", k: "int", d: 50, lo: 0, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/sidebarconfig.hpp:16", "CONFIG declaration: int dragThreshold = 50"], ["shell/modules/nexus/pages/panels/SidebarPanel.qml:36", "shipped Nexus control (StepperRow)"]] },
        { n: "setSidebarEnabled", p: "sidebar.enabled", g: "sidebar", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/sidebarconfig.hpp:15", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/panels/SidebarPanel.qml:29", "shipped Nexus control (ToggleRow)"]] },
        { n: "setNetworkRescanInterval", p: "nexus.networkRescanInterval", g: "nexus", k: "int", d: 15000, lo: 5000, hi: 120000, st: 5000, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/nexusconfig.hpp:12", "CONFIG declaration: int networkRescanInterval = 15000"], ["shell/modules/nexus/pages/ServicesPage.qml:110", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/ServicesPage.qml:122", "stepper displays seconds (value: x/1000; onMoved: Math.round(v*1000)); stored unit is ms — range converted x1000"]] },
        { n: "setBorderThickness", p: "border.thickness", g: "border", k: "int", d: 10, lo: 0, hi: 50, st: 2, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/borderconfig.hpp:13", "CONFIG declaration: int thickness = 10"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:108", "shipped Nexus control (StepperRow)"]] },
        { n: "setRounding", p: "border.rounding", g: "border", k: "int", d: 25, lo: 0, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/borderconfig.hpp:14", "CONFIG declaration: int rounding = 25"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:336", "shipped Nexus control (StepperRow)"]] },
        { n: "setSmoothing", p: "border.smoothing", g: "border", k: "int", d: 20, lo: 0, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/borderconfig.hpp:15", "CONFIG declaration: int smoothing = 20"], ["shell/modules/nexus/pages/wallandstyle/AppearancePage.qml:347", "shipped Nexus control (StepperRow)"]] },
        { n: "setAllScreens", p: "tabSwitch.allScreens", g: "general", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/tabswitchconfig.hpp:15", "CONFIG declaration: bool allScreens = true"], ["shell/modules/nexus/pages/panels/TabSwitcherPanel.qml:164", "shipped Nexus control (ToggleRow)"]] },
        { n: "setCheckUpdates", p: "general.checkUpdates", g: "general", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/generalconfig.hpp:70", "CONFIG declaration: bool checkUpdates = true"], ["shell/modules/nexus/pages/panels/taskbar/BarUpdates.qml:44", "shipped Nexus control (ToggleRow)"]] },
        { n: "setCurrentDesktopOnly", p: "tabSwitch.currentDesktopOnly", g: "general", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/tabswitchconfig.hpp:12", "CONFIG declaration: bool currentDesktopOnly = false"], ["shell/modules/nexus/pages/panels/TabSwitcherPanel.qml:114", "shipped Nexus control (ToggleRow)"]] },
        { n: "setPreviewOnDesktop", p: "tabSwitch.previewOnDesktop", g: "general", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/tabswitchconfig.hpp:13", "CONFIG declaration: bool previewOnDesktop = true"], ["shell/modules/nexus/pages/panels/TabSwitcherPanel.qml:129", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSessionDragThreshold", p: "session.dragThreshold", g: "general", k: "int", d: 30, lo: 10, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/sessionconfig.hpp:36", "CONFIG declaration: int dragThreshold = 30"], ["shell/modules/nexus/pages/SessionPage.qml:53", "shipped Nexus control (StepperRow)"]] },
        { n: "setSessionEnabled", p: "session.enabled", g: "general", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/sessionconfig.hpp:35", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/SessionPage.qml:36", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSessionVimKeybinds", p: "session.vimKeybinds", g: "general", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/sessionconfig.hpp:37", "CONFIG declaration: bool vimKeybinds = false"], ["shell/modules/nexus/pages/SessionPage.qml:45", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowMinimized", p: "tabSwitch.showMinimized", g: "general", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/tabswitchconfig.hpp:14", "CONFIG declaration: bool showMinimized = true"], ["shell/modules/nexus/pages/panels/TabSwitcherPanel.qml:149", "shipped Nexus control (ToggleRow)"]] },
        { n: "setArpcCaelestiaInfo", p: "services.arpcCaelestiaInfo", g: "services", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:88", "CONFIG declaration: bool arpcCaelestiaInfo = false"], ["shell/modules/nexus/pages/services/ArpcPage.qml:74", "shipped Nexus control (ToggleRow)"]] },
        { n: "setArpcEnabled", p: "services.arpcEnabled", g: "services", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:77", "CONFIG declaration: bool arpcEnabled = false"], ["shell/modules/nexus/pages/services/ArpcPage.qml:56", "shipped Nexus control (ToggleRow)"]] },
        { n: "setArpcIdleTimeout", p: "services.arpcIdleTimeout", g: "services", k: "int", d: 0, lo: 0, hi: 3600, st: 60, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:90", "CONFIG declaration: int arpcIdleTimeout = 0"], ["shell/modules/nexus/pages/services/ArpcPage.qml:83", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/services/ArpcPage.qml:95", "stepper displays minutes (value: Math.round(x/60); onMoved: Math.round(v*60)); stored unit is seconds — range converted x60"]] },
        { n: "setArpcManualOverride", p: "services.arpcManualOverride", g: "services", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:89", "CONFIG declaration: bool arpcManualOverride = false"], ["shell/modules/nexus/pages/services/ArpcPage.qml:439", "shipped Nexus control (ToggleRow)"]] },
        { n: "setArpcSteamAutoDetect", p: "services.arpcSteamAutoDetect", g: "services", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:84", "CONFIG declaration: bool arpcSteamAutoDetect = false"], ["shell/modules/nexus/pages/services/ArpcPage.qml:65", "shipped Nexus control (ToggleRow)"]] },
        { n: "setAudioIncrement", p: "services.audioIncrement", g: "services", k: "float", d: 0.1, lo: 0.01, hi: 0.5, st: 0.01, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:54", "CONFIG declaration: qreal audioIncrement = 0.1"], ["shell/modules/nexus/pages/ServicesPage.qml:151", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/ServicesPage.qml:161", "stepper displays percent (value: Math.round(x*100); onMoved: v/100); stored unit is a fraction — range converted /100"]] },
        { n: "setAutoSchemeEnabled", p: "services.autoSchemeEnabled", g: "services", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:62", "CONFIG declaration: bool autoSchemeEnabled = false"], ["shell/modules/nexus/pages/wallandstyle/AdvancedColorsPage.qml:89", "shipped Nexus control (ToggleRow)"]] },
        { n: "setAutoSchemeMode", p: "services.autoSchemeMode", g: "services", k: "enum", d: "solar", lo: null, hi: null, st: null, en: ["solar", "fixed"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:63", "CONFIG declaration: QString autoSchemeMode = u\"solar\"_s"], ["shell/modules/nexus/pages/wallandstyle/AdvancedColorsPage.qml:98", "shipped Nexus control (SelectRow)"]] },
        { n: "setBrightnessIncrement", p: "services.brightnessIncrement", g: "services", k: "float", d: 0.1, lo: 0.01, hi: 0.5, st: 0.01, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:55", "CONFIG declaration: qreal brightnessIncrement = 0.1"], ["shell/modules/nexus/pages/ServicesPage.qml:162", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/ServicesPage.qml:165", "stepper displays percent (value: Math.round(x*100); onMoved: v/100); stored unit is a fraction — range converted /100"]] },
        { n: "setClockFormat", p: "services.clockFormat", g: "services", k: "enum", d: "Auto", lo: null, hi: null, st: null, en: ["Auto", "TwelveHour", "TwentyFourHour"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:37", "CONFIG declaration: caelestia::config::ClockFormat::Enum clockFormat = ClockFormat::Auto"], ["shell/modules/nexus/pages/LanguageAndRegion.qml:419", "shipped Nexus control (SelectRow)"]] },
        { n: "setDataUnits", p: "services.dataUnits", g: "services", k: "enum", d: "Binary", lo: null, hi: null, st: null, en: ["Binary", "Decimal"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:31", "CONFIG declaration: caelestia::config::DataUnit::Enum dataUnits = DataUnit::Binary"], ["shell/modules/nexus/pages/LanguageAndRegion.qml:405", "shipped Nexus control (SelectRow)"]] },
        { n: "setGpuType", p: "services.gpuType", g: "services", k: "enum", d: "", lo: null, hi: null, st: null, en: ["", "NVIDIA", "GENERIC", "None"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:49", "CONFIG declaration: QString gpuType = QString()"], ["shell/modules/nexus/pages/ServicesPage.qml:206", "shipped Nexus control (SelectRow)"], ["shell/modules/nexus/pages/ServicesPage.qml:47", "gpuValues: [\"\", \"NVIDIA\", \"GENERIC\", \"None\"] (fixed literal)"]] },
        { n: "setMaxVolume", p: "services.maxVolume", g: "services", k: "float", d: 1.0, lo: 0.5, hi: 2.0, st: 0.05, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:56", "CONFIG declaration: qreal maxVolume = 1.0"], ["shell/modules/nexus/pages/ServicesPage.qml:172", "shipped Nexus control (StepperRow)"], ["shell/modules/nexus/pages/ServicesPage.qml:182", "stepper displays percent (value: Math.round(x*100); onMoved: v/100); stored unit is a fraction — range converted /100"]] },
        { n: "setSensorUnits", p: "services.sensorUnits", g: "services", k: "enum", d: "Celsius", lo: null, hi: null, st: null, en: ["Auto", "Celsius", "Fahrenheit", "Kelvin"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:30", "CONFIG declaration: caelestia::config::TemperatureUnit::Enum sensorUnits = TemperatureUnit::Celsius"], ["shell/modules/nexus/pages/LanguageAndRegion.qml:397", "shipped Nexus control (SelectRow)"]] },
        { n: "setSmartScheme", p: "services.smartScheme", g: "services", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:57", "CONFIG declaration: bool smartScheme = true"], ["shell/modules/nexus/pages/wallandstyle/AdvancedColorsPage.qml:81", "shipped Nexus control (ToggleRow)"]] },
        { n: "setVisualiserBars", p: "services.visualiserBars", g: "services", k: "int", d: 60, lo: 10, hi: 120, st: 2, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:50", "CONFIG declaration: int visualiserBars = 60"], ["shell/modules/nexus/pages/ServicesPage.qml:196", "shipped Nexus control (StepperRow)"]] },
        { n: "setWeatherUnits", p: "services.weatherUnits", g: "services", k: "enum", d: "Auto", lo: null, hi: null, st: null, en: ["Auto", "Celsius", "Fahrenheit", "Kelvin"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/serviceconfig.hpp:29", "CONFIG declaration: caelestia::config::TemperatureUnit::Enum weatherUnits = TemperatureUnit::Auto"], ["shell/modules/nexus/pages/LanguageAndRegion.qml:388", "shipped Nexus control (SelectRow)"]] },
        { n: "setGameModeAutoEnable", p: "utilities.gameMode.autoEnable", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:69", "CONFIG declaration: bool autoEnable = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:35", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableDesktopLyrics", p: "utilities.gameMode.disableDesktopLyrics", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:66", "CONFIG declaration: bool disableDesktopLyrics = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:109", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableHyprlandAnimations", p: "utilities.gameMode.disableHyprlandAnimations", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:59", "CONFIG declaration: bool disableHyprlandAnimations = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:60", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableHyprlandBlur", p: "utilities.gameMode.disableHyprlandBlur", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:60", "CONFIG declaration: bool disableHyprlandBlur = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:67", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableHyprlandGaps", p: "utilities.gameMode.disableHyprlandGaps", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:61", "CONFIG declaration: bool disableHyprlandGaps = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:73", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableHyprlandShadows", p: "utilities.gameMode.disableHyprlandShadows", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:62", "CONFIG declaration: bool disableHyprlandShadows = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:79", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableShellTransparency", p: "utilities.gameMode.disableShellTransparency", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:63", "CONFIG declaration: bool disableShellTransparency = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:98", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableToastTransparency", p: "utilities.gameMode.disableToastTransparency", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:65", "CONFIG declaration: bool disableToastTransparency = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:104", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableVisualizer", p: "utilities.gameMode.disableVisualizer", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:67", "CONFIG declaration: bool disableVisualizer = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:114", "shipped Nexus control (ToggleRow)"]] },
        { n: "setGameModeDisableWindowTransparency", p: "utilities.gameMode.disableWindowTransparency", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:64", "CONFIG declaration: bool disableWindowTransparency = true"], ["shell/modules/nexus/pages/services/GameModePage.qml:85", "shipped Nexus control (ToggleRow)"]] },
        { n: "setMaxToasts", p: "utilities.maxToasts", g: "utilities", k: "int", d: 4, lo: 1, hi: 10, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:81", "CONFIG declaration: int maxToasts = 4"], ["shell/modules/nexus/pages/services/ToastPreferencesPage.qml:50", "shipped Nexus control (StepperRow)"]] },
        { n: "setShowGifRecorder", p: "utilities.showGifRecorder", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:87", "CONFIG declaration: bool showGifRecorder = true"], ["shell/modules/nexus/pages/utilities/UtilitiesPanelPage.qml:38", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowKeepAwake", p: "utilities.showKeepAwake", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:85", "CONFIG declaration: bool showKeepAwake = true"], ["shell/modules/nexus/pages/utilities/UtilitiesPanelPage.qml:23", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowQuickToggles", p: "utilities.showQuickToggles", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:88", "CONFIG declaration: bool showQuickToggles = true"], ["shell/modules/nexus/pages/utilities/UtilitiesPanelPage.qml:45", "shipped Nexus control (ToggleRow)"]] },
        { n: "setShowScreenRecorder", p: "utilities.showScreenRecorder", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:86", "CONFIG declaration: bool showScreenRecorder = true"], ["shell/modules/nexus/pages/utilities/UtilitiesPanelPage.qml:31", "shipped Nexus control (ToggleRow)"]] },
        { n: "setToastsChargingChanged", p: "utilities.toasts.chargingChanged", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:19", "CONFIG declaration: bool chargingChanged = true"], ["shell/modules/nexus/pages/services/ToastEventsPage.qml:26", "shipped Nexus control (ToggleRow)"]] },
        { n: "setToastsConfigLoaded", p: "utilities.toasts.configLoaded", g: "utilities", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:18", "CONFIG declaration: bool configLoaded = false"], ["shell/modules/nexus/pages/services/ToastEventsPage.qml:45", "shipped Nexus control (ToggleRow)"]] },
        { n: "setToastsFullscreen", p: "utilities.toasts.fullscreen", g: "utilities", k: "enum", d: "off", lo: null, hi: null, st: null, en: ["off", "important", "all"], sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:17", "CONFIG declaration: QString fullscreen = u\"off\"_s"], ["shell/modules/nexus/pages/services/ToastPreferencesPage.qml:41", "shipped Nexus control (SelectRow)"]] },
        { n: "setToastsGameModeChanged", p: "utilities.toasts.gameModeChanged", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:20", "CONFIG declaration: bool gameModeChanged = true"], ["shell/modules/nexus/pages/services/ToastEventsPage.qml:32", "shipped Nexus control (ToggleRow)"]] },
        { n: "setToastsNightLightChanged", p: "utilities.toasts.nightLightChanged", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:31", "CONFIG declaration: bool nightLightChanged = true"], ["shell/modules/nexus/pages/services/ToastEventsPage.qml:38", "shipped Nexus control (ToggleRow)"]] },
        { n: "setToastsTransparency", p: "utilities.toasts.transparency", g: "utilities", k: "bool", d: false, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:32", "CONFIG declaration: bool transparency = false"], ["shell/modules/nexus/pages/services/ToastPreferencesPage.qml:60", "shipped Nexus control (ToggleRow)"]] },
        { n: "setToastsTransparencyBase", p: "utilities.toasts.transparencyBase", g: "utilities", k: "float", d: 0.85, lo: 0, hi: 1, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:33", "CONFIG declaration: qreal transparencyBase = 0.85"], ["shell/modules/nexus/pages/services/ToastPreferencesPage.qml:67", "shipped Nexus control (SliderRow)"]] },
        { n: "setUtilitiesDragThreshold", p: "utilities.dragThreshold", g: "utilities", k: "int", d: 50, lo: 0, hi: 200, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:78", "CONFIG declaration: int dragThreshold = 50"], ["shell/modules/nexus/pages/panels/UtilitiesPanel.qml:68", "shipped Nexus control (StepperRow)"]] },
        { n: "setUtilitiesEnabled", p: "utilities.enabled", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:76", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/panels/UtilitiesPanel.qml:29", "shipped Nexus control (ToggleRow)"]] },
        { n: "setUtilitiesHoverThickness", p: "utilities.hoverThickness", g: "utilities", k: "int", d: 10, lo: 1, hi: 100, st: 1, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:79", "CONFIG declaration: int hoverThickness = 10"], ["shell/modules/nexus/pages/panels/UtilitiesPanel.qml:44", "shipped Nexus control (StepperRow)"]] },
        { n: "setUtilitiesHoverWidth", p: "utilities.hoverWidth", g: "utilities", k: "int", d: 50, lo: 10, hi: 100, st: 5, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:80", "CONFIG declaration: int hoverWidth = 50"], ["shell/modules/nexus/pages/panels/UtilitiesPanel.qml:56", "shipped Nexus control (StepperRow)"]] },
        { n: "setUtilitiesShowOnHover", p: "utilities.showOnHover", g: "utilities", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: false, c: [["shell/plugin/src/Caelestia/Config/utilitiesconfig.hpp:77", "CONFIG declaration: bool showOnHover = true"], ["shell/modules/nexus/pages/panels/UtilitiesPanel.qml:36", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsCameraClick", p: "audio.sounds.cameraClick", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:12", "CONFIG declaration: bool cameraClick = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:46", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsChargingStarted", p: "audio.sounds.chargingStarted", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:13", "CONFIG declaration: bool chargingStarted = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:66", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsEffectTick", p: "audio.sounds.effectTick", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:14", "CONFIG declaration: bool effectTick = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:54", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsEnabled", p: "audio.sounds.enabled", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:11", "CONFIG declaration: bool enabled = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:24", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsLock", p: "audio.sounds.lock", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:15", "CONFIG declaration: bool lock = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:74", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsLowBattery", p: "audio.sounds.lowBattery", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:17", "CONFIG declaration: bool lowBattery = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:88", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsNotificationVolume", p: "audio.sounds.notificationVolume", g: "audio", k: "float", d: 1.0, lo: 0, hi: 1, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:22", "CONFIG declaration: qreal notificationVolume = 1.0"], ["shell/modules/nexus/pages/services/ToastPreferencesPage.qml:80", "shipped Nexus control (SliderRow)"]] },
        { n: "setSoundsScreenRecord", p: "audio.sounds.screenRecord", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:18", "CONFIG declaration: bool screenRecord = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:95", "shipped Nexus control (ToggleRow)"]] },
        { n: "setSoundsSfxVolume", p: "audio.sounds.sfxVolume", g: "audio", k: "float", d: 1.0, lo: 0, hi: 1, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:21", "CONFIG declaration: qreal sfxVolume = 1.0"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:31", "shipped Nexus control (SliderRow)"]] },
        { n: "setSoundsUnlock", p: "audio.sounds.unlock", g: "audio", k: "bool", d: true, lo: null, hi: null, st: null, en: null, sl: null, go: true, c: [["shell/plugin/src/Caelestia/Config/audioconfig.hpp:16", "CONFIG declaration: bool unlock = true"], ["shell/modules/nexus/pages/audio/SoundEffectsPage.qml:81", "shipped Nexus control (ToggleRow)"]] },
    ]

    // Named presets: bundles of validated tool calls only (see
    // curations.PRESETS; build_registry validates every call).
    readonly property var presetTable: [
        { name: "compact", label: "Compact", description: "Smaller dock icons and tighter spacing/padding/rounding — the same keys the Nexus steppers expose.", calls: [["setDockIconSize", 24], ["setSpacingScale", 0.8], ["setPaddingScale", 0.8], ["setRoundingScale", 0.8]] },
        { name: "minimal", label: "Minimal", description: "Issue #120's own example direction: smaller bar and dock, lower rounding, faster animations, badges and previews off.", calls: [["setBarScale", 0.7], ["setDockIconSize", 20], ["setRoundingScale", 0.5], ["setAnimationSpeed", 0.5], ["setSpacingScale", 0.7], ["setDockBadges", false], ["setLivePreviews", false]] },
        { name: "gaming", label: "Gaming", description: "Snappier shell, no blur/transparency compositing, no popup notifications. (Game Mode itself is a service toggle, not a shell.json scalar — this bundle is the config-side reduction only.)", calls: [["setBlurEnabled", false], ["setTransparencyEnabled", false], ["setAnimationSpeed", 0.25], ["setNotifsMaxPopups", 0]] },
        { name: "battery-saver", label: "Battery saver", description: "Reduce compositing and background work: blur, ambient glow and wallpaper recolour off, animations fast.", calls: [["setBlurEnabled", false], ["setAnimationSpeed", 0.25], ["setAmbientColor", false], ["setWallpaperRecolor", false]] },
        { name: "macos-like", label: "More like macOS", description: "Always-visible bottom dock with larger icons, rounder corners, roomier spacing and badges on — the keys the shipped controls already expose.", calls: [["setBarPosition", "bottom"], ["setBarPersistent", true], ["setDockIconSize", 48], ["setRoundingScale", 1.3], ["setSpacingScale", 1.1], ["setPaddingScale", 1.1], ["setAnimationSpeed", 1.0], ["setDockBadges", true]] },
    ]

    // Explainability rules: state predicate + answer template + citations.
    // Rendered identically by the Python CLI (assistant/settings/explain.py).
    readonly property var explainTable: [
        { path: "appearance.blur", when: "appearance.blur == true and appearance.transparency.enabled == true", answer: "Blur is enabled because transparency is currently active and appearance.blur is on — the blur regions gate on both ({cite}).", cites: ["shell/modules/drawers/blur/BlurOffsets.qml:17"] },
        { path: "appearance.blur", when: "appearance.blur == true and appearance.transparency.enabled == false", answer: "Blur is ON but has no effect, because transparency is currently disabled — the blur regions gate on transparency.enabled && blur together ({cite}).", cites: ["shell/modules/drawers/blur/BlurOffsets.qml:17"] },
        { path: "appearance.transparency.enabled", when: "appearance.transparency.enabled == true and utilities.gameMode.disableShellTransparency == true and _gamemode == true", answer: "Transparency is configured ON but is currently suppressed, because Game Mode is active with 'disable shell transparency' set — the colour service gates on that pair ({cite}).", cites: ["shell/services/Colours.qml:418"] },
        { path: "appearance.transparency.base", when: "appearance.transparency.base > 0 and _light == true", answer: "Surfaces look less transparent than the configured base opacity {appearance.transparency.base}, because light mode trims the base by 0.1 ({cite}).", cites: ["shell/services/Colours.qml:419"] },
        { path: "appearance.pitchBlack", when: "appearance.pitchBlack == true", answer: "Surfaces are fully opaque and pure black because Pitch Black (bezel mode) is active — it forces opacity 1 ({cite1}) and #000000 surfaces ({cite2}).", cites: ["shell/modules/drawers/ContentWindow.qml:383", "shell/modules/drawers/ContentWindow.qml:394"] },
        { path: "overview.enableOverviewBlur", when: "overview.enableOverviewBlur == true and appearance.blur == false", answer: "The overview blur setting is ON but has no effect, because the global appearance blur is off — the overview effect gates on both ({cite}).", cites: ["shell/modules/drawers/ContentWindow.qml:374"] },
        { path: "appearance.anim.durations.scale", when: "appearance.anim.durations.scale != 1", answer: "Animations feel {slower|faster} because the animation duration scale is currently set to {appearance.anim.durations.scale} — every duration token is multiplied by it, so lower means faster ({cite}).", cites: ["shell/plugin/src/Caelestia/Config/appearanceconfig.cpp:209"] },
        { path: "appearance.ambientColor", when: "appearance.ambientColor == true and _light == true", answer: "The ambient glow is configured ON but is currently hidden, because ambient glow only renders in dark mode — it gates on ambientColor && !light ({cite}).", cites: ["shell/components/effects/AmbientGlow.qml:34"] },
        { path: "bar.persistent", when: "bar.persistent == false", answer: "The bar hides because bar persistence is currently off — a non-persistent bar dodges or auto-hides instead of staying put ({cite}).", cites: ["shell/modules/bar/BarWrapper.qml:62"] },
        { path: "bar.dodgeWindows", when: "bar.dodgeWindows == true and bar.persistent == false", answer: "Window dodging has no effect, because dodge mode requires a persistent bar — the dodge gate is dodgeWindows && persistent ({cite}).", cites: ["shell/modules/bar/BarWrapper.qml:27"] },
        { path: "bar.scale", when: "bar.scale < 0.6", answer: "The bar is not as small as asked: the effective bar scale is floored at 0.6 ({cite}); the configured value is {bar.scale}.", cites: ["shell/modules/bar/BarWrapper.qml:24"] },
    ]

    Component.onCompleted: {
        for (let i = 0; i < toolTable.length; i++) {
            const t = toolTable[i];
            toolsByName[t.n] = t;
            toolsByPath[t.p] = t;
        }
        const seen = [];
        for (let i = 0; i < toolTable.length; i++) {
            const g = toolTable[i].g;
            if (seen.indexOf(g) === -1)
                seen.push(g);
        }
        groups = seen;
    }

    // ---- lookups ----------------------------------------------------------

    function toolInfo(name) {
        const t = toolsByName[name];
        if (!t)
            return null;
        return {
            name: t.n, path: t.p, group: t.g, kind: t.k, default: t.d,
            minimum: t.lo, maximum: t.hi, step: t.st, enum: t.en,
            stringMaxLen: t.sl, globalOnly: t.go, citations: t.c || []
        };
    }

    function toolsInGroup(slug) {
        const out = [];
        for (let i = 0; i < toolTable.length; i++)
            if (toolTable[i].g === slug)
                out.push(toolTable[i].n);
        return out;
    }

    // Compact schema lines for the in-shell model (the 277-row table is too
    // large for a system prompt; the model lists what it needs on demand).
    function listTools(group) {
        const lines = [];
        for (let i = 0; i < toolTable.length; i++) {
            const t = toolTable[i];
            if (group && t.g !== group)
                continue;
            let validation;
            if (t.k === "enum") validation = (t.en || []).join("|");
            else if (t.k === "bool") validation = "on/off";
            else if (t.k === "string") validation = `string<=${t.sl || 64}`;
            else validation = `${t.lo}-${t.hi}`;
            lines.push(`${t.n} ${t.p} ${t.k} ${validation} default ${_fmtVal(t.d)}`);
        }
        if (group && lines.length === 0)
            return { ok: false, reason: `unknown group ${group}; available: ${groups.join(", ")}` };
        return { ok: true, lines: lines, groups: groups };
    }

    // Read-only get for the model: live value + validation + grounding.
    function get(path) {
        const t = toolsByPath[path] !== undefined ? toolsByPath[path]
                  : toolsByName[path] !== undefined ? toolsByName[path] : null;
        if (!t)
            return { ok: false, reason: `unknown setting ${path}` };
        const value = readPath(t.p);
        let validation;
        if (t.k === "enum") validation = (t.en || []).join("|");
        else if (t.k === "bool") validation = "on/off";
        else if (t.k === "string") validation = `string<=${t.sl || 64}`;
        else validation = `${t.lo}-${t.hi}`;
        return {
            ok: true, name: t.n, path: t.p, group: t.g, kind: t.k,
            value: value === null ? t.d : value, validation: validation,
            default: t.d, globalOnly: t.go, citations: (t.c || []).map(c => c[0])
        };
    }

    // ---- validation (mirrors planner.py's set branch) ----------------------

    function validate(name, value) {
        const t = toolsByName[name];
        if (!t)
            return { ok: false, reason: `unknown tool ${name}` };
        if (t.k === "bool") {
            if (typeof value !== "boolean")
                return { ok: false, reason: "this setting is on/off only; it has no magnitude" };
            return { ok: true, value: value };
        }
        if (t.k === "enum") {
            const en = t.en || [];
            for (let i = 0; i < en.length; i++) {
                if (en[i] === value)
                    return { ok: true, value: en[i] };
                // Case-insensitive acceptance, canonicalized to the stored
                // form (string enums only) — mirrors EnumCodec::decode's
                // case-insensitive key match (codecs.cpp:249-257).
                if (typeof en[i] === "string" && typeof value === "string"
                    && en[i].toLowerCase() === value.toLowerCase())
                    return { ok: true, value: en[i] };
            }
            return { ok: false, reason: `value '${value}' is not one of ${en.join("|")}` };
        }
        if (t.k === "string") {
            if (typeof value !== "string" || value.length === 0)
                return { ok: false, reason: "a non-empty string is required" };
            if (value.length > (t.sl || 64))
                return { ok: false, reason: `string longer than ${t.sl || 64} characters` };
            return { ok: true, value: value };
        }
        if (typeof value !== "number" || !isFinite(value))
            return { ok: false, reason: `value '${value}' is not a number` };
        if (t.k === "int" && Math.round(value) !== value)
            return { ok: false, reason: "this setting is an integer" };
        if (t.lo !== null && value < t.lo)
            return { ok: false, reason: `absolute value ${value} is outside the allowed range ${t.lo}-${t.hi}; it is not applied` };
        if (t.hi !== null && value > t.hi)
            return { ok: false, reason: `absolute value ${value} is outside the allowed range ${t.lo}-${t.hi}; it is not applied` };
        return { ok: true, value: value };
    }

    // ---- live config read/write (the Nexus idiom, one writer here) --------

    function readPath(path) {
        const segs = path.split(".");
        let obj = GlobalConfig;
        for (let i = 0; i < segs.length - 1; i++) {
            obj = obj[segs[i]];
            if (obj === undefined || obj === null)
                return null;
        }
        const v = obj[segs[segs.length - 1]];
        return v === undefined ? null : v;
    }

    function writePath(path, value) {
        const segs = path.split(".");
        let obj = GlobalConfig;
        for (let i = 0; i < segs.length - 1; i++) {
            obj = obj[segs[i]];
            if (obj === undefined || obj === null)
                return false;
        }
        obj[segs[segs.length - 1]] = value;
        return true;
    }

    // ---- plan / confirm / apply --------------------------------------------
    //
    // request(calls, label) implements issue #120's confirmation policy:
    // a request resolving to ONE tool call applies immediately (undoable);
    // a request resolving to MORE THAN ONE becomes a pending plan the chat
    // UI must surface as a preview card — nothing is written until
    // confirmPlan(). cancelPlan() drops it untouched.

    function buildPlan(calls, label) {
        // calls: [{name, value}] (or {tool, value}); returns
        // {ok, plan?, reason?}; the plan is all-or-nothing: any invalid
        // entry rejects the whole plan before a single write happens.
        const ops = [];
        for (let i = 0; i < calls.length; i++) {
            const c = calls[i];
            const name = c.name !== undefined ? c.name : c.tool;
            const t = toolsByName[name];
            if (!t)
                return { ok: false, reason: `unknown tool ${name}` };
            const v = validate(name, c.value);
            if (!v.ok)
                return { ok: false, reason: `${name}: ${v.reason}` };
            const old = readPath(t.p);
            ops.push({ name: t.n, path: t.p, kind: t.k, old: old, new: v.value,
                       noOp: old === v.value });
        }
        return { ok: true, plan: { label: label || "", ops: ops } };
    }

    function request(calls, label) {
        const r = buildPlan(calls, label);
        if (!r.ok)
            return r;
        const applicable = r.plan.ops.filter(op => !op.noOp);
        if (applicable.length === 0)
            return { ok: true, applied: false, message: "no changes needed; nothing written" };
        if (applicable.length === 1) {
            const res = applyOps(applicable, r.plan.label);
            return { ok: true, applied: true, changes: res.changes, message: res.message };
        }
        pendingPlan = { plan: r.plan, applicable: applicable };
        return { ok: true, needsConfirm: true, plan: previewOf(r.plan) };
    }

    function previewOf(plan) {
        // The confirm card's payload: one line per op, in the issue's own
        // shape ("I found several changes that match your request: ...").
        const lines = [];
        for (let i = 0; i < plan.ops.length; i++) {
            const op = plan.ops[i];
            lines.push({
                name: op.name, path: op.path,
                from: op.old === null ? "(unset)" : String(op.old),
                to: String(op.new), noOp: op.noOp
            });
        }
        return { label: plan.label, ops: lines };
    }

    function confirmPlan() {
        if (!pendingPlan)
            return { ok: false, reason: "no pending plan to confirm" };
        const p = pendingPlan;
        pendingPlan = null;
        const res = applyOps(p.applicable, p.plan.label);
        return { ok: true, applied: true, changes: res.changes, message: res.message };
    }

    function cancelPlan() {
        if (!pendingPlan)
            return { ok: false, reason: "no pending plan to cancel" };
        pendingPlan = null;
        return { ok: true, applied: false, message: "plan cancelled; nothing was written" };
    }

    function applyOps(ops, label) {
        // The only write path. Records the undo entry AFTER every write
        // succeeded, so a failed write leaves no phantom history entry.
        const recorded = [];
        for (let i = 0; i < ops.length; i++) {
            const op = ops[i];
            if (!writePath(op.path, op.new)) {
                // Roll back what we already wrote this call (best effort;
                // the failed write itself changed nothing).
                for (let j = 0; j < recorded.length; j++)
                    writePath(recorded[j].path, recorded[j].old);
                return { changes: 0, message: `write failed at ${op.path}; rolled back ${recorded.length} change(s); nothing else was written` };
            }
            recorded.push(op);
        }
        pushHistory(label, ops.map(op => ({ path: op.path, old: op.old, new: op.new })));
        return { changes: ops.length,
                 message: `applied ${ops.length} change(s)${label ? ` (${label})` : ""}; undo is available` };
    }

    // ---- bounded undo history (>= 10, oldest evicted first) -----------------

    function _persistHistory() {
        const trimmed = history.slice(0, maxHistory); // FIFO: oldest evicted
        if (trimmed.length !== history.length)
            history = trimmed;
        historyFile.setText(JSON.stringify(history));
    }

    function pushHistory(label, ops) {
        const entry = {
            id: Date.now() + Math.floor(Math.random() * 1000),
            at: new Date().toISOString(),
            label: label || "",
            ops: ops
        };
        history.unshift(entry);
        _persistHistory();
    }

    function historyEntries() {
        return history.map(e => ({ id: e.id, at: e.at, label: e.label, ops: e.ops.length }));
    }

    function undo(steps) {
        const n = Math.max(1, steps || 1);
        let undone = 0;
        for (let i = 0; i < n && history.length > 0; i++) {
            const entry = history.shift();
            // Reverse order: undo the newest entry's ops back-to-front so
            // interdependent keys restore in the opposite order they were set.
            for (let j = entry.ops.length - 1; j >= 0; j--)
                writePath(entry.ops[j].path, entry.ops[j].old);
            undone++;
        }
        if (undone === 0)
            return { ok: false, reason: "nothing to undo (history is empty)" };
        _persistHistory();
        return { ok: true, undone: undone,
                 message: `undid ${undone} apply entr${undone === 1 ? "y" : "ies"}` };
    }

    function undoById(id) {
        const idx = history.findIndex(e => e.id === id);
        if (idx === -1)
            return { ok: false, reason: `no history entry with id ${id}` };
        const entry = history[idx];
        for (let j = entry.ops.length - 1; j >= 0; j--)
            writePath(entry.ops[j].path, entry.ops[j].old);
        history.splice(idx, 1);
        _persistHistory();
        return { ok: true, undone: 1,
                 message: `reverted '${entry.label || entry.ops[0].path}' (${entry.ops.length} change(s), applied ${entry.at})` };
    }

    // ---- explainability (read-only; grounded in the same registry) ----------
    //
    // explain(path) answers in issue #120's own style. Causal rules from
    // tools.json's explainTable run first (each grounded in a real QML/C++
    // citation); with no rule firing, the answer is the live value readback
    // with validation + default + citation, e.g. "The bar scale is
    // currently set to 1.2 (range 0.6-1.6, default 1; barconfig.hpp:233)."

    function _liveState(paths) {
        const state = {};
        for (let i = 0; i < paths.length; i++)
            state[paths[i]] = readPath(paths[i]);
        // Live session flags the offline CLI cannot know (documented):
        state._gamemode = GameMode.enabled;
        state._light = Colours.light;
        return state;
    }

    function _pathsIn(expr) {
        const out = [];
        const re = /([A-Za-z_][\w.]*)/g;
        let m;
        while ((m = re.exec(expr)) !== null) {
            if (m[1] !== "true" && m[1] !== "false" && out.indexOf(m[1]) === -1)
                out.push(m[1]);
        }
        return out;
    }

    function _evalWhen(rule, state) {
        // Restricted predicate grammar: `path == value`, `!=`, `>`, `<`
        // joined by ` and ` (see curations.EXPLAIN_RULES). Unknown state
        // keys make the rule NOT fire (offline honesty), never guess.
        const clauses = String(rule.when).split(" and ");
        for (let i = 0; i < clauses.length; i++) {
            const m = clauses[i].match(/^\s*([\w.]+)\s*(==|!=|>|<)\s*(.+?)\s*$/);
            if (!m)
                return false;
            const have = state[m[1]];
            if (have === undefined || have === null)
                return false;
            let want = m[3];
            let wantV;
            if (want === "true") wantV = true;
            else if (want === "false") wantV = false;
            else if (/^-?\d+(\.\d+)?$/.test(want)) wantV = Number(want);
            else wantV = want.replace(/^["']|["']$/g, "");
            let r;
            if (m[2] === "==") r = _valuesEqual(have, wantV);
            else if (m[2] === "!=") r = !_valuesEqual(have, wantV);
            else if (m[2] === ">") r = have > wantV;
            else r = have < wantV;
            if (!r)
                return false;
        }
        return true;
    }

    function _valuesEqual(have, wantV) {
        if (have === wantV)
            return true;
        if (typeof have === "number" && typeof wantV === "number"
            && Math.abs(have - wantV) < 1e-9)
            return true;
        if (typeof have === "boolean" && typeof wantV === "string")
            return String(have) === wantV;
        return false;
    }

    function _fmtVal(v) {
        if (v === true) return "on";
        if (v === false) return "off";
        if (typeof v === "number") {
            const r = Math.round(v * 100) / 100;
            return String(r);
        }
        return String(v);
    }

    function _renderAnswer(template, state, cites) {
        let out = String(template);
        // {a|b} alternation: resolve against the first numeric value
        // placeholder in the template (> its "neutral" 1 -> first option).
        const valPh = out.match(/\{[A-Za-z_][\w.]*\}/);
        let firstNum = null;
        if (valPh) {
            const key = valPh[0].slice(1, -1);
            if (typeof state[key] === "number")
                firstNum = state[key];
        }
        out = out.replace(/\{([^{}|]+)\|([^{}]+)\}/g, (match, a, b) =>
            (firstNum !== null && firstNum > 1) ? a : b);
        // {citeN} / {cite}
        out = out.replace(/\{cite(\d*)\}/g, (match, d) => {
            const idx = d ? (parseInt(d, 10) - 1) : 0;
            return cites[idx] !== undefined ? cites[idx] : (cites[0] || "");
        });
        // {dotted.path} value placeholders
        out = out.replace(/\{([A-Za-z_][\w.]*)\}/g, (match, key) =>
            state[key] !== undefined ? _fmtVal(state[key]) : match);
        return out;
    }

    function explain(path) {
        const t = toolsByPath[path] !== undefined ? toolsByPath[path]
                  : toolsByName[path] !== undefined ? toolsByName[path] : null;
        if (!t)
            return { ok: false, reason: `unknown setting ${path}` };
        const needed = [t.p];
        for (let i = 0; i < explainTable.length; i++) {
            const rule = explainTable[i];
            if (rule.path !== t.p)
                continue;
            const paths = _pathsIn(rule.when);
            for (let j = 0; j < paths.length; j++)
                if (needed.indexOf(paths[j]) === -1)
                    needed.push(paths[j]);
        }
        const state = _liveState(needed);
        for (let i = 0; i < explainTable.length; i++) {
            const rule = explainTable[i];
            if (rule.path !== t.p)
                continue;
            if (_evalWhen(rule, state)) {
                const answer = _renderAnswer(rule.answer, state, rule.cites);
                return { ok: true, answer: answer, cites: rule.cites, rule: true };
            }
        }
        const value = readPath(t.p);
        const cite = (t.c && t.c.length) ? t.c[0][0] : "";
        let validation;
        if (t.k === "enum") validation = `one of ${(t.en || []).join("|")}`;
        else if (t.k === "bool") validation = "on/off";
        else if (t.k === "string") validation = `string <= ${t.sl || 64} chars`;
        else validation = `range ${t.lo}-${t.hi}`;
        const shown = value === null ? t.d : value;
        return {
            ok: true,
            answer: `The ${t.p} is currently set to ${_fmtVal(shown)} `
                  + `(${validation}, default ${_fmtVal(t.d)}${cite ? `; ${cite}` : ""}).`,
            cites: t.c || [], rule: false
        };
    }

    // ---- presets (bundles of validated tool calls only) ----------------------

    function presetList() {
        return presetTable.map(p => ({
            name: p.name, label: p.label, description: p.description,
            calls: p.calls.length
        }));
    }

    function requestPreset(name) {
        const p = presetTable.find(x => x.name === name);
        if (!p)
            return { ok: false, reason: `unknown preset ${name}` };
        const calls = p.calls.map(c => ({ name: c[0], value: c[1] }));
        // Presets are multi-op by construction -> always the confirm flow.
        return request(calls, `preset: ${p.label}`);
    }

    FileView {
        id: historyFile

        printErrors: false
        path: root.historyPath
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (Array.isArray(data))
                    root.history = data.slice(0, root.maxHistory);
            } catch (e) {
                root.history = [];
            }
        }
    }
}
