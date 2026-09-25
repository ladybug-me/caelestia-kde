pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components

Item {
    id: root

    required property PopoutState popouts
    readonly property Popout currentPopout: content.children.find(c => c.shouldBeActive) ?? null
    readonly property Item current: currentPopout?.item ?? null

    // Tray menu popouts are looked up by name, and the list that opens them
    // (Tray.qml) is filtered differently from the list that publishes them here
    // (only items with a menu), so a positional index would drift: name them by
    // item id via the index in the bar's own filtered list.
    readonly property var trayItemsToIndices: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id)).reduce((acc, item, i) => {
        acc[item.id] = i;
        return acc;
    }, {})

    readonly property real contentMargin: Tokens.padding.large * (currentPopout?.item?.scaleOffset ?? 1.0)
    readonly property real availableWidth: Math.max(0, ((QsWindow.window as QsWindow)?.screen?.width ?? 0) - contentMargin * 2 - Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0))
    readonly property real availableHeight: Math.max(0, ((QsWindow.window as QsWindow)?.screen?.height ?? 0) - contentMargin * 2 - Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0))

    implicitWidth: Math.min(((currentPopout?.item?.width || currentPopout?.implicitWidth) ?? 0) + Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0), availableWidth)
    implicitHeight: Math.min(((currentPopout?.item?.height || currentPopout?.implicitHeight) ?? 0) + Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0), availableHeight)

    Flickable {
        id: viewport

        anchors.fill: parent
        anchors.margins: root.contentMargin

        clip: true
        contentWidth: width
        contentHeight: Math.max(height, content.implicitHeight)

        Item {
            id: content

            width: viewport.width
            height: Math.max(viewport.height, implicitHeight)
            implicitHeight: currentPopout?.item?.implicitHeight ?? 0

        Popout {
            name: "greeter"
            previewKey: "greeter"
            sourceComponent: Greeter {
                popouts: root.popouts
            }
        }

        Popout {
            name: "greetercontext"
            previewKey: "greeter"
            sourceComponent: GreeterContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "activewindow"
            previewKey: "greeter"
            sourceComponent: Greeter {
                popouts: root.popouts
            }
        }

        Popout {
            id: networkPopout

            name: "network"
            sourceComponent: Network {
                popouts: root.popouts
                view: "wireless"
            }
        }

        Popout {
            name: "ethernet"
            previewKey: "network"
            sourceComponent: Network {
                popouts: root.popouts
                view: "ethernet"
            }
        }

        Popout {
            id: passwordPopout

            name: "wirelesspassword"
            previewKey: "network"
            sourceComponent: WirelessPassword {
                id: passwordComponent

                popouts: root.popouts
            }
        }

        Popout {
            name: "bluetooth"
            sourceComponent: Bluetooth {
                popouts: root.popouts
            }
        }

        Popout {
            name: "clock"
            sourceComponent: CalendarPopout {
                popouts: root.popouts
            }
        }

        Popout {
            name: "clockcontext"
            previewKey: "clock"
            sourceComponent: ClockContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "battery"
            sourceComponent: Battery {
                popouts: root.popouts
            }
        }

        Popout {
            name: "peripheralBattery"
            sourceComponent: PeripheralBattery {
            }
        }

        Popout {
            name: "github"
            sourceComponent: Github {
                popouts: root.popouts
            }
        }

        Popout {
            name: "updateIndicator"
            sourceComponent: Updates {
                popouts: root.popouts
            }
        }

        Popout {
            name: "audio"
            // Audio controls need a readable minimum size even when bar
            // preview scaling is configured for compact indicators.
            minScale: 0.9
            sourceComponent: Audio {
                popouts: root.popouts
            }
        }

        Popout {
            name: "nightlight"
            sourceComponent: NightLight {
                popouts: root.popouts
            }
        }

        Popout {
            name: "kblayout"
            sourceComponent: KbLayout {
                popouts: root.popouts
            }
        }

        Popout {
            name: "lockstatus"
            previewKey: "lockStatus"
            sourceComponent: LockStatus {
                popouts: root.popouts
            }
        }

        Popout {
            name: "notifications"
            sourceComponent: Notifications {
                popouts: root.popouts
            }
        }

        Popout {
            name: "dockhover"
            previewKey: "dock"
            sourceComponent: DockHover {
                popouts: root.popouts
            }
        }

        Popout {
            name: "dockcontext"
            previewKey: "dock"
            sourceComponent: DockContext {
                popouts: root.popouts
            }
        }

        Repeater {
            model: ScriptModel {
                values: SystemTray.items.values.filter(i => i.hasMenu && i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            Popout {
                id: trayMenu

                required property SystemTrayItem modelData

                name: `traymenu${root.trayItemsToIndices[modelData.id]}`
                previewKey: "trayMenu"
                sourceComponent: trayMenuComp

                Connections {
                    function onHasCurrentChanged(): void {
                        if (root.popouts.hasCurrent && trayMenu.shouldBeActive) {
                            trayMenu.sourceComponent = null;
                            trayMenu.sourceComponent = trayMenuComp;
                        }
                    }

                    target: root.popouts
                }

                Component {
                    id: trayMenuComp

                    TrayMenu {
                        popouts: root.popouts
                        trayItem: trayMenu.modelData.menu // qmllint disable unresolved-type
                    }
                }
            }
        }
    }
    }

    component Popout: Loader {
        id: popout

        required property string name
        // Key into GlobalConfig.bar.previewScales/previewFontScales. Defaults to
        // the popout name; a missing key degrades to 0.0, matching the old
        // hardcoded per-popout preambles.
        property string previewKey: name
        // Per-popout minimum scale clamp. Audio needs a readable minimum even
        // when bar preview scaling is configured for compact indicators.
        property real minScale: 0.1
        readonly property bool shouldBeActive: root.popouts.currentName === name

        readonly property real masterScale: !isNaN(GlobalConfig.bar.previewScale) ? GlobalConfig.bar.previewScale : 1.0
        readonly property real elementOffset: GlobalConfig.bar.perElementPreviewScale ? (!isNaN(GlobalConfig.bar.previewScales[previewKey]) ? GlobalConfig.bar.previewScales[previewKey] : 0.0) : 0.0
        readonly property real barScaleOffset: GlobalConfig.bar.previewScaleWithBar ? (!isNaN(GlobalConfig.bar.scale) ? GlobalConfig.bar.scale : 1.0) : 1.0
        readonly property real scaleOffset: Math.max(minScale, (masterScale + elementOffset) * barScaleOffset)
        readonly property real elementFontOffset: GlobalConfig.bar.perElementFontScale ? (!isNaN(GlobalConfig.bar.previewFontScales[previewKey]) ? GlobalConfig.bar.previewFontScales[previewKey] : 0.0) : 0.0
        readonly property real fontScale: Math.max(0.1, scaleOffset + (!isNaN(GlobalConfig.bar.fontScaleOffset) ? GlobalConfig.bar.fontScaleOffset : 0.0) + elementFontOffset)
        readonly property bool sidebarOpen: root.popouts.sidebarOpen && root.popouts.isHorizontal

        anchors.centerIn: parent

        opacity: 0
        active: false

        states: State {
            name: "active"
            when: popout.shouldBeActive

            PropertyChanges {
                popout.active: true
                popout.opacity: 1
            }
        }

        transitions: [
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        property: "opacity"
                        type: Anim.DefaultEffects
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            },
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        property: "opacity"
                        type: Anim.SlowEffects
                    }
                }
            }
        ]

        Binding {
            when: popout.item !== null
            target: popout.item
            property: "scaleOffset"
            value: popout.scaleOffset
        }

        Binding {
            when: popout.item !== null
            target: popout.item
            property: "fontScale"
            value: popout.fontScale
        }

        Binding {
            when: popout.item !== null
            target: popout.item
            property: "_isSidebarOpen"
            value: popout.sidebarOpen
        }
    }
}
