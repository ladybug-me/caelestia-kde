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

    property var openWindow: null

    function create(parent: Item, props: var): var {
        props = props || {};
        if (root.openWindow) {
            const win = root.openWindow;
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

            function raise(): void {
                const pageTitles = PageRegistry.pages.map(p => p.label);
                const target = Kwin.windowList.find(w => w.title === win.title || (pageTitles.includes(w.title) && w.class && w.class.includes("quickshell")));
                if (target?.address)
                    Kwin.focusWindow(target.address);
            }

            Component.onDestruction: {
                if (root.openWindow === win)
                    root.openWindow = null;
            }

            color: Colours.tPalette.m3surface
            // Commented because nexus bg depends on the above
            // color: GlobalConfig.appearance.transparency.enabled ? Qt.alpha(Colours.tPalette.m3surface, 0) : Colours.tPalette.m3surface

            surfaceFormat.opaque: false

            BackgroundEffect.blurRegion: Region {
                Region { x: -10; y: -10; width: 1; height: 1 }
                Region { item: (GlobalConfig.appearance.transparency.enabled && GlobalConfig.appearance.blur) ? nexus : null }
            }

            onVisibleChanged: {
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
