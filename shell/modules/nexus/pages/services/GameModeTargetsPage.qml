pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root
    
    title: qsTr("Target windows")
    isSubPage: true
    scrollable: false

    ColumnLayout {
        id: mainLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Add target window")
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: contentRow.implicitHeight + Tokens.padding.medium * 2
            z: 1

            ConnectedRect {
                anchors.fill: parent
                first: true
            }

            RowLayout {
                id: contentRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                Column {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: qsTr("Custom regex")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: qsTr("Add a custom class or regex pattern")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                StyledRect {
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 32
                    radius: Tokens.rounding.small
                    color: Colours.layer(Colours.palette.m3surfaceVariant, 2)
                    
                    StyledTextField {
                        id: customInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "^steam_app_.*$"
                        onAccepted: {
                            if (text) {
                                let list = Array.from(GlobalConfig.utilities.gameMode.autoEnableRegexes);
                                if (!list.includes(text)) {
                                    list.push(text);
                                    GlobalConfig.utilities.gameMode.autoEnableRegexes = list;
                                    GlobalConfig.save();
                                }
                                text = "";
                            }
                        }
                    }
                }

                IconButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    icon: "add"
                    onClicked: {
                        if (customInput.text) {
                            let list = Array.from(GlobalConfig.utilities.gameMode.autoEnableRegexes);
                            if (!list.includes(customInput.text)) {
                                list.push(customInput.text);
                                GlobalConfig.utilities.gameMode.autoEnableRegexes = list;
                                GlobalConfig.save();
                            }
                            customInput.text = "";
                        }
                    }
                }
            }
        }

        WindowPickerRow {
            Layout.fillWidth: true
            last: true
            icon: "touch_app"
            label: qsTr("Pick from running windows")
            status: qsTr("Select an open window to add it automatically")
            onSelected: windowClass => {
                let list = Array.from(GlobalConfig.utilities.gameMode.autoEnableRegexes);
                if (!list.includes(windowClass)) {
                    list.push(windowClass);
                    GlobalConfig.utilities.gameMode.autoEnableRegexes = list;
                    GlobalConfig.save();
                }
            }
        }

        SectionHeader {
            text: qsTr("Target window list")
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
            radius: Tokens.rounding.large

            ListView {
                id: targetList

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                orientation: ListView.Vertical
                spacing: Tokens.spacing.small
                model: GlobalConfig.utilities.gameMode.autoEnableRegexes
                clip: true

                move: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }
                moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }

                delegate: StyledRect {
                    id: delegateRect

                    required property string modelData
                    required property int index

                    width: ListView.view.width
                    height: 40
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    radius: Tokens.rounding.medium

                    RowLayout {
                        id: itemLayout

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        property bool isRegex: delegateRect.modelData.startsWith("^") && delegateRect.modelData.endsWith("$")

                        IconImage {
                            visible: !itemLayout.isRegex
                            Layout.alignment: Qt.AlignVCenter
                            implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.5)
                            source: itemLayout.isRegex ? "" : Quickshell.iconPath(delegateRect.modelData, "image-missing")
                        }

                        MaterialIcon {
                            visible: itemLayout.isRegex
                            Layout.alignment: Qt.AlignVCenter
                            text: "code"
                            font: Tokens.font.icon.large
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: delegateRect.modelData
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28

                            StateLayer {
                                anchors.fill: parent
                                radius: 14
                                onClicked: {
                                    let list = Array.from(GlobalConfig.utilities.gameMode.autoEnableRegexes);
                                    list.splice(delegateRect.index, 1);
                                    GlobalConfig.utilities.gameMode.autoEnableRegexes = list;
                                    GlobalConfig.save();
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                font: Tokens.font.icon.small
                            }
                        }
                    }
                }
            }
        }
    }
}
