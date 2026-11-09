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

    title: qsTr("Muted apps")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        PolicySection {
            first: true
            title: qsTr("Notifications turned off")
            description: qsTr("Nothing arrives from these applications: no banner, no sound, and nothing added to the notification list.")
            status: qsTr("Turn its notifications off completely")
            apps: GlobalConfig.notifs.mutedApps
            write: apps => {
                GlobalConfig.notifs.mutedApps = apps;
                GlobalConfig.save();
            }
        }

        PolicySection {
            title: qsTr("Notifications without sound")
            description: qsTr("These applications still show their notifications. Only the sound is skipped.")
            status: qsTr("Keep its notifications, drop the sound")
            apps: GlobalConfig.audio.sounds.disabledNotifApps
            write: apps => {
                GlobalConfig.audio.sounds.disabledNotifApps = apps;
                GlobalConfig.save();
            }
        }
    }

    /// One per-app policy: the list it edits, and everything the page says about it.
    /// Which config list a section owns is one line where the section is used, so there
    /// is no name for every function to dispatch on and no branch to keep in step.
    component PolicySection: ColumnLayout {
        id: section

        required property string title
        required property string description
        required property string status
        /// The applications this policy applies to, and what writing them means.
        required property var apps
        required property var write

        property bool first

        function add(name: string): void {
            const wanted = name.trim();
            if (wanted === "" || section.apps.includes(wanted))
                return;

            section.write([...section.apps, wanted]);
        }

        function remove(name: string): void {
            section.write(section.apps.filter(app => app !== name));
        }

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: section.first
            text: section.title
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: helper.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: helper

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: section.description
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                wrapMode: Text.Wrap
            }
        }

        AppPickerRow {
            last: true
            icon: "add"
            label: qsTr("Add an application")
            status: section.status
            exclude: Array.from(section.apps)
            onSelected: name => section.add(name)
        }

        Flow {
            Layout.fillWidth: true
            visible: section.apps.length > 0
            spacing: Tokens.spacing.small

            Repeater {
                model: section.apps

                delegate: RemovableChip {
                    required property string modelData

                    label: modelData
                    onRemoved: section.remove(modelData)
                }
            }
        }
    }
}
