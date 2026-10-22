pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Caelestia.Config
import qs.components
import qs.modules.nexus

StackView {
    id: root

    required property NexusState nState
    default property list<QtObject> pages
    readonly property int animMovement: Tokens.padding.extraExtraLarge * 2
    readonly property var slotMap: ({})

    function buildSlotMap(): void {
        for (let i = 0; i < pages.length; i++) {
            const item = pages[i];
            if (!item)
                continue;
            if (item.component !== undefined) {
                const s = item.slot >= 0 ? item.slot : i;
                slotMap[s] = item.component;
                if (item.key)
                    slotMap[item.key] = item.component;
            } else {
                slotMap[i] = item;
            }
        }
    }

    function openSubPage(target: var, immediate: bool): void {
        const page = slotMap[target] ?? (typeof target === "number" ? pages[target] : null);
        if (page) {
            push(page, {
                nState
            }, immediate ? StackView.Immediate : StackView.PushTransition);
        } else {
            console.warn(logCat, "Attempted to open invalid sub-page slot/key:", target);
            nState.closeSubPage();
        }
    }

    clip: busy

    Component.onCompleted: {
        root.buildSlotMap();
        root.openSubPage(0, true);
        if (nState.pendingSubPageIdx >= 0) {
            const pending = nState.pendingSubPageIdx;
            nState.pendingSubPageIdx = -1;
            nState.subPageIdxStack.push(pending);
        }
        for (const page of nState.subPageIdxStack)
            root.openSubPage(page, true);
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
        function onSubPageOpened(target: var): void {
            root.openSubPage(target, false);
        }

        function onSubPageClosed(): void {
            if (root.depth < root.nState.subPageIdxStack.length) {
                console.log(logCat, "Attempted to close page while depth < stack depth. Ignoring.");
                return;
            }
            root.pop();
        }

        target: root.nState
    }
}
