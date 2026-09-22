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
import qs.services
import qs.utils
import qs.modules.nexus.common

PopupRow {
    id: root

    readonly property int popupHeight: (parent?.height ?? 300) - y - Tokens.padding.large - Tokens.padding.extraExtraLarge

    signal selected(windowClass: string)

    keepPopupAsChild: {
        let p = root.parent;
        while (p && p.objectName !== "PageContainer")
            p = p.parent;
        return p?.opacity < 1;
    }
    popup.topMovement: Math.max(Tokens.sizes.nexus.minPopupHeight - popupHeight, Tokens.padding.large)

    Loader {
        anchors.centerIn: parent
        active: root.popup.animDriver > 0

        sourceComponent: Item {
            implicitWidth: Tokens.sizes.nexus.popupWidth
            implicitHeight: {
                let maxH = CUtils.clamp(root.popupHeight, Tokens.sizes.nexus.minPopupHeight, Tokens.sizes.nexus.maxPopupHeight);
                let contentH = list.contentHeight;
                if (contentH > 0) return Math.min(contentH, maxH);
                return maxH;
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                VerticalFadeListView {
                    id: list

                    function updateModel(): void {
                        let toplevels = [];
                        for (const toplevel of Kwin.windowList) {
                            if (toplevel.title || toplevel.class) {
                                toplevels.push(toplevel);
                            }
                        }
                        list.model = toplevels.sort((a, b) => (a.title ?? "").localeCompare(b.title ?? ""));
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    delegate: StateLayer {
                        id: windowItem

                        required property var modelData
                        required property int index

                        anchors.fill: undefined
                        anchors.left: list.contentItem.left
                        anchors.right: list.contentItem.right
                        implicitHeight: itemLayout.implicitHeight + itemLayout.anchors.margins * 2
                        radius: Tokens.rounding.small

                        onClicked: {
                            root.popup.open = false;
                            root.selected(modelData.class ?? "");
                        }

                        RowLayout {
                            id: itemLayout

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            IconImage {
                                asynchronous: true
                                implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                                source: Quickshell.iconPath(windowItem.modelData.class ?? "", "image-missing")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: windowItem.modelData.title ?? "Unknown"
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: windowItem.modelData.class ?? ""
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Component.onCompleted: updateModel()

                    Connections {
                        function onWindowListChanged(): void {
                            list.updateModel();
                        }

                        target: Kwin
                    }
                }
            }
        }
    }
}
