import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Clipboard")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("History")
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Maximum entries")
            subtext: qsTr("Number of entries available in the launcher")
            value: GlobalConfig.launcher.clipboardMaxEntries
            from: 1
            to: 2048
            stepSize: 1
            onMoved: value => GlobalConfig.launcher.clipboardMaxEntries = value
        }
    }
}