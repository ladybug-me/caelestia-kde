pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Sidebar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            checked: Config.sidebar.enabled
            onToggled: GlobalConfig.sidebar.enabled = checked
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the sidebar opens")
            value: Config.sidebar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.sidebar.dragThreshold = v
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            last: true
            label: qsTr("Grab width")
            subtext: qsTr("Pixels of screen edge reserved for grabbing the sidebar")
            value: Config.sidebar.grabWidth
            from: 1
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.sidebar.grabWidth = v
        }

        SectionHeader {
            text: qsTr("Sidebar Tabs")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Show News tab")
            subtext: qsTr("Show the News tab in the sidebar")
            checked: GlobalConfig.ai.showNews
            onToggled: GlobalConfig.ai.showNews = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            last: true
            text: qsTr("Show Caelestia Mode")
            subtext: qsTr("Show the Caelestia Mode toggle at the bottom of notifications")
            checked: GlobalConfig.ai.showCaelestiaMode
            onToggled: GlobalConfig.ai.showCaelestiaMode = checked
        }
    }
}
