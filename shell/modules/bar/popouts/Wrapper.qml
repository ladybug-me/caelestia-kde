pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.windowinfo

Item {
    id: root

    required property ShellScreen screen
    required property real offsetScale
    required property DrawerVisibilities visibilities
    Config.screen: root.screen.name
    readonly property alias content: content
    readonly property alias winfo: winfo
    readonly property real nonAnimWidth: content.shouldBeActive ? content.implicitWidth : winfo.shouldBeActive ? winfo.implicitWidth : content.implicitWidth
    readonly property real nonAnimHeight: content.shouldBeActive ? content.implicitHeight : winfo.shouldBeActive ? winfo.implicitHeight : content.implicitHeight
    readonly property Item current: (content.item as Content)?.current ?? null
    readonly property bool isDetached: detachedMode.length > 0
    readonly property bool sidebarOpen: popoutState.sidebarOpen
    readonly property bool isDockPopout: currentName === "dockhover" || currentName === "dockcontext" || currentName === "greeter" || currentName === "greetercontext" || currentName === "activewindow" || currentName === "github" || currentName === "updateIndicator" || currentName === "clock" || currentName === "clockcontext"
    property alias currentName: popoutState.currentName
    property alias hasCurrent: popoutState.hasCurrent
    property alias dockModel: popoutState.dockModel
    property alias tasksModel: popoutState.tasksModel
    property real currentCenter
    property string detachedMode
    // Dummy object so Tokens attached prop resolves to global config
    // Anim configs are not per-monitor
    readonly property QtObject dummy: QtObject {}
    property int animLength: dummy.Tokens.anim.durations.expressiveDefaultSpatial
    property var animCurve: dummy.Tokens.anim.expressiveDefaultSpatial // The easingCurve type is Qt 6.11+ so we gotta use var for now

    function setAnims(detach: bool): void {
        const type = `expressive${detach ? "Slow" : "Default"}Spatial`;
        animLength = dummy.Tokens.anim.durations[type];
        animCurve = dummy.Tokens.anim[type];
    }
    function detach(mode: string): void {
        setAnims(true);
        if (mode === "winfo") {
            detachedMode = mode;
            focus = true;
        } else {
            // The mode string is a page key; the registry owns the position.
            const pageIdx = PageRegistry.indexForKey(mode);
            WindowFactory.create(null, { initialPageIdx: pageIdx >= 0 ? pageIdx : 0 });
            close();
        }
        setAnims(false);
    }
    function close(): void {
        hasCurrent = false;
        detachedMode = "";
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight
    focus: hasCurrent
    Keys.onEscapePressed: {
        // Forward escape to password popout if active, otherwise close
        if (currentName === "wirelesspassword" && content.item) {
            const passwordPopout = (content.item as Content)?.children.find(c => c.name === "wirelesspassword");
            if (passwordPopout && passwordPopout.item) {
                passwordPopout.item.closeDialog();
                return;
            }
        }
        close();
    }
    Keys.onPressed: event => {
        // Don't intercept keys when password popout is active - let it handle them
        if (currentName === "wirelesspassword") {
            event.accepted = false;
        }
    }

    PopoutState {
        id: popoutState

        sidebarOpen: root.visibilities.sidebar
        isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"
        onDetachRequested: mode => root.detach(mode)
    }
    HyprlandFocusGrab {
        active: root.isDetached
        windows: [QsWindow.window]
        onCleared: root.close()
    }
    Binding {
        when: root.isDetached || (root.hasCurrent && root.currentName === "wirelesspassword")
        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }
    Comp {
        id: content

        shouldBeActive: root.hasCurrent && !root.detachedMode
        anchors.fill: parent
        sourceComponent: Content {
            popouts: popoutState
        }
    }
    Comp {
        id: winfo

        shouldBeActive: root.detachedMode === "winfo"
        anchors.centerIn: parent
        sourceComponent: WindowInfo {
            clientAddress: popoutState.selectedClientAddress
        }
        onShouldBeActiveChanged: {
            if (!shouldBeActive) {
                popoutState.selectedClientAddress = "";
            }
        }
    }
    Behavior on implicitWidth {
        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }
    Behavior on implicitHeight {
        enabled: root.offsetScale < 1

        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    component Comp: Loader {
        id: comp

        property bool shouldBeActive

        active: false
        opacity: 0
        // Makes the loader load on the same frame shouldBeActive becomes true, which ensures size is set
        states: State {
            name: "active"
            when: comp.shouldBeActive

            PropertyChanges {
                comp.opacity: 1
                comp.active: true
            }
        }
        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }
}
