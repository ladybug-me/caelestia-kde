pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus

Singleton {
    id: root

    property var openWindow: null
    readonly property bool openWindowActive: root.openWindow !== null && root.openWindow.nexus.windowActive

    function create(parent: Item, props: var): var {
        props = props || {};
        if (root.openWindow) {
            const win = root.openWindow;
            if (props.initialPageIdx !== undefined) {
                const pageIdx = typeof props.initialPageIdx === "string"
                    ? PageRegistry.indexForKey(props.initialPageIdx)
                    : props.initialPageIdx;
                win.nexus.nState.goToSubPage(pageIdx, props.initialSubPageIdx ?? -1);
            }
            win.visible = true;
            win.raise();
            Logger.mark("nexus=reused");
            return win;
        }
        const resolvedProps = Object.assign({}, props);
        if (typeof resolvedProps.initialPageIdx === "string")
            resolvedProps.initialPageIdx = PageRegistry.indexForKey(resolvedProps.initialPageIdx);
        const win = nexusComp.createObject(parent ?? dummy, resolvedProps);
        root.openWindow = win;
        Logger.mark("nexus=created");
        return win;
    }

    function close(): void {
        if (root.openWindow)
            root.openWindow.destroy();
    }
    function openBarSettings(target: int): void {
        const win = root.create(null, {
            initialPageIdx: "panels"
        });

        if (!win || !win.nexus)
            return;

        const nState = win.nexus.nState;
        nState.extraBarsTarget = target;
        nState.openSubPage("extraBars");
    }

    function openBarComponents(target: int): void {
        const win = root.create(null, {
            initialPageIdx: "panels"
        });

        if (!win || !win.nexus)
            return;

        const nState = win.nexus.nState;
        nState.barComponentsTarget = target;

        if (target >= 0)
            nState.openSubPage("extraBars");

        nState.openSubPage("barComponents");
    }

    function goBack(): void {
        if (!root.openWindow)
            return;
        const state = root.openWindow.nexus.nState;
        if (state.subPageIdxStack.length > 0)
            state.closeSubPage();
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
            property var initialSubPageIdx: -1

            function raise(): void {
                const pageTitles = PageRegistry.pages.map(p => p.label);
                const target = Kwin.windowList.find(w => w.title === win.title || (pageTitles.includes(w.title) && w.class && w.class.includes("quickshell")));
                if (target?.address)
                    Kwin.focusWindow(target.address);
            }

            Component.onDestruction: {
                Logger.mark("nexus=destroyed");
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
