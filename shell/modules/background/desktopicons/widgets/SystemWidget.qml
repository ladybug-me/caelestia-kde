pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

// CPU, GPU, memory and disk use. Shows more the bigger it is: rings when
// small, meters with temperatures in between, and usage details with a
// network graph when wide.
Item {
    id: root

    property var frame
    property var controller

    // Size in cells. Width picks the layout: rings at 2, meters at 3,
    // meters with usage and a network column from 4. A third row adds the
    // speeds, a detail line under each meter and network totals.
    readonly property int cols: frame?.span.w ?? 3
    readonly property bool tall: (frame?.span.h ?? 2) >= 3
    readonly property int tier: cols <= 2 ? 0 : cols === 3 ? 1 : 2
    readonly property bool hasGpu: Gpu.type !== Gpu.None && !isNaN(Gpu.percentage)

    function percent(value: real): string {
        return `${Math.round((isNaN(value) ? 0 : value) * 100)}%`;
    }

    function temp(celsius: real): string {
        return celsius > 0 ? Units.formatSensorTemp(celsius) : "";
    }

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Gpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    ServiceRef {
        service: NetworkUsage
    }

    // Small: one ring per resource. Each layout only exists while it is the
    // one shown, so the hidden one does not keep redrawing the desktop.
    Loader {
        anchors.fill: parent
        active: root.tier === 0

        sourceComponent: GridLayout {
            columns: 2
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            Ring {
                label: qsTr("CPU")
                value: Cpu.percentage
            }

            Ring {
                visible: root.hasGpu
                label: qsTr("GPU")
                value: Gpu.percentage
            }

            Ring {
                label: qsTr("Memory")
                value: Memory.percentage
            }

            Ring {
                label: qsTr("Disk")
                value: Storage.percentage
            }
        }
    }

    // Medium and large: meters, plus network.
    Loader {
        anchors.fill: parent
        active: root.tier > 0

        sourceComponent: RowLayout {
            spacing: Tokens.spacing.large

            // Nothing fills the height, so the rows share the spare room evenly
            // and the top and bottom gaps match.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.small

                Meter {
                    icon: "memory"
                    label: qsTr("CPU")
                    value: Cpu.percentage
                    extra: root.temp(Cpu.temperature)
                    // Drop the "8-Core Processor" tail; the model says enough.
                    detail: Cpu.name.replace(/\s*(\d+-Core\s*)?Processor\s*$/i, "")
                }

                Meter {
                    visible: root.hasGpu
                    icon: "developer_board"
                    label: qsTr("GPU")
                    value: Gpu.percentage
                    extra: root.temp(Gpu.temperature)
                    detail: Gpu.name
                }

                Meter {
                    icon: "memory_alt"
                    label: qsTr("Memory")
                    value: Memory.percentage
                    extra: root.tier === 2 && !root.tall ? usage : ""
                    detail: usage

                    readonly property string usage: Memory.total > 0 ? Units.formatKibUsage(Memory.used, Memory.total) : ""
                }

                Meter {
                    icon: "hard_disk"
                    label: qsTr("Disk")
                    value: Storage.percentage
                    extra: root.tier === 2 && !root.tall ? usage : ""
                    detail: usage

                    readonly property string usage: Storage.primaryDisk ? Units.formatKibUsage(Storage.primaryDisk.used, Storage.primaryDisk.total) : ""
                }

                // Medium widgets show the speeds under the meters when there is room.
                Speeds {
                    Layout.fillWidth: true
                    visible: root.tier === 1 && root.tall
                }
            }

            // Large widgets give the network a column of its own.
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: root.width * 0.4
                Layout.maximumWidth: root.width * 0.4
                visible: root.tier === 2
                spacing: Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    SparklineItem {
                        id: sparkline

                        property real targetMax: 1024
                        property real smoothMax: targetMax

                        anchors.fill: parent
                        visible: parent.height > 40
                        line1: NetworkUsage.uploadBuffer // qmllint disable missing-type
                        line1Color: Colours.palette.m3tertiary
                        line1FillAlpha: 0.15
                        line2: NetworkUsage.downloadBuffer // qmllint disable missing-type
                        line2Color: Colours.palette.m3secondary
                        line2FillAlpha: 0.2
                        maxValue: smoothMax
                        historyLength: NetworkUsage.historyLength

                        // No sliding between samples: on the desktop it would
                        // never stop and redraw the whole background window.
                        slideProgress: 1

                        Connections {
                            function onValuesChanged(): void {
                                sparkline.targetMax = Math.max(NetworkUsage.downloadBuffer.maximum, NetworkUsage.uploadBuffer.maximum, 1024);
                            }

                            target: NetworkUsage.downloadBuffer
                        }

                        Behavior on smoothMax {
                            Anim {}
                        }
                    }
                }

                Speeds {
                    Layout.fillWidth: true
                    stacked: true
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.tall
                    elide: Text.ElideRight
                    text: `↓${Units.formatBytes(NetworkUsage.downloadTotal ?? 0)} ↑${Units.formatBytes(NetworkUsage.uploadTotal ?? 0)}`
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }
        }
    }

    component Ring: ColumnLayout {
        id: ring

        required property string label
        required property real value

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            CircularProgress {
                id: progress

                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                value: ring.value
                strokeWidth: Math.max(3, Math.round(width / 14))
                fgColour: ring.value > 0.85 ? Colours.palette.m3error : Colours.palette.m3primary
                bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.15)

                StyledText {
                    anchors.centerIn: parent
                    text: root.percent(ring.value)
                    font: progress.width > 56 ? Tokens.font.label.large : Tokens.font.label.small
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: ring.label
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    component Meter: RowLayout {
        id: meter

        required property string icon
        required property string label
        required property real value
        property string extra
        // Second line under the label, such as the CPU model; tall widgets only.
        property string detail

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: meter.icon
            color: Colours.palette.m3primary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.minimumWidth: implicitWidth
                    text: meter.label
                    font: Tokens.font.label.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: meter.extra.length > 0 ? `${meter.extra} · ${root.percent(meter.value)}` : root.percent(meter.value)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: meter.detail.length > 0 && root.tall
                elide: Text.ElideRight
                text: meter.detail
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Qt.alpha(Colours.palette.m3onSurface, 0.15)

                StyledRect {
                    width: parent.width * Math.max(0, Math.min(1, isNaN(meter.value) ? 0 : meter.value))
                    height: parent.height
                    radius: parent.radius
                    color: meter.value > 0.85 ? Colours.palette.m3error : Colours.palette.m3primary
                }
            }
        }
    }

    // Download and upload speed, side by side or one per line.
    component Speeds: GridLayout {
        property bool stacked: false

        columns: stacked ? 2 : 4
        rowSpacing: 2
        columnSpacing: Tokens.spacing.medium

        MaterialIcon {
            text: "download"
            color: Colours.palette.m3secondary
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: Units.formatBytes(NetworkUsage.downloadSpeed ?? 0, true)
            font: Tokens.font.label.medium
        }

        MaterialIcon {
            text: "upload"
            color: Colours.palette.m3tertiary
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: Units.formatBytes(NetworkUsage.uploadSpeed ?? 0, true)
            font: Tokens.font.label.medium
        }
    }
}
