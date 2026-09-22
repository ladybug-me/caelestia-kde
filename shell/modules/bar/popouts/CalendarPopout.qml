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

ColumnLayout {
    id: root

    required property PopoutState popouts
    property bool _isSidebarOpen: false
    property real scaleOffset: 1.0
    property real fontScale: 1.0

    property date viewDate: new Date()
    readonly property int currMonth: viewDate.getMonth()
    readonly property int currYear: viewDate.getFullYear()

    width: 280 * scaleOffset
    spacing: Tokens.spacing.medium * scaleOffset

    StyledText {
        Layout.topMargin: Tokens.padding.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        text: qsTr("Calendar")
        font.weight: 500
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
    }

    StyledRect {
        Layout.fillWidth: true
        implicitWidth: inner.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
        implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: inner
            width: parent.width - Tokens.padding.medium * 2 * root.scaleOffset
            x: Tokens.padding.medium * root.scaleOffset
            y: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.extraSmall * root.scaleOffset

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall * root.scaleOffset

                IconButton {
                    isRound: true
                    icon: "chevron_left"
                    type: IconButton.Text
                    onClicked: root.viewDate = new Date(root.currYear, root.currMonth - 1, 1)
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: grid.title
                    font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                }

                IconButton {
                    isRound: true
                    icon: "chevron_right"
                    type: IconButton.Text
                    onClicked: root.viewDate = new Date(root.currYear, root.currMonth + 1, 1)
                }
            }

            GridLayout {
                id: daysRow
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 0
                rowSpacing: 0

                Repeater {
                    model: 7

                    delegate: StyledText {
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((index + Qt.locale().firstDayOfWeek) % 7, Locale.ShortFormat)
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        color: {
                            const dow = (index + Qt.locale().firstDayOfWeek) % 7;
                            return (dow === 0 || dow === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface;
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: grid.implicitHeight

                MonthGrid {
                    id: grid
                    month: root.currMonth
                    year: root.currYear
                    anchors.fill: parent
                    spacing: 3
                    locale: Qt.locale()

                    delegate: Item {
                        id: dayItem
                        required property var model
                        implicitWidth: implicitHeight
                        implicitHeight: text.implicitHeight + Tokens.padding.small

                        StyledText {
                            id: text
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: grid.locale.toString(dayItem.model.day)
                            color: {
                                if (dayItem.model.today) return Colours.palette.m3onPrimary;
                                const dow = dayItem.model.date.getDay();
                                if (dow === 0 || dow === 6) return Colours.palette.m3tertiary;
                                return Colours.palette.m3onSurfaceVariant;
                            }
                            opacity: dayItem.model.today || dayItem.model.month === grid.month ? 1 : 0.4
                            font: Tokens.font.body.small
                        }
                    }
                }

                MaterialShape {
                    id: todayIndicator

                    readonly property Item todayItem: grid.contentItem.children.find(c => c.model.today) ?? null
                    property Item today

                    onTodayItemChanged: {
                        if (todayItem)
                            today = todayItem;
                    }

                    x: today ? today.x + (today.width - implicitWidth) / 2 : 0
                    y: today ? today.y : 0

                    implicitSize: today ? Math.max(today.implicitWidth, today.implicitHeight) + Tokens.padding.extraSmall : 0
                    shape: MaterialShape.Sunny

                    clip: true
                    color: Colours.palette.m3primary

                    opacity: todayItem ? 1 : 0

                    Colouriser {
                        x: -todayIndicator.x
                        y: -todayIndicator.y

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
    }
}
