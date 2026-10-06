pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    // See ContentWindow.qml note: loosely typed because the KDE fallback
    // bridge's monitorFor() returns a mock QtObject, not a real HyprlandMonitor.
    // Kwin.qml feeds the mocks' specialWorkspace from the real per-output
    // tracker state, so this reads actual state.
    readonly property var monitor: Kwin.monitorFor(screen)
    readonly property string activeSpecial: (Config.bar.workspaces.perMonitor ? root.monitor : Kwin.focusedMonitor)?.specialWorkspace?.name ?? ""

    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"


    layer.enabled: true
    layer.effect: Mask {
        maskSource: mask
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: Tokens.rounding.full

            gradient: Gradient {
                orientation: isHorizontal ? Gradient.Horizontal : Gradient.Vertical

                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0)
                }
                GradientStop {
                    position: 0.3
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 0.7
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0)
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: isHorizontal ? parent.bottom : undefined
            anchors.left: parent.left
            anchors.right: isHorizontal ? undefined : parent.right

            radius: Tokens.rounding.full
            implicitWidth: isHorizontal ? parent.width / 2 : 0
            implicitHeight: isHorizontal ? 0 : parent.height / 2
            opacity: isHorizontal ? (view.contentX > 0 ? 0 : 1) : (view.contentY > 0 ? 0 : 1)

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.top: isHorizontal ? parent.top : undefined
            anchors.right: parent.right
            anchors.left: isHorizontal ? undefined : parent.left

            radius: Tokens.rounding.full
            implicitWidth: isHorizontal ? parent.width / 2 : 0
            implicitHeight: isHorizontal ? 0 : parent.height / 2
            opacity: isHorizontal ? (view.contentX < view.contentWidth - parent.width + Tokens.padding.extraSmall ? 0 : 1) : (view.contentY < view.contentHeight - parent.height + Tokens.padding.extraSmall ? 0 : 1)

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    ListView {
        id: view

        anchors.fill: parent
        spacing: Tokens.spacing.medium
        interactive: false

        orientation: isHorizontal ? ListView.Horizontal : ListView.Vertical

        currentIndex: model.values.findIndex(w => w.name === root.activeSpecial)
        onCurrentIndexChanged: currentIndex = Qt.binding(() => model.values.findIndex(w => w.name === root.activeSpecial))

        model: ScriptModel {
            // Kwin.workspaces is a plain array (KWinWorkspaceState.workspaces): `.values` is
            // Array.prototype.values, so the filter threw and the strip never rendered.
            // Workspace maps carry no monitor key, so the strip lists every special:
            // desktop.
            values: Kwin.workspaces.filter(w => String(w.name ?? "").startsWith("special:"))
        }

        preferredHighlightBegin: 0
        preferredHighlightEnd: isHorizontal ? width : height
        highlightRangeMode: ListView.StrictlyEnforceRange

        highlightFollowsCurrentItem: false

        highlight: Item {
            x: isHorizontal ? (view.currentItem?.x ?? 0) : 0
            y: isHorizontal ? 0 : (view.currentItem?.y ?? 0)
            implicitWidth: isHorizontal ? ((view.currentItem as SpecialWsDelegate)?.size ?? 0) : 0
            implicitHeight: isHorizontal ? 0 : ((view.currentItem as SpecialWsDelegate)?.size ?? 0)

            Behavior on x {
                enabled: isHorizontal

                Anim {}
            }

            Behavior on y {
                enabled: !isHorizontal

                Anim {}
            }
        }

        delegate: SpecialWsDelegate {}

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        remove: Transition {
            Anim {
                property: "scale"
                to: 0.5
                type: Anim.StandardSmall
            }
            Anim {
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        displaced: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }
    }

    Loader {
        asynchronous: true
        active: Config.bar.workspaces.activeIndicator
        anchors.fill: parent

        sourceComponent: Item {
            StyledClippingRect {
                id: indicator

                anchors.left: isHorizontal ? undefined : parent.left
                anchors.right: isHorizontal ? undefined : parent.right
                anchors.top: isHorizontal ? parent.top : undefined
                anchors.bottom: isHorizontal ? parent.bottom : undefined

                x: isHorizontal ? ((view.currentItem?.x ?? 0) - view.contentX) : 0
                y: isHorizontal ? 0 : ((view.currentItem?.y ?? 0) - view.contentY)
                implicitWidth: isHorizontal ? ((view.currentItem as SpecialWsDelegate)?.size ?? 0) : view.width
                implicitHeight: isHorizontal ? view.height : ((view.currentItem as SpecialWsDelegate)?.size ?? 0)

                color: Colours.palette.m3tertiary
                radius: Tokens.rounding.full

                Colouriser {
                    source: view
                    sourceColor: Colours.palette.m3onSurface
                    colorizationColor: Colours.palette.m3onTertiary

                    anchors.horizontalCenter: isHorizontal ? undefined : parent.horizontalCenter
                    anchors.verticalCenter: isHorizontal ? parent.verticalCenter : undefined

                    x: isHorizontal ? -indicator.x : 0
                    y: isHorizontal ? 0 : -indicator.y
                    implicitWidth: view.width
                    implicitHeight: view.height
                }

                Behavior on x {
                    enabled: isHorizontal

                    Anim {
                        type: Anim.Emphasized
                    }
                }

                Behavior on y {
                    enabled: !isHorizontal

                    Anim {
                        type: Anim.Emphasized
                    }
                }

                Behavior on implicitWidth {
                    enabled: isHorizontal

                    Anim {
                        type: Anim.Emphasized
                    }
                }

                Behavior on implicitHeight {
                    enabled: !isHorizontal

                    Anim {
                        type: Anim.Emphasized
                    }
                }
            }
        }
    }

    MouseArea {
        property real startPos

        anchors.fill: view

        drag.target: view.contentItem

        drag.axis: isHorizontal ? Drag.XAxis : Drag.YAxis
        drag.maximumX: 0
        drag.minimumX: isHorizontal ? Math.min(0, view.width - view.contentWidth - Tokens.padding.small) : 0
        drag.maximumY: 0
        drag.minimumY: isHorizontal ? 0 : Math.min(0, view.height - view.contentHeight - Tokens.padding.extraSmall)

        onPressed: event => startPos = isHorizontal ? event.x : event.y

        onClicked: event => {
            const currentPos = isHorizontal ? event.x : event.y;
            if (Math.abs(currentPos - startPos) > drag.threshold)
                return;

            const ws = view.itemAt(event.x, event.y) as SpecialWsDelegate;
            // Plain workspace maps, not HyprlandWorkspace objects: pass the pill's
            // full special: name (or "" for the default one) straight to the bridge.
            Kwin.toggleSpecialWorkspace(String(ws?.modelData?.name ?? ""), root.screen.name);
        }
    }

    component SpecialWsDelegate: GridLayout {
        id: ws

        // Plain workspace map ({ id: uuid, name, index, active }), not a
        // HyprlandWorkspace: this port has no lastIpcObject to reach through.
        required property var modelData
        readonly property string wsName: String(ws.modelData?.name ?? "")
        readonly property string wsUuid: String(ws.modelData?.id ?? "")
        readonly property int wsIndex: Number(ws.modelData?.index ?? 0)
        // Counts bind through Kwin.windowList so they follow open/close events.
        readonly property int windowCount: wsUuid ? Kwin.filterWindows(Kwin.windowList, wsUuid, "", true).length : 0
        readonly property bool hasWindows: root.Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.windowCount > 0
        readonly property int size: isHorizontal ? (label.Layout.preferredWidth + (hasWindows ? windows.implicitWidth + Tokens.padding.extraSmall : 0)) : (label.Layout.preferredHeight + (hasWindows ? windows.implicitHeight + Tokens.padding.extraSmall : 0))
        readonly property string icon: Icons.getSpecialWsIcon(ws.wsName)

        columns: isHorizontal ? -1 : 1
        rows: isHorizontal ? 1 : -1
        flow: isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom

        anchors.left: isHorizontal ? undefined : view.contentItem.left
        anchors.right: isHorizontal ? undefined : view.contentItem.right
        anchors.top: isHorizontal ? view.contentItem.top : undefined
        anchors.bottom: isHorizontal ? view.contentItem.bottom : undefined

        columnSpacing: 0
        rowSpacing: 0

        Loader {
            id: label

            asynchronous: true

            Layout.alignment: isHorizontal ? (Qt.AlignVCenter | Qt.AlignLeft) : (Qt.AlignHCenter | Qt.AlignTop)
            Layout.preferredWidth: isHorizontal ? Math.round(Tokens.sizes.bar.innerWidth * Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0)) : -1
            Layout.preferredHeight: isHorizontal ? -1 : Math.round(Tokens.sizes.bar.innerWidth * Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0))

            sourceComponent: ws.icon.length === 1 ? letterComp : iconComp

            Component {
                id: iconComp

                MaterialIcon {
                    anchors.fill: parent
                    fill: 1
                    text: ws.icon
                    verticalAlignment: Qt.AlignVCenter
                    horizontalAlignment: Qt.AlignHCenter
                }
            }

            Component {
                id: letterComp

                StyledText {
                    anchors.fill: parent
                    text: ws.icon
                    verticalAlignment: Qt.AlignVCenter
                    horizontalAlignment: Qt.AlignHCenter
                }
            }
        }

        Loader {
            id: windows

            asynchronous: true

            Layout.alignment: isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            Layout.fillWidth: isHorizontal && enabled
            Layout.fillHeight: !isHorizontal && enabled

            visible: active
            active: ws.hasWindows

            sourceComponent: isHorizontal ? rowComponent : columnComponent

            Behavior on Layout.preferredHeight {
                enabled: !isHorizontal

                Anim {}
            }
        }

        // MOVED COMPONENTS INSIDE DELEGATE: This fixes the "ws is not defined" error
        Component {
            id: columnComponent

            Column {
                spacing: 0

                add: Transition {
                    Anim {
                        properties: "scale"
                        from: 0
                        to: 1
                        easing: Tokens.anim.standardDecel
                    }
                }

                move: Transition {
                    Anim {
                        properties: "scale"
                        to: 1
                        easing: Tokens.anim.standardDecel
                    }
                    Anim {
                        properties: "x,y"
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: {
                            const wins = Kwin.windowList.filter(c => c.workspace?.uuid === ws.wsUuid || (c.workspace?.id === ws.wsIndex && ws.wsIndex > 0));
                            const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                            return maxIcons > 0 ? wins.slice(0, maxIcons) : wins;
                        }
                    }

                    MaterialIcon {
                        required property var modelData

                        grade: 0
                        text: Icons.getAppCategoryIcon(modelData.class, "terminal")
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        Component {
            id: rowComponent

            Row {
                spacing: 0
                add: Transition {
                    Anim {
                        properties: "scale"
                        from: 0
                        to: 1
                        easing: Tokens.anim.standardDecel
                    }
                }
                move: Transition {
                    Anim {
                        properties: "scale"
                        to: 1
                        easing: Tokens.anim.standardDecel
                    }
                    Anim {
                        properties: "x,y"
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: {
                            const wins = Kwin.windowList.filter(c => c.workspace?.uuid === ws.wsUuid || (c.workspace?.id === ws.wsIndex && ws.wsIndex > 0));
                            const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                            return maxIcons > 0 ? wins.slice(0, maxIcons) : wins;
                        }
                    }

                    MaterialIcon {
                        required property var modelData

                        grade: 0
                        text: Icons.getAppCategoryIcon(modelData.class, "terminal")
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
