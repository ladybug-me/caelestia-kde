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
                const isKey = typeof props.initialPageIdx === "string";
                const pageIdx = isKey
                    ? PageRegistry.indexForKey(props.initialPageIdx)
                    : props.initialPageIdx;
                const rawSub = (props.initialSubPageIdx !== undefined && props.initialSubPageIdx !== -1)
                    ? props.initialSubPageIdx
                    : (isKey ? PageRegistry.defaultSubPageForKey(props.initialPageIdx) : -1);
                const subIdx = (typeof rawSub === "number") ? rawSub : PageDictionary.defaultSubPageForKey(rawSub);
                win.nexus.nState.goToSubPage(pageIdx, subIdx);
            }
            win.visible = true;
            win.raise();
            win.nexus.forceActiveFocus();
            Logger.mark("nexus=reused");
            return win;
        }
        const resolvedProps = Object.assign({}, props);
        if (typeof resolvedProps.initialPageIdx === "string") {
            const key = resolvedProps.initialPageIdx;
            resolvedProps.initialPageIdx = PageRegistry.indexForKey(key);
            if (resolvedProps.initialSubPageIdx === undefined || resolvedProps.initialSubPageIdx === -1)
                resolvedProps.initialSubPageIdx = PageRegistry.defaultSubPageForKey(key);
        }
        if (typeof resolvedProps.initialSubPageIdx === "string") {
            const mapped = PageDictionary.defaultSubPageForKey(resolvedProps.initialSubPageIdx);
            if (mapped >= 0)
                resolvedProps.initialSubPageIdx = mapped;
        }
        const win = nexusComp.createObject(parent ?? dummy, resolvedProps);
        root.openWindow = win;
        if (win) {
            win.visible = true;
            Qt.callLater(win.raise);
        }
        Logger.mark("nexus=created");
        return win;
    }

    function close(): void {
        if (root.openWindow)
            root.openWindow.destroy();
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

            visible: true

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

            minimumSize.width: Math.max(1050, Tokens.sizes.nexus.minWidth)
            minimumSize.height: Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen ? screen.name : (Screens.activeScreen?.name ?? "")
            contentItem.Tokens.screen: screen ? screen.name : (Screens.activeScreen?.name ?? "")

            title: PageRegistry.pages[nexus.nState.currentPageIdx] ? PageRegistry.pages[nexus.nState.currentPageIdx].label : "Nexus"

            Nexus {
                id: nexus

                anchors.fill: parent
                initialPageIdx: win.initialPageIdx
                initialSubPageIdx: win.initialSubPageIdx
                nState.screen: win.screen ?? Screens.activeScreen ?? Quickshell.screens[0]
                nState.isWindow: true
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
