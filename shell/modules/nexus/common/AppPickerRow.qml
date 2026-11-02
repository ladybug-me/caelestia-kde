pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.nexus.common

/// Picks the name a notification carries out of the installed applications, since that
/// name is not something anyone should have to remember.
PopupRow {
    id: root

    /// The popup opens upwards, so it may only be as tall as the space the row leaves above itself.
    readonly property int bodyHeight: Math.min(Tokens.sizes.nexus.maxPopupHeight, Math.max(Math.round(y) - Tokens.padding.large, Tokens.sizes.nexus.minPopupHeight))
    readonly property string typed: root.filter.trim()
    readonly property var matches: {
        const needle = root.typed.toLowerCase();
        return Apps.alphaApps.filter(entry => entry && !root.exclude.includes(entry.name) && (needle === "" || entry.name.toLowerCase().includes(needle)));
    }

    property list<string> exclude: []
    property string filter

    signal selected(name: string)

    keepPopupAsChild: {
        let p = root.parent;
        while (p && p.objectName !== "PageContainer")
            p = p.parent;
        return p?.opacity < 1;
    }
    popup.topMovement: root.bodyHeight

    Loader {
        anchors.centerIn: parent
        active: root.popup.animDriver > 0

        sourceComponent: Item {
            implicitWidth: Tokens.sizes.nexus.popupWidth
            implicitHeight: root.bodyHeight

            ColumnLayout {
                anchors.fill: parent
                spacing: Tokens.spacing.extraSmall

                StyledTextField {
                    id: query

                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    horizontalAlignment: TextInput.AlignLeft
                    placeholderText: qsTr("Search applications")
                    onTextEdited: root.filter = query.text
                }

                VerticalFadeListView {
                    id: list

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.matches

                    delegate: StateLayer {
                        id: appRow

                        required property DesktopEntry modelData
                        required property int index

                        anchors.fill: undefined
                        anchors.left: list.contentItem.left
                        anchors.right: list.contentItem.right
                        implicitHeight: itemLayout.implicitHeight + itemLayout.anchors.margins * 2
                        radius: Tokens.rounding.small

                        onClicked: {
                            root.popup.open = false;
                            root.selected(appRow.modelData.name);
                        }

                        RowLayout {
                            id: itemLayout

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
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

                TextButton {
                    Layout.fillWidth: true
                    visible: root.typed !== "" && root.matches.length === 0
                    text: qsTr("Allow \"%1\"").arg(root.typed)
                    type: TextButton.Tonal
                    onClicked: {
                        root.popup.open = false;
                        root.selected(root.typed);
                    }
                }
            }
        }
    }
}
