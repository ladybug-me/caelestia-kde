pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Media")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Configuration")
        }

        ToggleRow {
            first: true
            text: qsTr("Background")
            subtext: qsTr("Render a solid background behind the widget")
            checked: Config.bar.media.background
            onToggled: {
                GlobalConfig.bar.media.background = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Show visualiser")
            subtext: qsTr("Display animated frequency bars next to the title")
            checked: Config.bar.media.showVisualiser
            onToggled: {
                GlobalConfig.bar.media.showVisualiser = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Inverted text direction")
            subtext: qsTr("Rotate the title the opposite way when the bar is vertical")
            checked: Config.bar.media.inverted
            onToggled: {
                GlobalConfig.bar.media.inverted = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Auto-hide")
            subtext: qsTr("Hide the widget when no media source is available")
            checked: Config.bar.media.autoHide
            onToggled: {
                GlobalConfig.bar.media.autoHide = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Show title")
            subtext: qsTr("Show the track title in the bar, otherwise show an icon")
            checked: Config.bar.media.showTitle
            onToggled: {
                GlobalConfig.bar.media.showTitle = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Widget")
        }

        StepperRow {
            first: true
            label: qsTr("Max title length")
            subtext: qsTr("Character count before the track title is cut off")
            value: Config.bar.media.maxTitleLength
            from: 5
            to: 100
            stepSize: 1
            onMoved: v => {
                GlobalConfig.bar.media.maxTitleLength = Math.round(v);
                GlobalConfig.save();
            }
        }

        TextFieldRow {
            last: true
            label: qsTr("Sources")
            subtext: qsTr("Player names to follow, comma-separated; empty follows anything")
            value: (Config.bar.media.sources || []).join(", ")
            onEditingFinished: value => {
                GlobalConfig.bar.media.sources = value.split(",").map(s => s.trim()).filter(s => s.length > 0);
                GlobalConfig.save();
            }
        }
    }
}
