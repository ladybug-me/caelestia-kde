pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property Props props
    required property DrawerVisibilities visibilities
    readonly property int notifCount: Notifs.openCount

    /// What the list is being narrowed to, empty when nothing is.
    property string query: ""

    /// Searching only makes sense once there is something to search through, and keeps
    /// making sense while a query is narrowing what is left.
    readonly property bool canSearch: root.notifCount > 0 || root.query !== ""

    anchors.fill: parent
    anchors.margins: Tokens.padding.medium

    Component.onCompleted: Notifs.list.forEach(n => n.popup = false)

    Item {
        id: title

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.extraSmall

        implicitHeight: Math.max(count.implicitHeight, titleText.implicitHeight, searchButton.implicitHeight)

        StyledText {
            id: count

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.notifCount > 0 ? 0 : -width - titleText.anchors.leftMargin
            opacity: root.notifCount > 0 ? 1 : 0

            text: root.notifCount
            color: Colours.palette.m3outline
            font: Tokens.font.label.large

            Behavior on anchors.leftMargin {
                Anim {}
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        StyledText {
            id: titleText

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: count.right
            anchors.right: searchButton.left
            anchors.leftMargin: Tokens.spacing.extraSmall
            anchors.rightMargin: Tokens.spacing.small

            text: root.notifCount > 0 ? qsTr("notification%1").arg(root.notifCount === 1 ? "" : "s") : qsTr("Notifications")
            color: Colours.palette.m3outline
            font: Tokens.font.label.large
            elide: Text.ElideRight
        }

        // Only worth offering once there is something to search through.
        IconButton {
            id: searchButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.canSearch ? 1 : 0
            enabled: root.canSearch

            icon: searchField.visible ? "search_off" : "search"
            onClicked: {
                searchField.visible = !searchField.visible;
                if (searchField.visible)
                    searchField.forceActiveFocus();
                else {
                    searchField.text = "";
                    root.query = "";
                }
            }
            Accessible.name: qsTr("Search notifications")

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    StyledTextField {
        id: searchField

        anchors.top: title.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.medium
        visible: false
        placeholderText: qsTr("Search notifications")
        horizontalAlignment: TextInput.AlignLeft
        onTextEdited: root.query = searchField.text
    }

    ClippingRectangle {
        id: clipRect

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchField.visible ? searchField.bottom : title.bottom
        anchors.bottom: clearLoader.opacity > 0 ? clearLoader.top : toggleRect.top
        anchors.bottomMargin: Tokens.padding.medium
        anchors.topMargin: Tokens.spacing.medium

        radius: Tokens.rounding.medium
        color: "transparent"

        Loader {
            id: loader

            property bool gameIsActive: item && item.hasOwnProperty("isPlaying") && item.isPlaying

            asynchronous: true
            anchors.centerIn: parent
            active: opacity > 0
            opacity: (root.notifCount > 0 && !gameIsActive) ? 0 : 1
            z: (root.notifCount > 0 && !gameIsActive) ? -1 : 1
            width: clipRect.width
            height: 250

            sourceComponent: DinoGame {
                width: clipRect.width
                height: 250
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardExtraLarge
                }
            }
        }

        StyledFlickable {
            id: view

            anchors.fill: parent

            flickableDirection: Flickable.VerticalFlick
            contentWidth: width
            contentHeight: notifList.implicitHeight
            opacity: loader.opacity === 1 ? 0 : 1

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: view
            }

            NotifDockList {
                id: notifList

                props: root.props
                visibilities: root.visibilities
                container: view
                filter: root.query
            }
        }
    }


    StyledRect {
        id: toggleRect

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: clearLoader.opacity > 0 ? clearLoader.width + Tokens.padding.medium * 2 : 0

        height: toggleLayout.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            id: toggleLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Tokens.padding.large
                radius: Tokens.rounding.full
                color: GlobalConfig.general.caelestiaMode ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "auto_awesome"
                    color: GlobalConfig.general.caelestiaMode ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Caelestia Mode")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: GlobalConfig.general.caelestiaMode ? qsTr("Spinning kurukuru activated") : qsTr("Classic dinosaur character")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                checked: GlobalConfig.general.caelestiaMode
                onToggled: {
                    GlobalConfig.general.caelestiaMode = checked;
                }
            }
        }
    }

    Loader {
        id: clearLoader

        asynchronous: true
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.medium

        scale: root.notifCount > 0 ? 1 : 0.5
        opacity: root.notifCount > 0 ? 1 : 0
        active: opacity > 0

        sourceComponent: IconButton {
            id: clearBtn

            icon: "clear_all"
            font: Tokens.font.icon.large
            onClicked: Notifs.clear()

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                z: -1
                level: clearBtn.stateLayer.containsMouse ? 4 : 3
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
