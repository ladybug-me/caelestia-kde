pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    title: root.nState ? PageCompRegistry.categories[root.nState.currentPageIdx].label : ""
    isSubPage: false

    ColumnLayout {
        readonly property var cat: PageCompRegistry.categories[root.nState ? root.nState.currentPageIdx : 0]
        readonly property var pagesList: cat ? cat.pages : []

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Repeater {
            model: parent.pagesList

            ColumnLayout {
                id: rowCol

                required property var modelData
                required property int index

                readonly property var list: parent.parent.pagesList
                readonly property bool hasSection: modelData.section && modelData.section.length > 0
                readonly property bool isSectionStart: hasSection && (index === 0 || list[index - 1].section !== modelData.section)
                readonly property bool isSectionEnd: index === list.length - 1 || (index < list.length - 1 && list[index + 1].section !== modelData.section)

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    visible: rowCol.isSectionStart
                    first: rowCol.index === 0
                    text: rowCol.modelData.section
                }

                NavRow {
                    first: !rowCol.hasSection ? rowCol.index === 0 : rowCol.isSectionStart
                    last: !rowCol.hasSection ? rowCol.index === rowCol.list.length - 1 : rowCol.isSectionEnd
                    icon: rowCol.modelData.icon
                    label: rowCol.modelData.label
                    status: rowCol.modelData.description !== "" ? rowCol.modelData.description : rowCol.modelData.status
                    enabled: rowCol.modelData.enabled
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: root.nState.openSubPage(rowCol.modelData.slot)
                }
            }
        }
    }
}
