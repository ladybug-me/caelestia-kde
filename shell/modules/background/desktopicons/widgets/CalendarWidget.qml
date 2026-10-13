pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Month view. Scroll or use the arrows to change month; click the title to
// come back to today.
Item {
    id: root

    property var frame
    property var controller

    readonly property date today: Time.date
    property int year: today.getFullYear()
    property int month: today.getMonth()
    readonly property int firstDay: Qt.locale().firstDayOfWeek
    // Index of the first cell: days of the previous month shown before the 1st.
    readonly property int lead: (new Date(year, month, 1).getDay() - firstDay + 7) % 7

    function shift(delta: int): void {
        const d = new Date(year, month + delta, 1);
        year = d.getFullYear();
        month = d.getMonth();
    }

    function cellDate(index: int): date {
        return new Date(year, month, index - lead + 1);
    }

    WheelHandler {
        acceptedModifiers: Qt.NoModifier
        onWheel: event => root.shift(event.angleDelta.y > 0 ? -1 : 1)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Qt.locale().standaloneMonthName(root.month) + " " + root.year
                font: Tokens.font.title.small
                color: Colours.palette.m3primary

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.year = root.today.getFullYear();
                        root.month = root.today.getMonth();
                    }
                }
            }

            IconButton {
                type: IconButton.Text
                icon: "chevron_left"
                onClicked: root.shift(-1)
            }

            IconButton {
                type: IconButton.Text
                icon: "chevron_right"
                onClicked: root.shift(1)
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: 0
            columnSpacing: 0

            Repeater {
                model: 7

                StyledText {
                    required property int index

                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((root.firstDay + index) % 7, Locale.NarrowFormat)
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }

            Repeater {
                model: 42

                Item {
                    id: day

                    required property int index
                    readonly property date date: root.cellDate(index)
                    readonly property bool inMonth: date.getMonth() === root.month
                    readonly property bool isToday: date.toDateString() === root.today.toDateString()

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledRect {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 2
                        height: width
                        radius: width / 2
                        color: day.isToday ? Colours.palette.m3primary : "transparent"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: day.date.getDate()
                        font: Tokens.font.label.medium
                        color: day.isToday ? Colours.palette.m3onPrimary : day.inMonth ? Colours.palette.m3onSurface : Colours.palette.m3outlineVariant
                    }
                }
            }
        }
    }
}
