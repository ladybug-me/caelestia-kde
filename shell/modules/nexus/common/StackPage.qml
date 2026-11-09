pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Caelestia.Config
import qs.components
import qs.modules.nexus

StackView {
    id: root

    required property NexusState nState
    property var pages: []
    readonly property int animMovement: Tokens.padding.extraExtraLarge * 2
    readonly property var pageMap: ({})
    // set by Pages so the outgoing page ignores the nav signals of the page that replaces it
    property int pageIdx: -1

    function buildPageMap(): void {
        for (let i = 0; i < pages.length; i++) {
            const item = pages[i];
            if (!item || !item.key)
                continue;
            pageMap[item.key] = item.component ?? item;
        }
    }

    function openSubPage(target: string, immediate: bool): void {
        const page = pageMap[target];
        if (page) {
            push(page, {
                nState
            }, immediate ? StackView.Immediate : StackView.PushTransition);
        } else {
            console.warn(logCat, "Attempted to open invalid sub-page key:", target);
            nState.closeSubPage();
        }
    }

    function switchToPage(target: string): void {
        const page = pageMap[target];
        if (page) {
            root.popToIndex(0, StackView.Immediate);
            root.replace(page, {
                nState
            }, StackView.Immediate);
        }
    }

    clip: busy

    Component.onCompleted: {
        if (!pages || pages.length === 0) {
            pages = root.pageIdx >= 0 ? PageCompRegistry.collectAllPagesForCategory(root.pageIdx) : [];
        }
        root.buildPageMap();
        const baseKey = nState.activeSubPageKey !== ""
            ? nState.activeSubPageKey
            : nState.defaultPageForCategory(root.pageIdx);
        root.openSubPage(baseKey, true);
        if (nState.pendingSubPageKey !== "") {
            const pending = nState.pendingSubPageKey;
            nState.pendingSubPageKey = "";
            if (pending !== baseKey && nState.subPageKeyStack.indexOf(pending) < 0) {
                nState.subPageKeyStack.push(pending);
            }
        }
        for (let i = 0; i < nState.subPageKeyStack.length; i++) {
            const pageKey = nState.subPageKeyStack[i];
            if (pageKey !== baseKey) {
                root.openSubPage(pageKey, true);
            }
        }
    }

    pushEnter: Transition {
        SequentialAnimation {
            PropertyAction {
                property: "opacity"
                value: 0
            }
            PauseAnimation {
                duration: Tokens.anim.durations.expressiveDefaultEffects
            }
            ParallelAnimation {
                Anim {
                    property: "opacity"
                    to: 1
                    type: Anim.SlowEffects
                }
                Anim {
                    property: "x"
                    from: root.animMovement
                    to: 0
                    type: Anim.SlowEffects
                }
            }
        }
    }

    pushExit: Transition {
        Anim {
            property: "opacity"
            to: 0
            type: Anim.DefaultEffects
        }
    }

    popEnter: Transition {
        SequentialAnimation {
            PropertyAction {
                property: "opacity"
                value: 0
            }
            PauseAnimation {
                duration: Tokens.anim.durations.expressiveDefaultEffects
            }
            ParallelAnimation {
                Anim {
                    property: "opacity"
                    to: 1
                    type: Anim.SlowEffects
                }
                Anim {
                    property: "x"
                    from: -root.animMovement
                    to: 0
                    type: Anim.SlowEffects
                }
            }
        }
    }

    popExit: Transition {
        Anim {
            property: "opacity"
            to: 0
            type: Anim.DefaultEffects
        }
    }

    LoggingCategory {
        id: logCat

        name: "caelestia.nexus"
        defaultLogLevel: LoggingCategory.Info
    }

    Connections {
        function onSubCategorySelected(target: string): void {
            // read the live value: a cached binding is stale while currentPageIdx is still notifying
            if (root.pageIdx >= 0 && root.pageIdx !== root.nState.currentPageIdx)
                return;
            root.switchToPage(target);
        }

        function onSubPageOpened(target: string): void {
            root.openSubPage(target, false);
        }

        function onSubPageClosed(): void {
            if (root.depth < root.nState.subPageKeyStack.length) {
                console.log(logCat, "Attempted to close page while depth < stack depth. Ignoring.");
                return;
            }
            root.pop();
        }

        function onSubPagesCleared(): void {
            root.popToIndex(0, StackView.Immediate);
        }

        target: root.nState
    }
}
