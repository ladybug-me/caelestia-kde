pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus.common

DialogRowButton {
    id: root

    property string selectedFamily: ""
    property alias selectedItem: root.selectedFamily
    property bool allowAutomatic: false
    property string automaticLabel: qsTr("Automatic")
    property var customModel: null
    property string filter: ""
    property bool mono: false

    readonly property var allFamilies: {
        const families = root.customModel ? [...root.customModel] : [...Qt.fontFamilies()];
        families.sort((a, b) => a.localeCompare(b));
        if (root.allowAutomatic)
            return [""].concat(families);
        return families;
    }

    readonly property var filteredFamilies: {
        const q = root.filter.trim().toLowerCase();
        if (!q)
            return root.allFamilies;
        return root.allFamilies.filter(f => {
            if (!f)
                return root.automaticLabel.toLowerCase().includes(q);
            return f.toLowerCase().includes(q);
        });
    }

    signal fontSelected(family: string)

    icon: "font_download"
    label: root.mono ? qsTr("Choose a monospace font") : qsTr("Choose a system font")
    header: root.mono ? qsTr("Monospace fonts") : qsTr("System fonts")
    acceptLabel: qsTr("Apply")
    acceptAllowed: root.allowAutomatic ? true : root.selectedFamily.length > 0
    separateContent: true
    horizontalContentMargin: -Tokens.padding.small

    onOpenChanged: {
        if (open)
            root.filter = "";
    }

    onAccepted: {
        if (root.allowAutomatic || root.selectedFamily.length > 0)
            root.fontSelected(root.selectedFamily);
    }

    content: Component {
        ColumnLayout {
            spacing: Tokens.spacing.small

            StyledTextField {
                id: searchField

                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.medium
                Layout.rightMargin: Tokens.padding.medium
                placeholderText: qsTr("Search fonts...")
                text: root.filter
                onTextEdited: root.filter = text
            }

            VerticalFadeListView {
                id: listView

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                topMargin: Tokens.padding.small
                bottomMargin: Tokens.padding.large
                model: root.filteredFamilies

                delegate: StyledRect {
                    id: fontItem

                    required property string modelData

                    readonly property bool selected: root.selectedFamily === modelData

                    anchors.left: ListView.view.contentItem.left
                    anchors.right: ListView.view.contentItem.right
                    anchors.margins: 1
                    implicitHeight: fontLabel.implicitHeight + Tokens.padding.medium * 2
                    radius: stateLayer.pressed ? Tokens.rounding.extraSmall : selected ? Tokens.rounding.largeIncreased : Tokens.rounding.medium
                    color: Qt.alpha(Colours.palette.m3primaryContainer, selected ? 1 : 0)

                    Behavior on radius {
                        Anim {
                            type: Anim.SlowEffects
                        }
                    }

                    StateLayer {
                        id: stateLayer

                        anchors.fill: parent
                        radius: parent.radius
                        color: fontItem.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        onClicked: root.selectedFamily = fontItem.modelData
                    }

                    StyledText {
                        id: fontLabel

                        anchors.left: parent.left
                        anchors.right: fontItem.selected ? checkIcon.left : parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.large
                        anchors.rightMargin: fontItem.selected ? Tokens.spacing.medium : anchors.margins
                        text: fontItem.modelData || root.automaticLabel
                        color: fontItem.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        font.family: fontItem.modelData || Tokens.font.body.medium.family
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        id: checkIcon

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.large
                        text: "check"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.medium
                        opacity: fontItem.selected ? 1 : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.SlowEffects
                            }
                        }
                    }
                }
            }
        }
    }
}
