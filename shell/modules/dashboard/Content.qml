pragma ComponentBehavior: Bound

import "../../services"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.filedialog

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property ScreenState screenState
    required property FileDialog facePicker

    readonly property var dashboardTabs: {
        const allTabs = [
            {
                component: dashComponent,
                keepAlive: true,
                iconName: "dashboard",
                text: qsTr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                component: mediaComponent,
                keepAlive: true,
                iconName: "queue_music",
                text: qsTr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                component: performanceComponent,
                iconName: "speed",
                text: qsTr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                component: weatherComponent,
                keepAlive: true,
                iconName: "cloud",
                text: qsTr("Weather"),
                enabled: Config.dashboard.showWeather
            },
            {
                component: notesComponent,
                iconName: "sticky_note_2",
                text: qsTr("Notes"),
                enabled: Config.dashboard.showNotes
            },
            {
                component: terminalComponent,
                iconName: "terminal",
                text: qsTr("Terminal"),
                enabled: Config.dashboard.showTerminal
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2

    onDashboardTabsChanged: {
        if (dashboardTabs.length > 0 && screenState.dashboardTab >= dashboardTabs.length) {
            screenState.dashboardTab = dashboardTabs.length - 1;
        }
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    // Builds the keepAlive tabs one at a time shortly after start, so the first open is as
    // cheap as the next ones.
    Timer {
        interval: 1500
        repeat: true
        running: true

        onTriggered: {
            for (let i = 0; i < repeater.count; i++) {
                const loader = repeater.itemAt(i);
                if (loader && loader.modelData.keepAlive && !loader.keepLoaded) {
                    loader.keepLoaded = true;
                    return;
                }
            }
            stop();
        }
    }

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        nonAnimWidth: root.nonAnimWidth - anchors.margins * 2
        screenState: root.screenState
        tabs: root.dashboardTabs
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.screenState.dashboardTab
            readonly property Item currentItem: {
                repeater.count;
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick

            implicitWidth: currentItem?.implicitWidth ?? 0
            implicitHeight: currentItem?.implicitHeight ?? 0

            contentX: currentItem?.x ?? 0
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            onContentXChanged: {
                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            RowLayout {
                id: row

                Repeater {
                    id: repeater

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        Layout.alignment: Qt.AlignTop

                        sourceComponent: modelData.component

                        // Stays loaded once shown, so switching tabs does not rebuild it.
                        property bool keepLoaded: false

                        // Neighbours are loaded while dragging. Index based on purpose: reading x or
                        // implicitWidth here depends on this Loader's own content (binding loop).
                        readonly property bool preloadNeighbour: view.moving && Math.abs(index - view.currentIndex) === 1

                        // Light tabs (keepAlive) stay loaded while the dashboard is closed, so reopening it
                        // does not rebuild them. The dashboard is hidden then, and their services follow `visible`.
                        active: (modelData.keepAlive && keepLoaded) || (root.visibilities.dashboard && (keepLoaded || index === view.currentIndex || preloadNeighbour))

                        onActiveChanged: {
                            if (active)
                                keepLoaded = true;
                        }
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    visibilities: root.visibilities
                    screenState: root.screenState
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {
                    visibilities: root.visibilities
                }
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Component {
                id: notesComponent

                NotesTab {
                    dashboardOpen: root.visibilities.dashboard
                }
            }

            Component {
                id: terminalComponent

                TerminalTab {}
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
