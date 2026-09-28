pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.nexus

Item {
    id: root

    property int initialPageIdx: 0
    property int initialSubPageIdx: -1

    readonly property NexusState nState: NexusState {
        id: nState

        currentPageIdx: root.initialPageIdx
        Component.onCompleted: {
            if (root.initialSubPageIdx !== -1)
                openSubPage(root.initialSubPageIdx);
        }

        onClose: root.requestClose()
    }
    property color blobColour: Colours.tPalette.m3surfaceContainerLow

    signal close

    // Entry point for anything that wants to close Nexus (in-app close
    // button, native window close, etc). Intercepts the close when an
    // update is running so the user can decide whether to cancel it first.
    function requestClose(): void {
        if (UpdateChecker.updateRunning)
            closeConfirmDialog.visible = true;
        else
            root.close();
    }

    implicitWidth: implicitHeight * Tokens.sizes.nexus.ratio
    implicitHeight: nState.screen.height * Tokens.sizes.nexus.heightMult

    Behavior on blobColour {
        CAnim {}
    }

    BlobGroup {
        id: blobGroup

        smoothing: root.Tokens.rounding.medium
        color: root.blobColour
    }

    BlobInvertedRect {
        anchors.fill: parent
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.large

        borderLeft: navPane.width + navPane.anchors.margins * 2
        borderRight: Tokens.padding.medium
        borderTop: Tokens.padding.medium
        borderBottom: Tokens.padding.medium
    }

    NavPane {
        id: navPane

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large

        nState: nState
        width: Math.min(Tokens.sizes.nexus.maxNavWidth, Math.round(root.width / 3))
    }

    Pages {
        anchors.left: navPane.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: navPane.anchors.margins + anchors.margins
        anchors.margins: Tokens.padding.extraLarge

        nState: nState
    }

    Item {
        id: closeConfirmDialog

        anchors.fill: parent
        visible: false
        z: 1000

        Connections {
            target: UpdateChecker

            function onUpdateRunningChanged(): void {
                if (!UpdateChecker.updateRunning)
                    closeConfirmDialog.visible = false;
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: closeConfirmDialog.visible = false
        }

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3shadow, 0.55)
        }

        Elevation {
            level: 3
            radius: dialogBg.radius
            anchors.fill: dialogBg
        }

        StyledRect {
            id: dialogBg

            anchors.centerIn: parent
            implicitWidth: Math.min(340, root.width - Tokens.padding.large * 4)
            implicitHeight: dialogCol.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: dialogCol

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.large
                }
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "sync"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Update in progress")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Closing now will let the update keep running in the background, or you can cancel it first.")
                    wrapMode: Text.Wrap
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    spacing: Tokens.spacing.small

                    Item { Layout.fillWidth: true }

                    IconTextButton {
                        text: qsTr("Cancel Update")
                        icon: "stop"
                        type: TextButton.Tonal
                        onClicked: {
                            UpdateChecker.stopUpdate();
                            closeConfirmDialog.visible = false;
                            root.close();
                        }
                    }

                    IconTextButton {
                        text: qsTr("Keep Running")
                        icon: "close"
                        type: TextButton.Filled
                        onClicked: {
                            closeConfirmDialog.visible = false;
                            root.close();
                        }
                    }
                }
            }
        }
    }
}