pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Nexus settings")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        SectionHeader {
            text: qsTr("Layout")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                reset: ({ node: GlobalConfig.nexus, setting: "sidePane" })
                first: true
                last: true
                Layout.fillWidth: true
                text: qsTr("Subcategory side pane")
                subtext: qsTr("List a section's subcategories in their own pane. Turned off, they line up inside the section")
                checked: GlobalConfig.nexus.sidePane
                onToggled: GlobalConfig.nexus.sidePane = checked
            }
        }
    }
}
