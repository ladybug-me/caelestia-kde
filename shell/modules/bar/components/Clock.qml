pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    property var bar: null
    readonly property var popouts: bar?.popouts ?? null

    readonly property color colour: Colours.palette.m3tertiary
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)
    readonly property int barThickness: Math.round(Tokens.sizes.bar.innerWidth * Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0))

    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    // All three digit pairs share one font: the widest pair sets the scale so the
    // clock does not jitter as the digits change. Seconds are excluded from the
    // width comparison because they change too often to re-measure from.
    function fontFor(text: string, metricWidth: int): font {
        const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / metricWidth);
        return root.font.width(scale * 100).letterSpacing(scale).build();
    }

    implicitWidth: isHorizontal ? (horizontalLayout.implicitWidth + root.padding * 2) : barThickness
    implicitHeight: isHorizontal ? barThickness : (verticalLayout.implicitHeight + root.padding * 2)

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            const popouts = root.popouts;
            if (!popouts)
                return;

            if (mouse.button === Qt.RightButton) {
                if (popouts.hasCurrent && popouts.currentName === "clockcontext") {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "clockcontext";
                    popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                    popouts.hasCurrent = true;
                }
            } else if (mouse.button === Qt.LeftButton) {
                if (popouts.hasCurrent && (popouts.currentName === "clock" || popouts.currentName === "clockcontext")) {
                    popouts.hasCurrent = false;
                } else if (Config.bar.popouts.clock) {
                    popouts.currentName = "clock";
                    popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    RowLayout {
        id: horizontalLayout

        anchors.centerIn: parent
        visible: isHorizontal
        spacing: Tokens.spacing.extraSmall

        Loader {
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: Config.bar.clock.showDate
            text: Time.format("ddd")
            font: Tokens.font.body.small
            color: root.colour
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: Config.bar.clock.showDate
            text: Time.format("d")
            font: Tokens.font.body.small
            color: root.colour
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            visible: Config.bar.clock.showDate

            color: root.colour
            opacity: 0.2
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: Time.hourStr
            font: root.font.build()
            color: root.colour
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: ":"
            font: root.font.build()
            color: root.colour
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: Time.minuteStr
            font: root.font.build()
            color: root.colour
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: Config.bar.clock.showSeconds
            text: ":" + Time.format("ss")
            font: root.font.build()
            color: root.colour
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: Units.twelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }
    }

    ColumnLayout {
        id: verticalLayout

        anchors.centerIn: parent
        visible: !isHorizontal
        spacing: Tokens.spacing.extraSmall

        Loader {
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: Config.bar.clock.showDate

            horizontalAlignment: StyledText.AlignHCenter
            text: Time.format("ddd\nd")
            font: Tokens.font.body.small
            color: root.colour
        }

        Rectangle {
            Layout.fillWidth: true
            visible: Config.bar.clock.showDate
            implicitHeight: 1
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.hourStr
            font: root.fontFor(text, hourMetrics.width)
            color: root.colour

            TextMetrics {
                id: hourMetrics

                font: root.font.build()
                text: Time.hourStr
            }
        }

        StyledText {
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            text: Time.minuteStr
            font: root.fontFor(text, minMetrics.width)
            color: root.colour

            TextMetrics {
                id: minMetrics

                font: root.font.build()
                text: Time.minuteStr
            }
        }

        StyledText {
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            visible: Config.bar.clock.showSeconds
            text: Time.format("ss")
            font: root.fontFor(text, secMetrics.width)
            color: root.colour

            TextMetrics {
                id: secMetrics

                font: root.font.build()
                text: Time.format("ss")
            }
        }

        Loader {
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Units.twelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }
    }
}
