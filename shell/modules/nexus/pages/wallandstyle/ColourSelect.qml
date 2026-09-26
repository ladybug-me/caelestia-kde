pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.services
import qs.modules.nexus.common

PageBase {
    id: root

    property var lightSchemes: []
    property var darkSchemes: []

    function parseSchemeList(json: string): void {
        const light = [];
        const dark = [];
        try {
            const entries = JSON.parse(json);
            for (const s of entries) {
                const entry = { name: s.name, flavour: s.flavour, mode: s.mode, colours: s.colours };
                if (String(s.mode).toLowerCase().includes("light"))
                    light.push(entry);
                else
                    dark.push(entry);
            }
        } catch (e) {
            // Leave the lists empty on parse failure.
        }
        root.lightSchemes = light;
        root.darkSchemes = dark;
    }

    title: qsTr("Colors")
    isSubPage: true

    Component.onCompleted: {
        Schemes.reload();
        schemeListProc.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledRect {
            id: dynamicCard

            readonly property bool isSelected: Colours.scheme === "dynamic"

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            implicitHeight: dynamicRow.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
            border.width: isSelected ? 2 : 1
            border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

            StateLayer {
                radius: parent.radius
                onClicked: {
                    // On a fresh install the deploy script writes path.txt directly, so there
                    // is nothing derived yet and a bare `scheme set -n dynamic` fails. Seeding
                    // the wallpaper first is what makes it work, and the two have to be one
                    // process because the switch reads the path the seed writes.
                    const wall = Wallpapers.actualCurrent || Wallpapers.fallback;
                    const smartArg = Colours.smartArg.join(" ");
                    Quickshell.execDetached(["sh", "-c",
                        `caelestia wallpaper -f "$1" ${smartArg} >/dev/null 2>&1; caelestia scheme set ${smartArg} -n dynamic`,
                        "--", wall]);
                }
            }

            RowLayout {
                id: dynamicRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                StyledRect {
                    Layout.preferredWidth: Tokens.sizes.launcher.itemHeight
                    Layout.preferredHeight: Tokens.sizes.launcher.itemHeight

                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
                    color: Colours.palette.m3surface
                    radius: Tokens.rounding.full

                    Item {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right

                        width: parent.width / 2
                        clip: true

                        StyledRect {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right

                            width: parent.width
                            color: Colours.palette.m3primary
                            radius: Tokens.rounding.full
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Dynamic")
                        font: Tokens.font.title.small
                        color: dynamicCard.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Colors that follow your wallpaper")
                        font: Tokens.font.body.medium
                        color: dynamicCard.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    }
                }

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    visible: dynamicCard.isSelected
                    text: "check"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }

                IconButton {
                    id: settingsBtn

                    Layout.alignment: Qt.AlignVCenter
                    icon: "settings"
                    type: IconButton.Tonal
                    onClicked: root.nState.openSubPage(10)
                }
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.large
            text: qsTr("Light")
            font: Tokens.font.title.medium
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.medium

            Repeater {
                model: root.lightSchemes

                PaletteCard {}
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.large
            text: qsTr("Dark")
            font: Tokens.font.title.medium
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.medium

            Repeater {
                model: root.darkSchemes

                PaletteCard {}
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.large
            text: qsTr("Variants")
            font: Tokens.font.title.medium
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.medium

            Repeater {
                model: M3Variants.list

                StyledRect {
                    id: varDelegateRect

                    required property var modelData

                    readonly property bool isSelected: modelData?.variant === Schemes.currentVariant

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    implicitHeight: varCol.implicitHeight + Tokens.padding.large * 2
                    radius: Tokens.rounding.large
                    color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
                    border.width: isSelected ? 2 : 1
                    border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

                    StateLayer {
                        radius: parent.radius
                        onClicked: varDelegateRect.modelData?.onClicked(null)
                    }

                    RowLayout {
                        id: varCol

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.large

                        MaterialIcon {
                            Layout.alignment: Qt.AlignTop
                            text: varDelegateRect.modelData?.icon ?? ""
                            fontStyle: Tokens.font.icon.extraLarge
                            color: varDelegateRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                Layout.fillWidth: true
                                text: varDelegateRect.modelData?.name ?? ""
                                font: Tokens.font.title.small
                                color: varDelegateRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: varDelegateRect.modelData?.description ?? ""
                                font: Tokens.font.body.medium
                                color: varDelegateRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }





        Process {
            id: schemeListProc

            command: ["caelestia", "scheme", "list", "--flat"]
            stdout: StdioCollector {
                onStreamFinished: root.parseSchemeList(text)
            }
        }
    }

    component PaletteCard: StyledRect {
        id: card

        required property var modelData

        readonly property bool isSelected: `${modelData?.name} ${modelData?.flavour}` === Schemes.currentScheme && ((modelData?.mode === "light") === Colours.light)

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        implicitHeight: cardRow.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        border.width: isSelected ? 2 : 1
        border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

        StateLayer {
            radius: parent.radius
            onClicked: {
                // The card carries the whole palette, so the shell can show the result of this
                // switch at once instead of waiting for the render and the fan out to finish.
                Colours.previewNamed(card.modelData.name, card.modelData.flavour, card.modelData.colours, card.modelData.mode === "light");
                setScheme.command = ["caelestia", "scheme", "set", "-n", card.modelData.name,
                    "-f", card.modelData.flavour, "-m", card.modelData.mode, ...Colours.smartArg];
                setScheme.running = true;
            }
        }

        // A switch that fails writes no scheme, so the preview standing in for it would keep
        // showing colors that are not coming. A successful one is ended by the write itself.
        Process {
            id: setScheme

            onExited: code => {
                if (code !== 0)
                    Colours.clearPreview();
            }
        }

        RowLayout {
            id: cardRow

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.large

            StyledRect {
                Layout.preferredWidth: Tokens.sizes.launcher.itemHeight
                Layout.preferredHeight: Tokens.sizes.launcher.itemHeight

                border.width: 1
                border.color: Qt.alpha(`#${card.modelData?.colours?.outline}`, 0.5)
                color: `#${card.modelData?.colours?.surface}`
                radius: Tokens.rounding.full

                Item {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right

                    width: parent.width / 2
                    clip: true

                    StyledRect {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right

                        width: parent.width
                        color: `#${card.modelData?.colours?.primary}`
                        radius: Tokens.rounding.full
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData?.flavour ?? ""
                    font: Tokens.font.title.small
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData?.name ?? ""
                    font: Tokens.font.body.medium
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                }
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                visible: card.isSelected
                text: "check"
                color: Colours.palette.m3onSecondaryContainer
                fontStyle: Tokens.font.icon.large
            }
        }
    }
}
