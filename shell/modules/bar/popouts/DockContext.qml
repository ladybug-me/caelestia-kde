pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts
    property var model: popouts.dockModel

    property bool isPinned: {
        if (!model)
            return false;
        const current = GlobalConfig.bar.dock.pinnedApps || [];
        for (let i = 0; i < current.length; i++) {
            if (model.id === current[i] || (model.entry && model.entry.id === current[i])) {
                return true;
            }
        }
        return false;
    }

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    /// The names this application is known by, for the recent-documents lookup: the
    /// desktop entry id, the window class, and whatever the menu model carries.
    readonly property var appNames: [model?.id, model?.appClass, model?.entry?.id].filter(name => typeof name === "string" && name.length > 0)

    /// Whether the overview would show anything for this application when opened from
    /// here: it opens on the active workspace, so windows parked elsewhere do not count.
    readonly property bool hasWindows: {
        const wins = Kwin.filterWindows(Kwin.windowList || [], Kwin.activeWsId, "");
        return wins.some(w => Kwin.windowMatchesApp(w, root.appNames));
    }

    function loadRecents(): void {
        Recents.load(root.appNames);
    }

    function openRecent(entry: var): void {
        Launch.exec(["xdg-open", entry.path]);
        root.popouts.hasCurrent = false;
    }

    onAppNamesChanged: root.loadRecents()
    Component.onCompleted: root.loadRecents()

    width: 200 * scaleOffset
    implicitWidth: 200 * scaleOffset
    spacing: Tokens.spacing.medium * scaleOffset

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true
        visible: model && model.entry != null

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.small * root.scaleOffset

            DockAction {
                label: root.isPinned ? qsTr("Unpin from dock") : qsTr("Pin to dock")
                scaleOffset: root.scaleOffset
                fontScale: root.fontScale

                onActivated: {
                    const current = GlobalConfig.bar.dock.pinnedApps ? [...GlobalConfig.bar.dock.pinnedApps] : [];
                    const idToPin = model.entry ? model.entry.id : model.id;

                    if (root.isPinned) {
                        let index = current.indexOf(model.id);
                        if (index === -1)
                            index = current.indexOf(idToPin);
                        if (index !== -1) {
                            current.splice(index, 1);
                            GlobalConfig.bar.dock.pinnedApps = current;
                        }
                    } else if (!current.includes(idToPin)) {
                        current.push(idToPin);
                        GlobalConfig.bar.dock.pinnedApps = current;
                    }

                    root.popouts.hasCurrent = false;
                }
            }

            DockAction {
                visible: root.hasWindows
                label: qsTr("Show all windows")
                scaleOffset: root.scaleOffset
                fontScale: root.fontScale

                onActivated: {
                    Visibilities.showAppWindows(root.appNames);
                    root.popouts.hasCurrent = false;
                }
            }

            DockAction {
                label: qsTr("Open new window")
                scaleOffset: root.scaleOffset
                fontScale: root.fontScale

                onActivated: {
                    if (model.entry)
                        Launch.launchEntry(model.entry);

                    root.popouts.hasCurrent = false;
                }
            }
        }
    }

    // Jump list: what this application opened last, straight out of the freedesktop
    // recent-documents list. Absent when the application has no history or the list
    // does not name it.
    StyledRect {
        Layout.fillWidth: true
        visible: Recents.entries.length > 0
        implicitHeight: recentLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: recentLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Recent files")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Repeater {
                model: ScriptModel {
                    values: [...Recents.entries]
                }

                delegate: StyledRect {
                    id: recentRow

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: recentLabel.implicitHeight + Tokens.padding.small * root.scaleOffset
                    radius: Tokens.rounding.full
                    color: "transparent"

                    StateLayer {
                        anchors.fill: parent
                        radius: recentRow.radius
                        onClicked: root.openRecent(recentRow.modelData)
                    }

                    StyledText {
                        id: recentLabel

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: recentRow.modelData.name
                        elide: Text.ElideMiddle
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }
        }
    }

    IconTextButton {
        Layout.fillWidth: true
        inactiveColour: Colours.palette.m3primaryContainer
        inactiveOnColour: Colours.palette.m3onPrimaryContainer
        verticalPadding: Tokens.padding.small * root.scaleOffset
        text: qsTr("End task")
        icon: "close"
        visible: {
            if (!model || !model.toplevels || model.toplevels.length === 0) return false;
            return !model.toplevels.some(t => t.title && String(t.title).startsWith("Nexus"));
        }
        onClicked: {
            for (const toplevel of model.toplevels) {
                if (toplevel.pid) {
                    Quickshell.execDetached({ command: ["kill", "-15", String(toplevel.pid)] });
                } else if (Kwin.windowList.length > 0) {
                    Kwin.closeWindow(toplevel.address);
                } else {
                    Kwin.dispatch(Kwin.usingLua ? `hl.dsp.window.close({ window = "address:0x${toplevel.address}" })` : `closewindow address:0x${toplevel.address}`);
                }
            }
            root.popouts.hasCurrent = false;
        }
    }

    /// One tappable line in the application card. The menu is a list of these, and
    /// only what it says and does differs.
    component DockAction: StyledRect {
        id: action

        required property string label
        property real scaleOffset: 1
        property real fontScale: 1

        signal activated

        Layout.fillWidth: true
        implicitHeight: actionLabel.implicitHeight
        radius: Tokens.rounding.full
        color: "transparent"

        StateLayer {
            anchors.margins: -Tokens.padding.medium / 2 * action.scaleOffset
            anchors.leftMargin: -Tokens.padding.medium * action.scaleOffset
            anchors.rightMargin: -Tokens.padding.medium * action.scaleOffset

            radius: action.radius

            onClicked: action.activated()
        }

        StyledText {
            id: actionLabel

            anchors.left: parent.left
            text: action.label
            font.pointSize: Tokens.font.body.medium.pointSize * action.fontScale
        }
    }
}
