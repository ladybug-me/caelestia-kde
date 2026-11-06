pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

/// A month at a glance: the navigation row, the weekday header and the day grid, with a
/// dot on every day that has events and one indicator on the day being looked at.
///
/// The bar popout and the dashboard both show this; it owns no date of its own, so the
/// owner keeps `viewDate` (and, when `selectable`, the picked day) wherever it already
/// stores its state.
ColumnLayout {
    id: root

    property date viewDate: new Date()
    /// The day the indicator sits on. An invalid date means "today".
    property date highlightedDate
    /// Whether days can be picked. The dashboard only shows the month.
    property bool selectable: false
    property real scaleOffset: 1
    property real fontScale: 1

    readonly property int currMonth: root.viewDate.getMonth()
    readonly property int currYear: root.viewDate.getFullYear()
    readonly property date markedDate: isNaN(root.highlightedDate?.getTime() ?? NaN) ? new Date() : root.highlightedDate

    signal monthShifted(int delta)
    signal todayRequested()
    signal dayClicked(date date)

    function isSameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function isMarked(date: date): bool {
        return root.isSameDay(date, root.markedDate);
    }

    function isToday(date: date): bool {
        return root.isSameDay(date, new Date());
    }

    function isCurrentMonth(): bool {
        const now = new Date();
        return root.currMonth === now.getMonth() && root.currYear === now.getFullYear();
    }

    spacing: Tokens.spacing.extraSmall * root.scaleOffset

    CalendarMonthSlide {
        id: monthSlide

        shownDate: root.viewDate
        offset: Tokens.padding.extraLarge * root.scaleOffset
    }

    RowLayout {
        id: monthNavigationRow

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall * root.scaleOffset

        IconButton {
            isRound: true
            icon: "chevron_left"
            type: IconButton.Text
            font: Tokens.font.icon.builders.small.weight(Font.Bold).size(Tokens.font.icon.builders.small.build().pointSize * root.fontScale).build()
            padding: Tokens.padding.small * root.scaleOffset
            onClicked: root.monthShifted(-1)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            implicitWidth: monthYearDisplay.implicitWidth + Tokens.padding.large * 2 * root.scaleOffset
            implicitHeight: monthYearDisplay.implicitHeight + Tokens.padding.extraSmall * 2 * root.scaleOffset

            StateLayer {
                color: Colours.palette.m3primary
                radius: pressed ? Tokens.rounding.small * root.scaleOffset : height / 2
                disabled: root.isCurrentMonth()
                onClicked: root.todayRequested()

                Behavior on radius {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            StyledText {
                id: monthYearDisplay

                opacity: monthSlide.animOpacity
                transform: Translate {
                    x: monthSlide.animTranslate
                }

                anchors.centerIn: parent
                text: grid.title
                color: Colours.palette.m3primary
                font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).size(Tokens.font.title.builders.small.build().pointSize * root.fontScale).build()
            }
        }

        IconButton {
            isRound: true
            icon: "chevron_right"
            type: IconButton.Text
            font: Tokens.font.icon.builders.small.weight(Font.Bold).size(Tokens.font.icon.builders.small.build().pointSize * root.fontScale).build()
            padding: Tokens.padding.small * root.scaleOffset
            onClicked: root.monthShifted(1)
        }
    }

    DayOfWeekRow {
        id: daysRow

        Layout.fillWidth: true
        locale: grid.locale

        delegate: StyledText {
            required property var model

            horizontalAlignment: Text.AlignHCenter
            text: model.shortName
            font: Tokens.font.body.builders.small.weight(Font.Medium).size(Tokens.font.body.builders.small.build().pointSize * root.fontScale).build()
            color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: grid.implicitHeight

        opacity: monthSlide.animOpacity
        transform: Translate {
            x: monthSlide.animTranslate
        }

        MonthGrid {
            id: grid

            month: root.currMonth
            year: root.currYear

            anchors.fill: parent

            spacing: 3 * root.scaleOffset
            locale: Qt.locale()

            delegate: Item {
                id: dayItem

                required property var model

                implicitWidth: implicitHeight
                implicitHeight: text.implicitHeight + Tokens.padding.small * root.scaleOffset

                StyledText {
                    id: text

                    anchors.centerIn: parent

                    horizontalAlignment: Text.AlignHCenter
                    text: grid.locale.toString(dayItem.model.day)
                    color: {
                        if (root.isMarked(dayItem.model.date))
                            return Colours.palette.m3onPrimary;
                        if (root.isToday(dayItem.model.date))
                            return Colours.palette.m3primary;
                        if (dayItem.model.date.getDay() === 0 || dayItem.model.date.getDay() === 6)
                            return Colours.palette.m3tertiary;

                        return Colours.palette.m3onSurfaceVariant;
                    }
                    opacity: root.isToday(dayItem.model.date) || dayItem.model.month === grid.month ? 1 : 0.4
                    font: Tokens.font.body.builders.small.size(Tokens.font.body.small.pointSize * root.fontScale).build()
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    implicitWidth: 3 * root.scaleOffset
                    implicitHeight: 3 * root.scaleOffset
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary
                    // The marked day already carries the indicator shape.
                    visible: !root.isMarked(dayItem.model.date) && CalendarEvents.hasEventsOn(dayItem.model.date)
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    disabled: !root.selectable
                    onClicked: root.dayClicked(dayItem.model.date)
                }
            }
        }

        MaterialShape {
            id: markedIndicator

            readonly property Item markedItem: grid.contentItem.children.find(c => root.isMarked(c.model.date)) ?? null
            property Item day

            onMarkedItemChanged: {
                if (markedItem)
                    day = markedItem;
            }

            x: day ? day.x + (day.width - implicitWidth) / 2 : 0
            y: day ? day.y + (day.height - implicitHeight) / 2 : 0

            implicitSize: day ? Math.max(day.implicitWidth, day.implicitHeight) + Tokens.padding.extraSmall * 2 * root.scaleOffset : 0
            shape: MaterialShape.Sunny

            clip: true
            color: Colours.palette.m3primary

            opacity: markedItem ? 1 : 0

            Colouriser {
                x: -markedIndicator.x
                y: -markedIndicator.y

                implicitWidth: grid.width
                implicitHeight: grid.height

                source: grid
                sourceColor: Colours.palette.m3onSurface
                colorizationColor: Colours.palette.m3onPrimary
            }

            Behavior on x {
                Anim {}
            }

            Behavior on y {
                Anim {}
            }
        }
    }
}
