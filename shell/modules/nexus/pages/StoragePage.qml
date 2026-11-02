pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    function diskTitle(disk: var): string {
        return disk.removable ? qsTr("%1 (removable)").arg(disk.name) : disk.name;
    }

    function entryTitle(entry: var): string {
        return entry.label || entry.device;
    }

    function entryStatus(entry: var): string {
        const parts = entry.label ? [entry.device] : [];
        parts.push(entry.fstype.toUpperCase(), entry.size);
        if (entry.use)
            parts.push(qsTr("%1 used").arg(entry.use));
        if (entry.readOnly)
            parts.push(qsTr("read-only"));
        if (entry.mountpoints.length > 0)
            parts.push(entry.mountpoints.join(", "));
        return parts.join(" · ");
    }

    title: qsTr("Storage")

    // A stick can be plugged in while the page is open, so the list is re-read every
    // time the page is shown instead of trusting what was read last time.
    Component.onCompleted: Disks.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            visible: Disks.lastError !== ""
            text: Disks.lastError
            color: Colours.palette.m3error
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: Disks.loaded && Disks.lastError === "" && Disks.disks.length === 0
            text: qsTr("No disks were reported by lsblk.")
            color: Colours.palette.m3onSurfaceVariant
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }

        Repeater {
            model: Disks.disks

            delegate: ColumnLayout {
                id: diskSection

                required property var modelData
                required property int index

                readonly property var disk: diskSection.modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: diskSection.index === 0
                    text: root.diskTitle(diskSection.disk)
                }

                Repeater {
                    model: diskSection.disk.entries

                    delegate: ToggleRow {
                        id: filesystemRow

                        required property var modelData
                        required property int index

                        first: filesystemRow.index === 0
                        last: filesystemRow.index === diskSection.disk.entries.length - 1 && !diskSection.disk.removable
                        text: root.entryTitle(filesystemRow.modelData)
                        subtext: root.entryStatus(filesystemRow.modelData)
                        checked: filesystemRow.modelData.mountpoints.length > 0
                        // A filesystem the system is running from is shown, not offered:
                        // unmounting / or /boot is never what the click meant.
                        enabled: !Disks.working && !filesystemRow.modelData.system
                        onToggled: {
                            const device = filesystemRow.modelData.device;
                            if (filesystemRow.modelData.mountpoints.length > 0)
                                Disks.unmount(device);
                            else
                                Disks.mount(device);
                        }
                    }
                }

                // Not conditional on the filesystems above: a disk with none at all — a
                // stick that was never formatted — is exactly the one someone wants to
                // eject.
                NavRow {
                    visible: diskSection.disk.removable
                    first: diskSection.disk.entries.length === 0
                    last: true
                    icon: "eject"
                    label: qsTr("Eject")
                    status: diskSection.disk.mounted > 0 ? qsTr("Unmount everything on this disk first") : qsTr("Power the disk off before unplugging it")
                    onClicked: {
                        if (diskSection.disk.mounted === 0)
                            Disks.eject(diskSection.disk.device);
                    }
                }
            }
        }
    }
}
