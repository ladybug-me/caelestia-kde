pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    // The one detached Nexus window, if open. Reused so repeated detach /
    // "Open Updates" clicks navigate the existing window instead of stacking.
    property var openWindow: null

    function create(parent: Item, props: var): var {
        props = props || {};
        if (root.openWindow) {
            const win = root.openWindow;
            // Handles the sub-page as well: the page swap is animated, so
            // opening it straight after the page change reaches the page that
            // is on its way out instead of the one arriving.
            if (props.initialPageIdx !== undefined)
                win.nexus.nState.goToSubPage(props.initialPageIdx, props.initialSubPageIdx ?? -1);
            win.visible = true;
            win.raise();
            return win;
        }
        const win = nexusComp.createObject(parent ?? dummy, props);
        root.openWindow = win;
        return win;
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            property alias nexus: nexus

            property int initialPageIdx: 0
            property int initialSubPageIdx: -1

            Component.onDestruction: {
                if (root.openWindow === win)
                    root.openWindow = null;
            }

            color: Colours.tPalette.m3surface

            surfaceFormat.opaque: false

            BackgroundEffect.blurRegion: Region {
                Region { x: -10; y: -10; width: 1; height: 1 } // Prevent full-window blur fallback when disabled
                Region { item: (GlobalConfig.appearance.transparency.enabled && GlobalConfig.appearance.blur) ? nexus : null }
            }

            onVisibleChanged: {
                // Some Quickshell versions do not expose a cancellable close
                // signal on FloatingWindow. If the window is being hidden while
                // an update runs, reopen and route through Nexus' close guard.
                if (!visible && UpdateChecker.updateRunning) {
                    visible = true;
                    nexus.requestClose();
                    return;
                }

                if (!visible)
                    destroy();
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: Tokens.sizes.nexus.minWidth
            minimumSize.height: Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: PageRegistry.pages[nexus.nState.currentPageIdx].label

            Nexus {
                id: nexus

                anchors.fill: parent
                initialPageIdx: win.initialPageIdx
                initialSubPageIdx: win.initialSubPageIdx
                nState.screen: win.screen
                nState.isWindow: true
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
