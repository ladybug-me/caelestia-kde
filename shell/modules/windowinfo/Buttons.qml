pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var client

    signal closeRequested()

    spacing: Tokens.spacing.small

    RowLayout {
        spacing: Tokens.spacing.medium

        StyledText {
            text: qsTr("Move to workspace")
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Layout.topMargin: Tokens.padding.large
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
    }
    Flow {
        id: wsGrid

        clip: true
        spacing: Tokens.spacing.small

        Repeater {
            model: Kwin.workspaces.length

            Button {
                required property int index
                readonly property int wsId: Kwin.workspaces[index].index
                readonly property string wsName: wsId.toString()
                readonly property bool isCurrent: root.client?.workspace?.id === wsId

                onClicked: {
Kwin.setWindowDesktop(root.client?.address, wsId);
Kwin.switchToWorkspace(wsId);
                
                    Visibilities.setOverview(false);
                }
                color: isCurrent ? Colours.tPalette.m3surfaceContainerHighest : Colours.palette.m3tertiaryContainer
                onColor: isCurrent ? Colours.palette.m3onSurface : Colours.palette.m3onTertiaryContainer
                text: wsName
                disabled: isCurrent
            }
        }
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.bottomMargin: Tokens.spacing.medium
    }
    RowLayout {
        spacing: Tokens.spacing.small

        Button {
            color: Colours.palette.m3secondaryContainer
            onColor: Colours.palette.m3onSecondaryContainer
            text: root.client?.maximized ? qsTr("Restore") : qsTr("Maximize")
            onClicked: {
                console.log("Maximize clicked. Address:", root.client?.address, "Maximized:", root.client?.maximized);
console.log("Calling Kwin.maximizeWindow");
Kwin.maximizeWindow(root.client?.address, !root.client?.maximized, !root.client?.maximized);
            
                Visibilities.setOverview(false);
            }
        }
        Loader {
            asynchronous: true
            active: true
            sourceComponent: Button {
                color: Colours.palette.m3secondaryContainer
                onColor: Colours.palette.m3onSecondaryContainer
                text: root.client?.minimized ? qsTr("Unminimize") : qsTr("Minimize")
                onClicked: {
if (root.client?.minimized) {
    Kwin.focusWindow(root.client?.address);
} else {
    Kwin.minimizeWindow(root.client?.address);
}
                
                    Visibilities.setOverview(false);
                }
            }
            Layout.fillWidth: active
            Layout.leftMargin: active ? 0 : -parent.spacing
            Layout.rightMargin: active ? 0 : -parent.spacing
        }
        Button {
            color: Colours.palette.m3errorContainer
            onColor: Colours.palette.m3onErrorContainer
            text: qsTr("Kill")
            onClicked: {
                console.log("Kill clicked. Address:", root.client?.address);
console.log("Calling Kwin.closeWindow");
Kwin.closeWindow(root.client?.address);
            
                Visibilities.setOverview(false);
            }
        }
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.bottomMargin: Tokens.padding.large
    }

    component Button: StyledRect {
        property color onColor: Colours.palette.m3onSurface
        property alias disabled: stateLayer.disabled
        property alias text: label.text

        signal clicked

        radius: stateLayer.pressed ? Tokens.rounding.small : Tokens.rounding.medium
        implicitWidth: label.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: label.implicitHeight + Tokens.padding.small
        Layout.fillWidth: true

        Behavior on radius {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StateLayer {
            id: stateLayer

            color: parent.onColor
            onClicked: {
                parent.clicked()
                root.closeRequested()
                if (typeof Visibilities !== "undefined")
                    Visibilities.setOverview(false);
            }
        }

        StyledText {
            id: label

            anchors.centerIn: parent
            animate: true
            color: parent.onColor
            font: Tokens.font.body.medium
        }
    }
}
