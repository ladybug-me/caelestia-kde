pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Add to startup")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Repeater {
            model: Apps.alphaApps

            delegate: ConnectedRect {
                id: appRow

                required property DesktopEntry modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === Apps.alphaApps.length - 1
                implicitHeight: appLayout.implicitHeight + appLayout.anchors.margins * 2

                StateLayer {
                    onClicked: {
                        Autostart.add(appRow.modelData.id);
                        root.nState.closeSubPage();
                    }
                }

                RowLayout {
                    id: appLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    IconImage {
                        asynchronous: true
                        implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                        source: WinIcons.sourceFor(appRow.modelData, "", appRow.modelData?.id ?? "", 0)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: (appRow.modelData.comment || appRow.modelData.genericName) ?? ""
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
