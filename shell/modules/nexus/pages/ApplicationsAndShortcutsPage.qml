pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Applications & Shortcuts")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        NavRow {
            first: true
            icon: "apps"
            label: qsTr("Apps")
            status: qsTr("Default openers, installed apps, and search")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            icon: "list_alt"
            label: qsTr("All Apps")
            status: qsTr("Browse and manage desktop apps")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            last: true
            icon: "keyboard"
            label: qsTr("Keyboard Shortcuts")
            status: qsTr("View and configure shell keybindings")
            onClicked: root.nState.openSubPage(3)
        }
    }
}
