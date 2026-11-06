pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    /// The KWin effects this page offers, as data: adding one is a row here rather than
    /// a fourth near-identical toggle.
    readonly property var effectRows: [
        {
            id: "zoom",
            label: qsTr("Magnifier"),
            subtext: qsTr("Load KWin's zoom effect (Meta+= by default)")
        },
        {
            id: "invert",
            label: qsTr("Invert colours"),
            subtext: qsTr("Load KWin's colour inversion effect")
        },
        {
            id: "colorblindnesscorrection",
            label: qsTr("Colour filters"),
            subtext: qsTr("Load KWin's colour blindness correction effect")
        }
    ]

    function systemTextStatus(): string {
        if (!Accessibility.followSystem)
            return qsTr("The shell keeps the scale set below, whatever KDE's text size is");
        if (Accessibility.systemPointSize > 0)
            return qsTr("KDE's text is %1 pt, so the shell follows at %2%").arg(Accessibility.systemPointSize).arg(Math.round(Accessibility.systemScale * 100));

        return qsTr("KDE is using its default text size, so the shell stays at 100%");
    }

    title: qsTr("Accessibility")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Text")
        }

        ToggleRow {
            first: true
            text: qsTr("Follow system text size")
            subtext: qsTr("Match the text size set in KDE's settings")
            reset: ({ node: GlobalConfig.appearance.font, setting: "followSystemScale" })
            checked: GlobalConfig.appearance.font.followSystemScale
            onToggled: {
                GlobalConfig.appearance.font.followSystemScale = checked;
                GlobalConfig.save();
            }
        }

        StepperRow {
            label: qsTr("Font scale")
            subtext: qsTr("Multiplier applied to every piece of text the shell draws")
            reset: ({ node: GlobalConfig.appearance.font, setting: "scale" })
            value: GlobalConfig.appearance.font.scale
            from: 0.5
            to: 2
            stepSize: 0.05
            onMoved: v => {
                GlobalConfig.appearance.font.scale = v;
                GlobalConfig.appearance.font.followSystemScale = false;
                GlobalConfig.save();
            }
        }

        InfoRow {
            last: true
            icon: "info"
            Layout.fillWidth: true
            wrapSubtext: true
            subtext: root.systemTextStatus()
        }

        SectionHeader {
            text: qsTr("Motion")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Reduce motion")
            subtext: qsTr("Land every animation immediately instead of animating it")
            reset: ({ node: GlobalConfig.appearance.anim, setting: "enabled" })
            checked: !GlobalConfig.appearance.anim.enabled
            onToggled: {
                GlobalConfig.appearance.anim.enabled = !checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Screen")
        }

        Repeater {
            model: root.effectRows

            delegate: ToggleRow {
                required property var modelData
                required property int index

                first: index === 0
                //last: index === root.effectRows.length - 1
                text: modelData.label
                subtext: modelData.subtext
                checked: Accessibility.isEffectLoaded(modelData.id)
                onToggled: Accessibility.setEffect(modelData.id, checked)
            }
        }

        InfoRow {
            last: true
            Layout.fillWidth: true
            icon: "info"
            wrapSubtext: true
            //label: qsTr("These are KWin effects, so the shortcuts and the filter itself (protanopia, deuteranopia, ...) are set in System Settings -> Accessibility. Switching one on here loads it for the session.")
            subtext: qsTr("These are KWin effects, so the shortcuts and the filter itself (protanopia, deuteranopia, ...) are set in System Settings -> Accessibility. Switching one on here loads it for the session.")
        }

        SectionHeader {
            text: qsTr("Screen reader")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: readerRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: readerRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: Accessibility.screenReaderInstalled ? qsTr("Orca is installed") : qsTr("Orca is not installed — install the orca package to use it")
                    color: Accessibility.screenReaderInstalled ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
                    font: NexusStyle.secondaryFont
                    elide: Text.ElideRight
                }

                TextButton {
                    text: qsTr("Start Orca")
                    type: Accessibility.screenReaderInstalled ? TextButton.Filled : TextButton.Tonal
                    enabled: Accessibility.screenReaderInstalled
                    onClicked: Accessibility.startScreenReader()
                }
            }
        }
    }
}
