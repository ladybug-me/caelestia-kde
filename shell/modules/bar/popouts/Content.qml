pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.services as QsServices

// Aliased on purpose: qs.services declares singletons named after some of the
// popouts this file instantiates (Weather, Audio), and an unqualified import
// would make those names resolve to the services instead of the local
// components.
Item {
    id: root

    required property PopoutState popouts
    required property DrawerVisibilities visibilities
    readonly property Popout currentPopout: content.children.find(c => c.shouldBeActive) ?? null
    readonly property Item current: currentPopout?.item ?? null
    readonly property bool currentIsContext: currentPopout?.isContext ?? false

    readonly property real contentMargin: Tokens.padding.large * (currentPopout?.item?.scaleOffset ?? 1.0)
    readonly property real availableWidth: Math.max(0, ((QsWindow.window as QsWindow)?.screen?.width ?? 0) - contentMargin * 2 - Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0))
    readonly property real availableHeight: Math.max(0, ((QsWindow.window as QsWindow)?.screen?.height ?? 0) - contentMargin * 2 - Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0))

    // Built-in popouts are handed the values they need one by one in their own
    // entry. Plugin popouts are plain components, so the values they declare
    // are filled in here instead and the rest are left alone.
    function applyPopoutContext(popout: var): void {
        if (!popout)
            return;

        const context = {
            popouts: root.popouts,
            visibilities: root.visibilities
        };

        for (const name in context)
            if (popout.hasOwnProperty(name))
                popout[name] = context[name];
    }

    implicitWidth: Math.min(((currentPopout?.item?.width || currentPopout?.implicitWidth) ?? 0) + Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0), availableWidth)
    implicitHeight: Math.min(((currentPopout?.item?.height || currentPopout?.implicitHeight) ?? 0) + Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0), availableHeight)

    Flickable {
        id: viewport

        anchors.fill: parent
        anchors.margins: root.contentMargin

        clip: true
        boundsBehavior: Flickable.StopAtBounds
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
            name: "barcontext"
            isContext: true
            sourceComponent: BarContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "greetercontext"
            isContext: true
            previewKey: "greeter"
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Greeter settings")
                subPageIdx: 8
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
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
            isContext: true
            previewKey: "clock"
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Clock settings")
                subPageIdx: 11
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "osiconcontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Launcher settings")
                subPageIdx: 3
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "statusiconscontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Status icons settings")
                subPageIdx: 10
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
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
            name: "media"
            sourceComponent: Media {
                popouts: root.popouts
            }
        }

        Popout {
            name: "notes"
            sourceComponent: Notes {
                popouts: root.popouts
            }
        }

        Popout {
            name: "weather"
            sourceComponent: Weather {
                popouts: root.popouts
            }
        }

        Popout {
            name: "performance"
            sourceComponent: Performance {
                popouts: root.popouts
            }
        }

        Popout {
            name: "shortcuts"
            sourceComponent: Shortcuts {
                popouts: root.popouts
                visibilities: root.visibilities
            }
        }

        Popout {
            name: "screencapture"
            sourceComponent: ScreenCapture {
                popouts: root.popouts
                visibilities: root.visibilities
            }
        }

        Popout {
            name: "keepawake"
            sourceComponent: KeepAwake {
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
            minScale: 0.9
            sourceComponent: Audio {
                popouts: root.popouts
            }
        }

        Popout {
            name: "privacy"
            sourceComponent: Privacy {
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
            isContext: true
            previewKey: "dock"
            sourceComponent: DockContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "workspacescontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Workspaces settings")
                subPageIdx: 7
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "traycontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Tray settings")
                subPageIdx: 9
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "githubcontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("GitHub settings")
                subPageIdx: 13
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "mediacontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Media settings")
                subPageIdx: 19
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "performancecontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Performance settings")
                subPageIdx: 21
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }
        Popout {
            name: "weathercontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Weather settings")
                subPageIdx: 20
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }
        Popout {
            name: "screencapturecontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Screen Capture settings")
                subPageIdx: 22
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }
        Popout {
            name: "keepawakecontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Keep Awake settings")
                subPageIdx: 23
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "dockbgcontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Dock settings")
                subPageIdx: 12
                secondLabel: qsTr("Elements & Modules")
                secondSubPageIdx: 15
            }
        }

        Popout {
            name: "elementscontext"
            isContext: true
            sourceComponent: BarComponentContext {
                popouts: root.popouts
                label: qsTr("Elements & Modules")
                subPageIdx: 15
            }
        }

        // Plugin widgets that declare a popout get one here, so they slide in
        // through the same container the built-in popouts use instead of
        // opening a window of their own.
        Repeater {
            model: ScriptModel {
                values: QsServices.BarWidgetRegistry.widgets.filter(widget => widget.popoutUrl)
            }

            Popout {
                required property var modelData

                name: modelData.id
                previewKey: modelData.id
                source: modelData.popoutUrl

                onItemChanged: root.applyPopoutContext(item)
            }
        }

        Repeater {
            model: ScriptModel {
                values: QsServices.TrayRegistry.trayItems.filter(item => item.hasMenu)
            }

            Popout {
                id: trayMenu

                required property SystemTrayItem modelData

                name: QsServices.TrayRegistry.popoutNameOf(modelData)
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
        property bool isContext: false
        property string previewKey: name
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
